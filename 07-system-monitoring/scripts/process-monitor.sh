#!/bin/bash
# =============================================================================
# process-monitor.sh
# Monitor critical processes and auto-restart them via systemctl or direct
# command when they are found dead. Supports Slack/email alerting, cooldown
# periods, max restart limits, and detailed logging.
#
# Usage:
#   ./process-monitor.sh --service SERVICE [options]
#   ./process-monitor.sh --process PROC_NAME --restart-cmd CMD [options]
#
# Options:
#   --service NAME         systemd service name to monitor and restart
#   --process NAME         Process name to watch (pgrep match)
#   --restart-cmd CMD      Command to restart process (if not systemd)
#   --max-restarts N       Max restarts in cooldown window (default: 3)
#   --cooldown-min N       Cooldown window in minutes (default: 60)
#   --slack WEBHOOK_URL    Slack webhook for alerts
#   --email ADDRESS        Email address for alerts
#   --pid-file FILE        PID file to check instead of pgrep
#   --log-file FILE        Log file (default: /var/log/process-monitor.log)
#   --dry-run              Log and alert without actually restarting
#   --once                 Run check once and exit (for cron use)
#   --interval N           Watch interval in seconds (default: 30, daemon mode)
#
# Examples:
#   # Monitor nginx via systemd (recommended)
#   sudo ./process-monitor.sh --service nginx --slack https://hooks.slack.com/...
#
#   # Monitor a custom app process
#   sudo ./process-monitor.sh --process myapp \
#       --restart-cmd "sudo systemctl restart myapp" \
#       --max-restarts 3 --cooldown-min 30
#
#   # Run once from cron every minute
#   * * * * * root /opt/scripts/process-monitor.sh --service myapp --once
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

# --------------------------------------------------------------------------- #
#  Defaults
# --------------------------------------------------------------------------- #
SERVICE_NAME=""
PROCESS_NAME=""
RESTART_CMD=""
PID_FILE=""
MAX_RESTARTS=3
COOLDOWN_MIN=60
SLACK_WEBHOOK=""
EMAIL_TO=""
LOG_FILE="/var/log/process-monitor.log"
DRY_RUN=false
ONCE=false
INTERVAL=30
HOSTNAME_VAL=$(hostname -f 2>/dev/null || hostname)

# State tracking directory
STATE_DIR="/tmp/process-monitor-state"
mkdir -p "$STATE_DIR"

# --------------------------------------------------------------------------- #
#  Argument parsing
# --------------------------------------------------------------------------- #
usage() { sed -n '3,26p' "$0" | sed 's/^# \?//'; exit 0; }
[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)      SERVICE_NAME="$2";  shift 2 ;;
    --process)      PROCESS_NAME="$2";  shift 2 ;;
    --restart-cmd)  RESTART_CMD="$2";   shift 2 ;;
    --pid-file)     PID_FILE="$2";      shift 2 ;;
    --max-restarts) MAX_RESTARTS="$2";  shift 2 ;;
    --cooldown-min) COOLDOWN_MIN="$2";  shift 2 ;;
    --slack)        SLACK_WEBHOOK="$2"; shift 2 ;;
    --email)        EMAIL_TO="$2";      shift 2 ;;
    --log-file)     LOG_FILE="$2";      shift 2 ;;
    --dry-run)      DRY_RUN=true;       shift ;;
    --once)         ONCE=true;          shift ;;
    --interval)     INTERVAL="$2";      shift 2 ;;
    -h|--help)      usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Derive process name from service name if not set
[[ -z "$PROCESS_NAME" && -n "$SERVICE_NAME" ]] && PROCESS_NAME="$SERVICE_NAME"
MONITOR_TARGET="${SERVICE_NAME:-$PROCESS_NAME}"
[[ -z "$MONITOR_TARGET" ]] && { echo "Error: --service or --process required." >&2; exit 1; }

# --------------------------------------------------------------------------- #
#  Logging
# --------------------------------------------------------------------------- #
log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "${ts} [${level}] ${msg}" | tee -a "$LOG_FILE"
  logger -t "process-monitor" "[${level}] ${msg}"
}

# --------------------------------------------------------------------------- #
#  Restart state tracking (count restarts within cooldown window)
# --------------------------------------------------------------------------- #
STATE_FILE="${STATE_DIR}/${MONITOR_TARGET//\//_}.restarts"
LAST_RESTART_FILE="${STATE_DIR}/${MONITOR_TARGET//\//_}.last_restart"

count_recent_restarts() {
  local count=0
  local cutoff
  cutoff=$(date -d "${COOLDOWN_MIN} minutes ago" +%s 2>/dev/null || \
    date -v -"${COOLDOWN_MIN}"M +%s 2>/dev/null || echo 0)

  [[ -f "$STATE_FILE" ]] || return 0

  while IFS= read -r ts; do
    [[ "$ts" -gt "$cutoff" ]] && count=$((count + 1))
  done < "$STATE_FILE"
  echo "$count"
}

record_restart() {
  date +%s >> "$STATE_FILE"
  date '+%Y-%m-%d %H:%M:%S' > "$LAST_RESTART_FILE"
  # Trim entries older than cooldown
  if command -v python3 &>/dev/null; then
    python3 -c "
import time, os
cutoff = time.time() - ${COOLDOWN_MIN} * 60
f = '${STATE_FILE}'
if os.path.exists(f):
    lines = [l.strip() for l in open(f) if l.strip() and float(l.strip()) > cutoff]
    open(f, 'w').write('\n'.join(lines) + '\n' if lines else '')
"
  fi
}

# --------------------------------------------------------------------------- #
#  Alert functions
# --------------------------------------------------------------------------- #
send_slack_alert() {
  local event="$1" msg="$2"
  local emoji=":red_circle:"
  [[ "$event" == "RECOVERED" ]] && emoji=":green_circle:"

  [[ -z "$SLACK_WEBHOOK" ]] && return 0

  local payload="{
    \"text\": \"${emoji} *Process Monitor — ${HOSTNAME_VAL}*\",
    \"attachments\": [{
      \"color\": \"$([ "$event" == "RECOVERED" ] && echo good || echo danger)\",
      \"fields\": [
        {\"title\": \"Event\",     \"value\": \"${event}\",          \"short\": true},
        {\"title\": \"Process\",   \"value\": \"${MONITOR_TARGET}\", \"short\": true},
        {\"title\": \"Detail\",    \"value\": \"${msg}\",            \"short\": false},
        {\"title\": \"Time\",      \"value\": \"$(date '+%Y-%m-%d %H:%M:%S')\", \"short\": false}
      ]
    }]
  }"

  $DRY_RUN && { echo "  [DRY-RUN] Slack: ${event} ${MONITOR_TARGET}"; return; }
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-type: application/json' \
    --data "$payload" > /dev/null && \
    log "INFO" "Slack alert sent: ${event}" || \
    log "WARN" "Slack send failed"
}

send_email_alert() {
  local event="$1" msg="$2"
  [[ -z "$EMAIL_TO" ]] && return 0

  local subject="[${event}] Process ${MONITOR_TARGET} on ${HOSTNAME_VAL}"
  $DRY_RUN && { echo "  [DRY-RUN] Email: ${subject}"; return; }

  command -v mail &>/dev/null && \
    echo -e "Host: ${HOSTNAME_VAL}\nProcess: ${MONITOR_TARGET}\nEvent: ${event}\nDetail: ${msg}\nTime: $(date)" \
    | mail -s "$subject" "$EMAIL_TO" && \
    log "INFO" "Email sent: ${subject}" || \
    log "WARN" "Email not sent (mail not available)"
}

# --------------------------------------------------------------------------- #
#  Process check function
# --------------------------------------------------------------------------- #
is_running() {
  if [[ -n "$SERVICE_NAME" ]]; then
    systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
  elif [[ -n "$PID_FILE" ]]; then
    [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
  else
    pgrep -x "$PROCESS_NAME" > /dev/null 2>&1
  fi
}

# --------------------------------------------------------------------------- #
#  Restart function
# --------------------------------------------------------------------------- #
do_restart() {
  local reason="$1"
  local RECENT
  RECENT=$(count_recent_restarts)

  log "WARN" "${MONITOR_TARGET} is DOWN — reason: ${reason}"
  log "WARN" "Restart attempts in last ${COOLDOWN_MIN} min: ${RECENT}/${MAX_RESTARTS}"

  if (( RECENT >= MAX_RESTARTS )); then
    log "CRIT" "Max restarts (${MAX_RESTARTS}) reached in ${COOLDOWN_MIN} min window — NOT restarting"
    log "CRIT" "Manual intervention required for ${MONITOR_TARGET}"
    send_slack_alert "MAX_RESTARTS_EXCEEDED" \
      "Process has been restarted ${RECENT} times in ${COOLDOWN_MIN} minutes. Manual action required."
    send_email_alert "MAX_RESTARTS_EXCEEDED" \
      "Process has been restarted ${RECENT} times in ${COOLDOWN_MIN} minutes. Manual action required."
    return 1
  fi

  # Attempt restart
  log "INFO" "Attempting restart of ${MONITOR_TARGET} (attempt $((RECENT+1))/${MAX_RESTARTS})..."

  local restart_success=false

  if $DRY_RUN; then
    echo -e "  ${YELLOW}[DRY-RUN]${RESET} Would restart: ${MONITOR_TARGET}"
    restart_success=true
  elif [[ -n "$SERVICE_NAME" ]]; then
    if systemctl restart "$SERVICE_NAME" 2>&1 | tee -a "$LOG_FILE"; then
      restart_success=true
    fi
  elif [[ -n "$RESTART_CMD" ]]; then
    if eval "$RESTART_CMD" 2>&1 | tee -a "$LOG_FILE"; then
      restart_success=true
    fi
  else
    log "WARN" "No restart method available — set --service or --restart-cmd"
    return 1
  fi

  if $restart_success; then
    record_restart
    sleep 5  # Give process time to start
    if is_running; then
      log "INFO" "${MONITOR_TARGET} restarted successfully"
      send_slack_alert "RESTARTED" "Process restarted successfully (attempt $((RECENT+1)))."
      send_email_alert "RESTARTED" "Process restarted successfully."
    else
      log "CRIT" "${MONITOR_TARGET} failed to restart — still not running"
      send_slack_alert "RESTART_FAILED" "Process still not running after restart attempt."
      send_email_alert "RESTART_FAILED" "Process still not running after restart attempt."
    fi
  else
    log "CRIT" "Restart command failed for ${MONITOR_TARGET}"
    send_slack_alert "RESTART_FAILED" "Restart command exited with error."
  fi
}

# --------------------------------------------------------------------------- #
#  Single check
# --------------------------------------------------------------------------- #
check_once() {
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  local RECOVERED_FLAG="${STATE_DIR}/${MONITOR_TARGET//\//_}.was_down"

  if is_running; then
    echo -e "${GREEN}[${ts}] ✔ ${MONITOR_TARGET} is running${RESET}"

    # Send recovery alert if it was previously down
    if [[ -f "$RECOVERED_FLAG" ]]; then
      log "INFO" "${MONITOR_TARGET} has recovered"
      send_slack_alert "RECOVERED" "Process is back online."
      send_email_alert "RECOVERED" "Process is back online."
      rm -f "$RECOVERED_FLAG"
    fi
  else
    echo -e "${RED}[${ts}] ✘ ${MONITOR_TARGET} is NOT running${RESET}"
    touch "$RECOVERED_FLAG"  # Mark as down for recovery detection
    do_restart "process not found" || true
  fi
}

# --------------------------------------------------------------------------- #
#  Print status summary
# --------------------------------------------------------------------------- #
print_status() {
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}  Process Monitor — ${MONITOR_TARGET}${RESET}"
  echo -e "${BOLD}  Author: Eknatha${RESET}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  printf "  %-20s %s\n" "Host:"         "$HOSTNAME_VAL"
  printf "  %-20s %s\n" "Target:"       "$MONITOR_TARGET"
  printf "  %-20s %s\n" "Max restarts:" "${MAX_RESTARTS} per ${COOLDOWN_MIN} min"
  printf "  %-20s %s\n" "Log:"          "$LOG_FILE"
  printf "  %-20s %s\n" "Mode:"         "$($ONCE && echo 'once (cron)' || echo "daemon (interval: ${INTERVAL}s)")"
  $DRY_RUN && printf "  %-20s %s\n" "Dry-run:" "YES — no actual restarts"
  echo ""

  # Show last restart
  if [[ -f "$LAST_RESTART_FILE" ]]; then
    printf "  %-20s %s\n" "Last restart:" "$(cat "$LAST_RESTART_FILE")"
  fi

  # Show recent restart count
  RECENT=$(count_recent_restarts)
  printf "  %-20s %s\n" "Recent restarts:" "${RECENT}/${MAX_RESTARTS} in last ${COOLDOWN_MIN} min"
  echo ""
}

# --------------------------------------------------------------------------- #
#  MAIN
# --------------------------------------------------------------------------- #
print_status

if $ONCE; then
  check_once
  exit 0
fi

# Daemon mode — loop
log "INFO" "Starting process monitor daemon for ${MONITOR_TARGET} (interval: ${INTERVAL}s)"
trap 'log "INFO" "Process monitor stopped"; exit 0' SIGTERM SIGINT

while true; do
  check_once
  sleep "$INTERVAL"
done

# =============================================================================
# IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE
# Author : Eknatha
# Repo   : linux-for-devops/07-system-monitoring
# =============================================================================
