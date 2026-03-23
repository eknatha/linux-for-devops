#!/bin/bash
# =============================================================================
# health-check.sh
# Full system health snapshot — CPU, memory, disk, network, services, logs.
# Designed to run manually or via cron for scheduled health reports.
#
# Usage:
#   ./health-check.sh [--output FILE] [--slack WEBHOOK_URL] [--json] [--quiet]
#
# Options:
#   --output FILE        Save report to file (default: stdout)
#   --slack WEBHOOK_URL  Post alert summary to Slack channel
#   --json               Output machine-readable JSON summary
#   --quiet              Suppress stdout (use with --output or --slack)
#   --threshold-cpu N    CPU load ratio alert threshold (default: 1.5)
#   --threshold-mem N    Memory used % alert threshold (default: 85)
#   --threshold-disk N   Disk used % alert threshold (default: 80)
#
# Examples:
#   sudo ./health-check.sh
#   sudo ./health-check.sh --output /var/log/health-$(date +%F).log
#   sudo ./health-check.sh --slack https://hooks.slack.com/services/XXX/YYY/ZZZ
#   sudo ./health-check.sh --json | jq .
#
# Cron (daily at 8am):
#   0 8 * * * root /opt/scripts/health-check.sh --output /var/log/health-daily.log
#
# Author : Eknatha
# Repo   : linux-for-devops/07-system-monitoring
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
#  Colours
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

ok()    { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn()  { echo -e "  ${YELLOW}⚠${RESET}  $*"; WARN_COUNT=$((WARN_COUNT+1)); ALERTS+=("WARN: $*"); }
crit()  { echo -e "  ${RED}✘${RESET}  $*"; CRIT_COUNT=$((CRIT_COUNT+1)); ALERTS+=("CRIT: $*"); }
info()  { echo -e "  ${CYAN}➜${RESET}  $*"; }
hdr()   { echo ""; echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; \
          echo -e "${BOLD}  $*${RESET}"; \
          echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

# --------------------------------------------------------------------------- #
#  Defaults
# --------------------------------------------------------------------------- #
OUTPUT_FILE=""
SLACK_WEBHOOK=""
JSON_MODE=false
QUIET=false
THRESHOLD_CPU=1.5
THRESHOLD_MEM=85
THRESHOLD_DISK=80
WARN_COUNT=0
CRIT_COUNT=0
ALERTS=()
HOSTNAME_VAL=$(hostname -f 2>/dev/null || hostname)
REPORT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')

# --------------------------------------------------------------------------- #
#  Argument parsing
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)         OUTPUT_FILE="$2"; shift 2 ;;
    --slack)          SLACK_WEBHOOK="$2"; shift 2 ;;
    --json)           JSON_MODE=true; shift ;;
    --quiet)          QUIET=true; shift ;;
    --threshold-cpu)  THRESHOLD_CPU="$2"; shift 2 ;;
    --threshold-mem)  THRESHOLD_MEM="$2"; shift 2 ;;
    --threshold-disk) THRESHOLD_DISK="$2"; shift 2 ;;
    -h|--help) sed -n '3,18p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --------------------------------------------------------------------------- #
#  Output routing
# --------------------------------------------------------------------------- #
[[ -n "$OUTPUT_FILE" ]] && exec > >(tee "$OUTPUT_FILE") 2>&1
$QUIET && [[ -n "$OUTPUT_FILE" ]] && exec >/dev/null

# --------------------------------------------------------------------------- #
#  HEADER
# --------------------------------------------------------------------------- #
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║      System Health Check Report              ║${RESET}"
echo -e "${BOLD}║      Author: Eknatha                         ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${RESET}"
echo ""
printf "  %-20s %s\n" "Host:"    "$HOSTNAME_VAL"
printf "  %-20s %s\n" "Date:"    "$REPORT_DATE"
printf "  %-20s %s\n" "OS:"      "$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -s)"
printf "  %-20s %s\n" "Kernel:"  "$(uname -r)"
printf "  %-20s %s\n" "Uptime:"  "$(uptime -p 2>/dev/null || uptime)"

# --------------------------------------------------------------------------- #
#  SECTION 1: CPU & Load Average
# --------------------------------------------------------------------------- #
hdr "1. CPU & Load Average"

CORES=$(nproc)
LOAD1=$(awk '{print $1}' /proc/loadavg)
LOAD5=$(awk '{print $2}' /proc/loadavg)
LOAD15=$(awk '{print $3}' /proc/loadavg)
RATIO=$(echo "scale=2; $LOAD5 / $CORES" | bc 2>/dev/null || echo "0")

printf "  %-25s %s\n" "CPU Cores:"    "$CORES"
printf "  %-25s %s / %s / %s\n" "Load (1/5/15 min):" "$LOAD1" "$LOAD5" "$LOAD15"
printf "  %-25s %s\n" "Load Ratio (5min):" "${RATIO}x"

if (( $(echo "$RATIO > $THRESHOLD_CPU" | bc -l) )); then
  crit "Load ratio ${RATIO}x > threshold ${THRESHOLD_CPU}x — system is saturated"
elif (( $(echo "$RATIO > 1.0" | bc -l) )); then
  warn "Load ratio ${RATIO}x > 1.0 — system is fully utilised"
else
  ok "Load ratio ${RATIO}x — healthy"
fi

# Per-core breakdown
echo ""
info "Per-core usage (snapshot):"
if command -v mpstat &>/dev/null; then
  mpstat -P ALL 1 1 2>/dev/null | grep -v '^$\|Linux\|CPU' | awk '{printf "  Core %-4s usr:%-6s sys:%-6s iowait:%-6s idle:%s\n", $3,$4,$6,$7,$13}'
else
  top -bn1 | grep "Cpu(s)" | sed 's/^/  /'
fi

# --------------------------------------------------------------------------- #
#  SECTION 2: Memory
# --------------------------------------------------------------------------- #
hdr "2. Memory"

TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
USED=$(( TOTAL - AVAIL ))
USED_PCT=$(awk "BEGIN {printf \"%.1f\", ($USED/$TOTAL)*100}")
AVAIL_PCT=$(awk "BEGIN {printf \"%.1f\", ($AVAIL/$TOTAL)*100}")
SWAP_TOTAL=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
SWAP_FREE=$(awk '/SwapFree/ {print $2}' /proc/meminfo)
SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))

printf "  %-20s %s\n" "Total RAM:"   "$(echo "$TOTAL/1024/1024" | bc) GB"
printf "  %-20s %s (%.1f%%)\n" "Used:"  "$(echo "$USED/1024/1024" | bc) GB" "$USED_PCT"
printf "  %-20s %s (%.1f%%)\n" "Available:" "$(echo "$AVAIL/1024/1024" | bc) GB" "$AVAIL_PCT"
printf "  %-20s %s / %s\n" "Swap (used/total):" "$(echo "$SWAP_USED/1024" | bc) MB" "$(echo "$SWAP_TOTAL/1024" | bc) MB"

if (( $(echo "$USED_PCT > $THRESHOLD_MEM" | bc -l) )); then
  crit "Memory used: ${USED_PCT}% > threshold ${THRESHOLD_MEM}%"
elif (( $(echo "$USED_PCT > 70" | bc -l) )); then
  warn "Memory used: ${USED_PCT}% — watch closely"
else
  ok "Memory used: ${USED_PCT}% — healthy"
fi

if [[ "$SWAP_TOTAL" -gt 0 ]] && [[ "$SWAP_USED" -gt 0 ]]; then
  SWAP_PCT=$(awk "BEGIN {printf \"%.1f\", ($SWAP_USED/$SWAP_TOTAL)*100}")
  warn "Swap in use: ${SWAP_PCT}% — possible memory pressure"
else
  ok "No swap usage"
fi

echo ""
info "Top 5 memory consumers:"
ps aux --sort=-%mem | awk 'NR>1 && NR<=6 {printf "  %-10s %5s%%  %s\n", $1, $4, $11}'

# --------------------------------------------------------------------------- #
#  SECTION 3: Disk Usage
# --------------------------------------------------------------------------- #
hdr "3. Disk Usage"

while IFS= read -r line; do
  [[ "$line" =~ ^Filesystem ]] && continue
  FS=$(echo "$line" | awk '{print $1}')
  TYPE=$(echo "$line" | awk '{print $2}')
  SIZE=$(echo "$line" | awk '{print $3}')
  USED_H=$(echo "$line" | awk '{print $4}')
  AVAIL_H=$(echo "$line" | awk '{print $5}')
  PCT=$(echo "$line" | awk '{print $6}' | tr -d '%')
  MNT=$(echo "$line" | awk '{print $7}')

  printf "  %-25s %5s%%  used: %-8s avail: %-8s (%s)\n" "$MNT" "$PCT" "$USED_H" "$AVAIL_H" "$TYPE"

  if (( PCT > THRESHOLD_DISK + 10 )); then
    crit "Disk ${MNT}: ${PCT}% used — critically full"
  elif (( PCT > THRESHOLD_DISK )); then
    warn "Disk ${MNT}: ${PCT}% used > threshold ${THRESHOLD_DISK}%"
  else
    ok "Disk ${MNT}: ${PCT}% — healthy"
  fi
done < <(df -hT | grep -vE 'tmpfs|devtmpfs|udev|Filesystem')

echo ""
info "Inode usage (high inode usage = can't create files even if disk has space):"
df -i | grep -vE 'tmpfs|devtmpfs|udev|Filesystem' | while read -r line; do
  PCT=$(echo "$line" | awk '{print $5}' | tr -d '%')
  MNT=$(echo "$line" | awk '{print $6}')
  [[ "$PCT" =~ ^[0-9]+$ ]] && (( PCT > 80 )) && warn "Inode usage ${MNT}: ${PCT}%"
done || true

# --------------------------------------------------------------------------- #
#  SECTION 4: Network
# --------------------------------------------------------------------------- #
hdr "4. Network"

info "Interface statistics:"
ip -s link show 2>/dev/null | awk '
  /^[0-9]/ {iface=$2; gsub(":","",iface)}
  /RX:/ {getline; rx=$1}
  /TX:/ {getline; tx=$1}
  rx && tx {printf "  %-15s RX: %-12s TX: %s bytes\n", iface, rx, tx; rx=""; tx=""}
' | head -10

echo ""
info "Listening ports (TCP/UDP):"
ss -tulnp 2>/dev/null | grep LISTEN | awk '{printf "  %-6s %-30s %s\n", $1, $5, $7}' | head -20

echo ""
info "Connection count by state:"
ss -tan 2>/dev/null | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn | \
  while read -r count state; do printf "  %-20s %s\n" "$state" "$count"; done

# --------------------------------------------------------------------------- #
#  SECTION 5: Systemd Services
# --------------------------------------------------------------------------- #
hdr "5. Systemd Services"

FAILED_UNITS=$(systemctl --failed --plain --no-legend 2>/dev/null | awk '{print $1}')
if [[ -z "$FAILED_UNITS" ]]; then
  ok "No failed systemd units"
else
  while IFS= read -r unit; do
    crit "Failed service: ${unit}"
  done <<< "$FAILED_UNITS"
fi

echo ""
info "Key service status:"
for svc in sshd nginx apache2 mysql postgresql redis docker fail2ban; do
  if systemctl list-units --plain --no-legend "${svc}.service" 2>/dev/null | grep -q "$svc"; then
    STATE=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
    if [[ "$STATE" == "active" ]]; then
      ok "${svc}: ${STATE}"
    else
      warn "${svc}: ${STATE}"
    fi
  fi
done

# --------------------------------------------------------------------------- #
#  SECTION 6: Recent Log Errors
# --------------------------------------------------------------------------- #
hdr "6. Recent Log Errors (last 1 hour)"

ERROR_COUNT=$(journalctl -p err --since "1 hour ago" --no-pager 2>/dev/null | grep -vc '^-- ' || echo 0)
info "Total error/critical entries in last hour: ${ERROR_COUNT}"

if (( ERROR_COUNT > 50 )); then
  crit "High error rate in logs: ${ERROR_COUNT} errors in last hour"
elif (( ERROR_COUNT > 10 )); then
  warn "Elevated errors in logs: ${ERROR_COUNT} in last hour"
else
  ok "Error count in bounds: ${ERROR_COUNT}"
fi

echo ""
info "Recent errors (last 10):"
journalctl -p err --since "1 hour ago" --no-pager 2>/dev/null | grep -v '^-- ' | tail -10 | sed 's/^/  /'

# --------------------------------------------------------------------------- #
#  SECTION 7: Open File Descriptors
# --------------------------------------------------------------------------- #
hdr "7. File Descriptors & Limits"

FD_OPEN=$(cat /proc/sys/fs/file-nr 2>/dev/null | awk '{print $1}')
FD_MAX=$(cat /proc/sys/fs/file-max 2>/dev/null)
FD_PCT=$(awk "BEGIN {printf \"%.1f\", ($FD_OPEN/$FD_MAX)*100}")

printf "  %-25s %s / %s (%.1f%%)\n" "Open FDs (used/max):" "$FD_OPEN" "$FD_MAX" "$FD_PCT"

if (( $(echo "$FD_PCT > 80" | bc -l) )); then
  crit "File descriptor usage: ${FD_PCT}% — approaching limit"
elif (( $(echo "$FD_PCT > 60" | bc -l) )); then
  warn "File descriptor usage: ${FD_PCT}% — watch closely"
else
  ok "File descriptor usage: ${FD_PCT}%"
fi

echo ""
info "Top 5 processes by open file descriptors:"
for pid in $(ls /proc | grep '^[0-9]' | head -100); do
  count=$(ls /proc/$pid/fd 2>/dev/null | wc -l)
  name=$(cat /proc/$pid/comm 2>/dev/null || echo unknown)
  echo "$count $name $pid"
done | sort -rn | head -5 | awk '{printf "  %-20s PID:%-8s FDs:%s\n", $2, $3, $1}'

# --------------------------------------------------------------------------- #
#  SECTION 8: Security Checks
# --------------------------------------------------------------------------- #
hdr "8. Security Quick Check"

# Failed logins last hour
FAIL_LOGINS=$(journalctl -u sshd --since "1 hour ago" --no-pager 2>/dev/null | grep -c 'Failed password' || \
  grep "Failed password" /var/log/auth.log 2>/dev/null | awk -v d="$(date '+%b %e')" '$0 ~ d' | wc -l || echo 0)

if (( FAIL_LOGINS > 20 )); then
  crit "High SSH failure count: ${FAIL_LOGINS} in last hour — possible brute force"
elif (( FAIL_LOGINS > 5 )); then
  warn "SSH failures: ${FAIL_LOGINS} in last hour"
else
  ok "SSH failure count: ${FAIL_LOGINS} in last hour"
fi

# Root login check
ROOT_LOGINS=$(journalctl -u sshd --since "24 hours ago" --no-pager 2>/dev/null | grep -c 'Accepted.*root' || echo 0)
if (( ROOT_LOGINS > 0 )); then
  crit "Root SSH logins detected in last 24h: ${ROOT_LOGINS}"
else
  ok "No root SSH logins in last 24h"
fi

# Zombie processes
ZOMBIES=$(ps aux | awk '$8=="Z"' | wc -l)
if (( ZOMBIES > 5 )); then
  warn "Zombie processes: ${ZOMBIES}"
else
  ok "Zombie count: ${ZOMBIES}"
fi

# --------------------------------------------------------------------------- #
#  SUMMARY
# --------------------------------------------------------------------------- #
hdr "HEALTH SUMMARY"

echo ""
printf "  %-20s %s\n" "Host:" "$HOSTNAME_VAL"
printf "  %-20s %s\n" "Checked at:" "$REPORT_DATE"
printf "  %-20s ${RED}%s${RESET}\n" "Critical alerts:" "$CRIT_COUNT"
printf "  %-20s ${YELLOW}%s${RESET}\n" "Warnings:" "$WARN_COUNT"
echo ""

if [[ ${#ALERTS[@]} -gt 0 ]]; then
  echo -e "  ${BOLD}Active Alerts:${RESET}"
  for alert in "${ALERTS[@]}"; do
    if [[ "$alert" == CRIT* ]]; then
      echo -e "  ${RED}  $alert${RESET}"
    else
      echo -e "  ${YELLOW}  $alert${RESET}"
    fi
  done
else
  echo -e "  ${GREEN}  ✔ All checks passed — system is healthy.${RESET}"
fi

echo ""

# --------------------------------------------------------------------------- #
#  Slack notification
# --------------------------------------------------------------------------- #
if [[ -n "$SLACK_WEBHOOK" ]] && [[ ${#ALERTS[@]} -gt 0 ]]; then
  EMOJI=":warning:"
  (( CRIT_COUNT > 0 )) && EMOJI=":red_circle:"
  ALERT_TEXT=$(printf '%s\n' "${ALERTS[@]}" | sed 's/^/• /')
  PAYLOAD=$(cat <<EOF
{
  "text": "${EMOJI} *Health Check — ${HOSTNAME_VAL}* (${REPORT_DATE})\n\`\`\`${ALERT_TEXT}\`\`\`"
}
EOF
)
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-type: application/json' \
    --data "$PAYLOAD" > /dev/null && echo "  Slack alert sent." || echo "  Slack send failed."
fi

# --------------------------------------------------------------------------- #
#  JSON output
# --------------------------------------------------------------------------- #
if $JSON_MODE; then
  ALERT_JSON=$(printf '"%s",' "${ALERTS[@]:-}" | sed 's/,$//')
  cat <<EOF
{
  "host": "${HOSTNAME_VAL}",
  "date": "${REPORT_DATE}",
  "critical": ${CRIT_COUNT},
  "warnings": ${WARN_COUNT},
  "alerts": [${ALERT_JSON}],
  "healthy": $(( CRIT_COUNT == 0 && WARN_COUNT == 0 ))
}
EOF
fi

# Exit code reflects health
(( CRIT_COUNT > 0 )) && exit 2
(( WARN_COUNT > 0 )) && exit 1
exit 0

# =============================================================================
# IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE
# Author : Eknatha
# Repo   : linux-for-devops/07-system-monitoring
# =============================================================================
