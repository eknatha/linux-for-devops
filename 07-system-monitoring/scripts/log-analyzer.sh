#!/bin/bash
# =============================================================================
# log-analyzer.sh
# Parse, summarise, and report on system and application logs.
# Extracts error rates, top offenders, security events, and anomalies.
# eknatha
# Usage:
#   ./log-analyzer.sh [--type TYPE] [--since DURATION] [--output FILE]
# 
# Options:
#   --type TYPE        Log type: system|nginx|apache|auth|app|all (default: all)
#   --since DURATION   Time window: "1 hour ago", "today", "2024-01-15" (default: 1 hour ago)
#   --log-file FILE    Custom log file to analyse
#   --output FILE      Save report to file
#   --slack WEBHOOK    Post summary to Slack
#   --top N            Show top N entries (default: 10)
#   --error-only       Only show error/warn entries
#
# Examples:
#   sudo ./log-analyzer.sh --type auth --since "24 hours ago"
#   sudo ./log-analyzer.sh --type nginx --log-file /var/log/nginx/access.log
#   sudo ./log-analyzer.sh --type all --since today --output /tmp/log-report.txt
#
# Author : Eknatha
# Repo   : linux-for-devops/07-system-monitoring
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
#  Defaults
# --------------------------------------------------------------------------- #
LOG_TYPE="all"
SINCE="1 hour ago"
CUSTOM_LOG=""
OUTPUT_FILE=""
SLACK_WEBHOOK=""
TOP_N=10
ERROR_ONLY=false
HOSTNAME_VAL=$(hostname -f 2>/dev/null || hostname)
REPORT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')

# --------------------------------------------------------------------------- #
#  Colours
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

hdr()  { echo ""; echo -e "${BOLD}════════════════════════════════════════${RESET}"; \
         echo -e "${BOLD}  $*${RESET}"; \
         echo -e "${BOLD}════════════════════════════════════════${RESET}"; }
info() { echo -e "  ${CYAN}➜${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
ok()   { echo -e "  ${GREEN}✔${RESET}  $*"; }

# --------------------------------------------------------------------------- #
#  Argument parsing
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)       LOG_TYPE="$2";    shift 2 ;;
    --since)      SINCE="$2";       shift 2 ;;
    --log-file)   CUSTOM_LOG="$2";  shift 2 ;;
    --output)     OUTPUT_FILE="$2"; shift 2 ;;
    --slack)      SLACK_WEBHOOK="$2"; shift 2 ;;
    --top)        TOP_N="$2";       shift 2 ;;
    --error-only) ERROR_ONLY=true;  shift ;;
    -h|--help) sed -n '3,16p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$OUTPUT_FILE" ]] && exec > >(tee "$OUTPUT_FILE") 2>&1

# --------------------------------------------------------------------------- #
#  HEADER
# --------------------------------------------------------------------------- #
echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       Log Analyser Report                     ║${RESET}"
echo -e "${BOLD}║       Author: Eknatha                         ║${RESET}"
echo -e "${BOLD}╚═══════════════════════════════════════════════╝${RESET}"
echo ""
printf "  %-20s %s\n" "Host:"     "$HOSTNAME_VAL"
printf "  %-20s %s\n" "Date:"     "$REPORT_DATE"
printf "  %-20s %s\n" "Type:"     "$LOG_TYPE"
printf "  %-20s %s\n" "Since:"    "$SINCE"
printf "  %-20s %s\n" "Top N:"    "$TOP_N"

# --------------------------------------------------------------------------- #
#  SYSTEM JOURNAL ANALYSIS
# --------------------------------------------------------------------------- #
analyse_system() {
  hdr "System Journal Analysis"

  info "Log volume in window:"
  TOTAL=$(journalctl --since "$SINCE" --no-pager 2>/dev/null | grep -vc '^-- ' || echo 0)
  printf "  %-30s %s entries\n" "Total log entries:" "$TOTAL"

  echo ""
  info "Entries by priority:"
  for pri_name in emerg alert crit err warning notice info; do
    count=$(journalctl --since "$SINCE" -p "$pri_name" --no-pager 2>/dev/null | grep -vc '^-- ' || echo 0)
    printf "  %-12s %s\n" "${pri_name}:" "$count"
  done

  echo ""
  info "Top ${TOP_N} services by error count:"
  journalctl --since "$SINCE" -p err --no-pager 2>/dev/null \
    | grep -v '^-- ' \
    | awk '{print $5}' \
    | sed 's/\[.*\]//' \
    | sort | uniq -c | sort -rn \
    | head -"$TOP_N" \
    | awk '{printf "  %-5s %s\n", $1, $2}'

  echo ""
  info "Critical and emergency events:"
  journalctl --since "$SINCE" -p crit --no-pager 2>/dev/null \
    | grep -v '^-- ' | tail -20 | sed 's/^/  /' || echo "  None found."

  echo ""
  info "Kernel errors (dmesg):"
  journalctl -k --since "$SINCE" -p err --no-pager 2>/dev/null \
    | grep -v '^-- ' | tail -10 | sed 's/^/  /' || \
    dmesg -T --level=err,crit 2>/dev/null | tail -10 | sed 's/^/  /' || \
    echo "  None found."

  echo ""
  info "OOM kill events:"
  journalctl --since "$SINCE" --no-pager 2>/dev/null \
    | grep -i 'oom\|out of memory\|killed process' \
    | tail -5 | sed 's/^/  /' || echo "  None found."

  echo ""
  info "Failed systemd services:"
  systemctl --failed --plain --no-legend 2>/dev/null | awk '{print "  "$0}' || echo "  None."
}

# --------------------------------------------------------------------------- #
#  NGINX LOG ANALYSIS
# --------------------------------------------------------------------------- #
analyse_nginx() {
  hdr "Nginx Log Analysis"

  local ACCESS="/var/log/nginx/access.log"
  local ERROR="/var/log/nginx/error.log"
  [[ -n "$CUSTOM_LOG" ]] && ACCESS="$CUSTOM_LOG"

  if [[ ! -f "$ACCESS" ]]; then
    warn "Nginx access log not found: ${ACCESS}"
    return
  fi

  # Determine date filter for log (Combined Log Format: [10/Jan/2024:14:30:00 +0000])
  local DATE_FILTER
  DATE_FILTER=$(date '+%d/%b/%Y')

  info "Request volume (today: ${DATE_FILTER}):"
  TOTAL=$(grep "$DATE_FILTER" "$ACCESS" 2>/dev/null | wc -l || echo 0)
  printf "  Total requests: %s\n" "$TOTAL"

  echo ""
  info "HTTP status code breakdown:"
  grep "$DATE_FILTER" "$ACCESS" 2>/dev/null \
    | awk '{print $9}' \
    | sort | uniq -c | sort -rn \
    | awk '{printf "  HTTP %-4s %s requests\n", $2, $1}'

  echo ""
  info "Top ${TOP_N} URLs by request count:"
  grep "$DATE_FILTER" "$ACCESS" 2>/dev/null \
    | awk '{print $7}' \
    | sort | uniq -c | sort -rn \
    | head -"$TOP_N" \
    | awk '{printf "  %-5s %s\n", $1, $2}'

  echo ""
  info "Top ${TOP_N} client IPs:"
  grep "$DATE_FILTER" "$ACCESS" 2>/dev/null \
    | awk '{print $1}' \
    | sort | uniq -c | sort -rn \
    | head -"$TOP_N" \
    | awk '{printf "  %-8s %s\n", $1, $2}'

  echo ""
  info "5xx errors (server errors):"
  grep "$DATE_FILTER" "$ACCESS" 2>/dev/null \
    | awk '$9 ~ /^5/' \
    | tail -"$TOP_N" | sed 's/^/  /' || echo "  None found."

  echo ""
  info "4xx errors (client errors) — top ${TOP_N}:"
  grep "$DATE_FILTER" "$ACCESS" 2>/dev/null \
    | awk '$9 ~ /^4/ {print $9, $7}' \
    | sort | uniq -c | sort -rn \
    | head -"$TOP_N" \
    | awk '{printf "  %-5s HTTP %-4s %s\n", $1, $2, $3}'

  echo ""
  info "Nginx error log (last ${TOP_N} entries):"
  if [[ -f "$ERROR" ]]; then
    tail -"$TOP_N" "$ERROR" | sed 's/^/  /'
  else
    echo "  Error log not found: ${ERROR}"
  fi

  echo ""
  info "Requests per minute (last 10 minutes):"
  grep "$DATE_FILTER" "$ACCESS" 2>/dev/null \
    | awk '{print $4}' \
    | cut -d: -f1-3 \
    | sed 's/\[//' \
    | sort | uniq -c \
    | tail -10 \
    | awk '{printf "  %-30s %s req\n", $2, $1}'
}

# --------------------------------------------------------------------------- #
#  AUTH LOG ANALYSIS
# --------------------------------------------------------------------------- #
analyse_auth() {
  hdr "Authentication & Security Log Analysis"

  local AUTH_LOG="/var/log/auth.log"
  [[ ! -f "$AUTH_LOG" ]] && AUTH_LOG="/var/log/secure"   # RHEL/CentOS
  [[ -n "$CUSTOM_LOG" ]] && AUTH_LOG="$CUSTOM_LOG"

  info "SSH authentication events (journald):"
  echo ""

  info "Successful SSH logins:"
  journalctl -u sshd --since "$SINCE" --no-pager 2>/dev/null \
    | grep 'Accepted' \
    | awk '{printf "  %-15s from %-20s port %s\n", $9, $11, $13}' \
    | tail -"$TOP_N" || \
    grep 'Accepted password\|Accepted publickey' "$AUTH_LOG" 2>/dev/null \
    | tail -"$TOP_N" | sed 's/^/  /' || echo "  None found."

  echo ""
  info "Failed SSH login attempts:"
  FAIL_COUNT=$(journalctl -u sshd --since "$SINCE" --no-pager 2>/dev/null \
    | grep -c 'Failed password' || \
    grep -c 'Failed password' "$AUTH_LOG" 2>/dev/null || echo 0)
  printf "  Total failed attempts: %s\n" "$FAIL_COUNT"

  echo ""
  info "Top ${TOP_N} IPs with failed SSH logins:"
  journalctl -u sshd --since "$SINCE" --no-pager 2>/dev/null \
    | grep 'Failed password' \
    | awk '{print $11}' \
    | sort | uniq -c | sort -rn \
    | head -"$TOP_N" \
    | awk '{printf "  %-8s attempts from: %s\n", $1, $2}' || \
    grep 'Failed password' "$AUTH_LOG" 2>/dev/null \
    | awk '{print $(NF-3)}' \
    | sort | uniq -c | sort -rn \
    | head -"$TOP_N" \
    | awk '{printf "  %-8s %s\n", $1, $2}' || echo "  No data."

  echo ""
  info "Root login attempts:"
  journalctl -u sshd --since "$SINCE" --no-pager 2>/dev/null \
    | grep -i 'root' | tail -5 | sed 's/^/  /' || echo "  None found."

  echo ""
  info "sudo usage events:"
  journalctl _COMM=sudo --since "$SINCE" --no-pager 2>/dev/null \
    | grep -v '^-- ' | tail -"$TOP_N" | sed 's/^/  /' || \
    grep 'sudo' "$AUTH_LOG" 2>/dev/null | tail -"$TOP_N" | sed 's/^/  /' || \
    echo "  None found."

  echo ""
  info "User account modifications:"
  journalctl --since "$SINCE" --no-pager 2>/dev/null \
    | grep -iE 'useradd|usermod|userdel|groupadd|passwd|chage' \
    | tail -10 | sed 's/^/  /' || echo "  None found."

  echo ""
  info "Fail2ban bans (if running):"
  journalctl -u fail2ban --since "$SINCE" --no-pager 2>/dev/null \
    | grep 'Ban ' | tail -"$TOP_N" | sed 's/^/  /' || echo "  Fail2ban not running or no bans."
}

# --------------------------------------------------------------------------- #
#  CUSTOM APPLICATION LOG ANALYSIS
# --------------------------------------------------------------------------- #
analyse_app() {
  local log_file="${CUSTOM_LOG:-}"
  hdr "Application Log Analysis: ${log_file:-generic}"

  if [[ -z "$log_file" ]]; then
    warn "No log file specified. Use --log-file /path/to/app.log"
    return
  fi

  if [[ ! -f "$log_file" ]]; then
    warn "Log file not found: ${log_file}"
    return
  fi

  info "File: ${log_file}"
  printf "  %-20s %s\n" "Size:"    "$(du -sh "$log_file" | awk '{print $1}')"
  printf "  %-20s %s\n" "Lines:"   "$(wc -l < "$log_file")"
  printf "  %-20s %s\n" "Modified:" "$(stat -c '%y' "$log_file" | cut -d. -f1)"

  echo ""
  info "Error/Warning count:"
  for level in ERROR CRITICAL WARN WARNING FATAL; do
    count=$(grep -ci "$level" "$log_file" 2>/dev/null || echo 0)
    printf "  %-12s %s occurrences\n" "${level}:" "$count"
  done

  echo ""
  info "Last ${TOP_N} ERROR entries:"
  grep -iE 'ERROR|CRITICAL|FATAL' "$log_file" 2>/dev/null \
    | tail -"$TOP_N" | sed 's/^/  /' || echo "  None found."

  echo ""
  info "Most frequent error messages (top ${TOP_N}):"
  grep -iE 'ERROR|WARN|CRIT' "$log_file" 2>/dev/null \
    | sed 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9:\.]*Z\?//g' \
    | sed 's/\[.*\]//g' \
    | sort | uniq -c | sort -rn \
    | head -"$TOP_N" \
    | awk '{printf "  %-5s %s\n", $1, substr($0, index($0,$2))}' || echo "  No data."

  echo ""
  info "Log activity (lines per hour — last 24h):"
  if command -v awk &>/dev/null; then
    awk '{
      # Try to extract hour from common timestamp formats
      if (match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}/)) {
        hr = substr($0, RSTART+11, 2)
        hours[hr]++
      }
    }
    END {
      for (h in hours) printf "  Hour %-3s %s lines\n", h":", hours[h]
    }' "$log_file" | sort
  fi
}

# --------------------------------------------------------------------------- #
#  SUMMARY and Slack
# --------------------------------------------------------------------------- #
print_summary() {
  hdr "Report Summary"
  printf "  %-20s %s\n" "Host:"    "$HOSTNAME_VAL"
  printf "  %-20s %s\n" "Period:"  "Since $SINCE"
  printf "  %-20s %s\n" "Report:"  "$REPORT_DATE"
  [[ -n "$OUTPUT_FILE" ]] && printf "  %-20s %s\n" "Saved to:" "$OUTPUT_FILE"
}

send_slack_summary() {
  [[ -z "$SLACK_WEBHOOK" ]] && return
  local payload="{\"text\": \":mag: *Log Analysis — ${HOSTNAME_VAL}* (since: ${SINCE})\nReport generated at ${REPORT_DATE}. $([ -n "$OUTPUT_FILE" ] && echo "Saved to: ${OUTPUT_FILE}")\"}"
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-type: application/json' \
    --data "$payload" > /dev/null
}

# --------------------------------------------------------------------------- #
#  DISPATCH
# --------------------------------------------------------------------------- #
case "$LOG_TYPE" in
  system)  analyse_system ;;
  nginx)   analyse_nginx ;;
  apache)  CUSTOM_LOG="${CUSTOM_LOG:-/var/log/apache2/access.log}"; analyse_nginx ;;
  auth)    analyse_auth ;;
  app)     analyse_app ;;
  all)
    analyse_system
    analyse_auth
    [[ -f "/var/log/nginx/access.log" ]] && analyse_nginx
    [[ -n "$CUSTOM_LOG" ]] && analyse_app
    ;;
  *)
    echo "Unknown log type: $LOG_TYPE. Use: system|nginx|apache|auth|app|all" >&2
    exit 1
    ;;
esac

print_summary
send_slack_summary

# =============================================================================
# IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE
# Author : Eknatha
# Repo   : linux-for-devops/07-system-monitoring
# =============================================================================
