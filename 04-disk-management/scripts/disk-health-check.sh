#!/bin/bash
# =============================================================================
# disk-health-check.sh
# Comprehensive disk health audit — SMART status, filesystem errors,
# usage thresholds, inode usage, I/O stats, and deleted-file detection.
# Designed for scheduled production monitoring.
#
# Usage:
#   sudo ./disk-health-check.sh [options]
#
# Options:
#   --warn-pct N       Disk usage warn threshold % (default: 75)
#   --crit-pct N       Disk usage critical threshold % (default: 90)
#   --inode-warn N     Inode usage warn threshold % (default: 80)
#   --output FILE      Save report to file
#   --slack WEBHOOK    Post alert summary to Slack
#   --json             Output JSON summary
#   --quiet            Suppress stdout
#
# Examples:
#   sudo ./disk-health-check.sh
#   sudo ./disk-health-check.sh --warn-pct 75 --crit-pct 90 \
#       --slack https://hooks.slack.com/services/XXX/YYY/ZZZ
#   sudo ./disk-health-check.sh --output /var/log/disk-health-$(date +%F).log
#
# Author : Eknatha
# Repo   : linux-for-devops/04-disk-management
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
#  Colours
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; WARN_COUNT=$((WARN_COUNT+1)); ISSUES+=("WARN: $*"); }
crit() { echo -e "  ${RED}✘${RESET}  $*"; CRIT_COUNT=$((CRIT_COUNT+1)); ISSUES+=("CRIT: $*"); }
info() { echo -e "  ${CYAN}➜${RESET}  $*"; }
hdr()  { echo ""; echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; \
         echo -e "${BOLD}  $*${RESET}"; \
         echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

# --------------------------------------------------------------------------- #
#  Defaults
# --------------------------------------------------------------------------- #
WARN_PCT=75
CRIT_PCT=90
INODE_WARN=80
OUTPUT_FILE=""
SLACK_WEBHOOK=""
JSON_MODE=false
QUIET=false
WARN_COUNT=0
CRIT_COUNT=0
ISSUES=()
HOSTNAME_VAL=$(hostname -f 2>/dev/null || hostname)
REPORT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')

# --------------------------------------------------------------------------- #
#  Argument parsing
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    --warn-pct)   WARN_PCT="$2";      shift 2 ;;
    --crit-pct)   CRIT_PCT="$2";      shift 2 ;;
    --inode-warn) INODE_WARN="$2";    shift 2 ;;
    --output)     OUTPUT_FILE="$2";   shift 2 ;;
    --slack)      SLACK_WEBHOOK="$2"; shift 2 ;;
    --json)       JSON_MODE=true;     shift ;;
    --quiet)      QUIET=true;         shift ;;
    -h|--help) sed -n '3,17p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$OUTPUT_FILE" ]] && exec > >(tee "$OUTPUT_FILE") 2>&1
$QUIET && [[ -n "$OUTPUT_FILE" ]] && exec >/dev/null

# --------------------------------------------------------------------------- #
#  Header
# --------------------------------------------------------------------------- #
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       Disk Health Check Report                   ║${RESET}"
echo -e "${BOLD}║       Author: Eknatha                            ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
printf "  %-20s %s\n" "Host:"    "$HOSTNAME_VAL"
printf "  %-20s %s\n" "Date:"    "$REPORT_DATE"
printf "  %-20s %s%% / %s%%\n" "Thresholds (warn/crit):" "$WARN_PCT" "$CRIT_PCT"

# --------------------------------------------------------------------------- #
#  SECTION 1: Disk Layout
# --------------------------------------------------------------------------- #
hdr "1. Block Device Layout"

lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID 2>/dev/null | sed 's/^/  /'

# --------------------------------------------------------------------------- #
#  SECTION 2: Disk Space Usage
# --------------------------------------------------------------------------- #
hdr "2. Disk Space Usage"

printf "  %-25s %-8s %-8s %-8s %-6s %s\n" \
  "Filesystem" "Size" "Used" "Avail" "Use%" "Mounted on"
printf "  %s\n" "$(printf '%.0s─' {1..75})"

while IFS= read -r line; do
  [[ "$line" =~ ^Filesystem ]] && continue
  FS=$(echo "$line"   | awk '{print $1}')
  TYPE=$(echo "$line" | awk '{print $2}')
  SIZE=$(echo "$line" | awk '{print $3}')
  USED=$(echo "$line" | awk '{print $4}')
  AVAIL=$(echo "$line" | awk '{print $5}')
  PCT=$(echo "$line"  | awk '{print $6}' | tr -d '%')
  MNT=$(echo "$line"  | awk '{print $7}')

  [[ -z "$PCT" || ! "$PCT" =~ ^[0-9]+$ ]] && continue

  printf "  %-25s %-8s %-8s %-8s %-6s %s\n" "$FS" "$SIZE" "$USED" "$AVAIL" "${PCT}%" "$MNT"

  if (( PCT >= CRIT_PCT )); then
    crit "${MNT}: ${PCT}% used — CRITICAL (threshold: ${CRIT_PCT}%)"
  elif (( PCT >= WARN_PCT )); then
    warn "${MNT}: ${PCT}% used (threshold: ${WARN_PCT}%)"
  else
    ok "${MNT}: ${PCT}% — healthy"
  fi
done < <(df -hT | grep -vE 'tmpfs|devtmpfs|udev|overlay|squashfs')

# --------------------------------------------------------------------------- #
#  SECTION 3: Inode Usage
# --------------------------------------------------------------------------- #
hdr "3. Inode Usage"

printf "  %-25s %-10s %-10s %-10s %s\n" "Filesystem" "Inodes" "IUsed" "IFree" "Use%"
printf "  %s\n" "$(printf '%.0s─' {1..65})"

while IFS= read -r line; do
  [[ "$line" =~ ^Filesystem ]] && continue
  FS=$(echo "$line"   | awk '{print $1}')
  TOTAL=$(echo "$line"| awk '{print $2}')
  USED=$(echo "$line" | awk '{print $3}')
  FREE=$(echo "$line" | awk '{print $4}')
  PCT=$(echo "$line"  | awk '{print $5}' | tr -d '%')
  MNT=$(echo "$line"  | awk '{print $6}')

  [[ "$PCT" =~ ^[0-9]+$ ]] || continue
  printf "  %-25s %-10s %-10s %-10s %s%%\n" "$FS" "$TOTAL" "$USED" "$FREE" "$PCT"

  if (( PCT >= 90 )); then
    crit "${MNT}: inodes ${PCT}% used — cannot create new files!"
  elif (( PCT >= INODE_WARN )); then
    warn "${MNT}: inodes ${PCT}% used"
  fi
done < <(df -i | grep -vE 'tmpfs|devtmpfs|udev|overlay|squashfs')

# --------------------------------------------------------------------------- #
#  SECTION 4: SMART Disk Health
# --------------------------------------------------------------------------- #
hdr "4. SMART Disk Health"

if ! command -v smartctl &>/dev/null; then
  warn "smartctl not installed — install: sudo apt install smartmontools"
else
  PHYSICAL_DISKS=$(lsblk -dn -o NAME,TYPE | awk '$2=="disk" {print "/dev/"$1}')
  if [[ -z "$PHYSICAL_DISKS" ]]; then
    info "No physical disks found (VM environment?)"
  else
    for disk in $PHYSICAL_DISKS; do
      echo ""
      info "Checking: ${disk}"
      RESULT=$(sudo smartctl -H "$disk" 2>/dev/null | grep -E 'result:|PASSED|FAILED|overall-health' || echo "UNKNOWN")

      if echo "$RESULT" | grep -q 'PASSED'; then
        ok "${disk}: SMART health PASSED"
      elif echo "$RESULT" | grep -q 'FAILED'; then
        crit "${disk}: SMART health FAILED — disk failure imminent!"
      else
        warn "${disk}: SMART status unknown (may be a virtual disk)"
      fi

      # Check critical SMART attributes
      ATTRS=$(sudo smartctl -A "$disk" 2>/dev/null || true)
      for attr in 5 187 196 197 198; do
        VALUE=$(echo "$ATTRS" | awk -v id="$attr" '$1==id {print $10}')
        if [[ -n "$VALUE" ]] && (( VALUE > 0 )); then
          case $attr in
            5)   ATTR_NAME="Reallocated_Sector_Ct" ;;
            187) ATTR_NAME="Reported_Uncorrect" ;;
            196) ATTR_NAME="Reallocated_Event_Count" ;;
            197) ATTR_NAME="Current_Pending_Sector" ;;
            198) ATTR_NAME="Offline_Uncorrectable" ;;
          esac
          crit "${disk}: ${ATTR_NAME} = ${VALUE} (non-zero = disk degrading!)"
        fi
      done
    done
  fi
fi

# --------------------------------------------------------------------------- #
#  SECTION 5: Kernel Disk Error Messages
# --------------------------------------------------------------------------- #
hdr "5. Kernel Disk Error Messages (last 24h)"

KERN_ERRORS=$(sudo dmesg -T 2>/dev/null | \
  grep --color=never -iE 'error|fail|bad block|i/o error|ata.*error|scsi.*error|nvme.*error' | \
  grep -v 'Warning\|ACPI' | tail -15 || true)

if [[ -z "$KERN_ERRORS" ]]; then
  ok "No disk-related kernel errors found"
else
  warn "Kernel disk errors detected:"
  echo "$KERN_ERRORS" | sed 's/^/    /'
  crit "Disk errors in kernel log — investigate immediately"
fi

# --------------------------------------------------------------------------- #
#  SECTION 6: I/O Statistics Snapshot
# --------------------------------------------------------------------------- #
hdr "6. I/O Statistics Snapshot"

if command -v iostat &>/dev/null; then
  info "I/O device statistics (2s sample):"
  echo ""
  printf "  %-12s %-8s %-8s %-12s %-12s %-8s %s\n" \
    "Device" "r/s" "w/s" "rMB/s" "wMB/s" "await" "%util"
  printf "  %s\n" "$(printf '%.0s─' {1..70})"

  iostat -xz 2 2 2>/dev/null | awk '
    /^Device/ { header=1; next }
    header && NF > 8 {
      printf "  %-12s %-8s %-8s %-12s %-12s %-8s %s\n",
        $1, $4, $5, $6, $7, $10, $NF
      # Alert on high await or utilisation
      if ($10+0 > 50) print "  WARN: " $1 " await=" $10 "ms (high)"
      if ($NF+0 > 80) print "  WARN: " $1 " util=" $NF "% (saturated)"
    }
  '
else
  warn "iostat not installed — install: sudo apt install sysstat"
fi

# --------------------------------------------------------------------------- #
#  SECTION 7: LVM Status
# --------------------------------------------------------------------------- #
hdr "7. LVM Volume Status"

if command -v lvs &>/dev/null; then
  echo ""
  info "Physical Volumes:"
  pvs 2>/dev/null | sed 's/^/  /' || echo "  No PVs found"

  echo ""
  info "Volume Groups:"
  vgs 2>/dev/null | sed 's/^/  /' || echo "  No VGs found"

  echo ""
  info "Logical Volumes:"
  lvs 2>/dev/null | sed 's/^/  /' || echo "  No LVs found"

  # Check for LVM snapshots exceeding 80% usage
  lvs --noheadings -o lv_name,data_percent 2>/dev/null | while read -r lv pct; do
    [[ -z "$pct" || "$pct" == "" ]] && continue
    PCT_INT=$(echo "$pct" | cut -d. -f1)
    [[ "$PCT_INT" =~ ^[0-9]+$ ]] && (( PCT_INT > 80 )) && \
      crit "LVM snapshot ${lv} is ${pct}% full — increase size or remove!"
  done
else
  info "LVM not installed or no LVM volumes configured"
fi

# --------------------------------------------------------------------------- #
#  SECTION 8: RAID Status
# --------------------------------------------------------------------------- #
hdr "8. Software RAID Status"

if [[ -f /proc/mdstat ]]; then
  cat /proc/mdstat | sed 's/^/  /'

  # Check for degraded arrays
  if grep -q 'degraded\|FAILED' /proc/mdstat 2>/dev/null; then
    crit "RAID array is degraded or has failed members — immediate action required!"
  else
    ARRAYS=$(grep '^md' /proc/mdstat | wc -l)
    if (( ARRAYS > 0 )); then
      ok "${ARRAYS} RAID array(s) found — status OK"
    else
      info "No active RAID arrays"
    fi
  fi
else
  info "No software RAID detected"
fi

# --------------------------------------------------------------------------- #
#  SECTION 9: Deleted Files Still Held Open
# --------------------------------------------------------------------------- #
hdr "9. Deleted Files Still Held Open"

if command -v lsof &>/dev/null; then
  DELETED=$(sudo lsof +L1 2>/dev/null | grep deleted || true)

  if [[ -z "$DELETED" ]]; then
    ok "No deleted files held open (no hidden disk usage)"
  else
    TOTAL_SIZE=$(echo "$DELETED" | awk '{sum+=$7} END{printf "%.0f", sum/1048576}' || echo "0")
    DELETED_COUNT=$(echo "$DELETED" | wc -l)
    warn "Deleted files still open: ${DELETED_COUNT} file(s) consuming ~${TOTAL_SIZE}MB"
    echo ""
    printf "  %-12s %-8s %-10s %s\n" "COMMAND" "PID" "SIZE" "FILE"
    echo "$DELETED" | awk '{printf "  %-12s %-8s %-10s %s\n", $1, $2, $7, $9}' | head -10
    echo ""
    info "Fix: truncate (> /proc/<pid>/fd/<fd>) or restart the process"
  fi
else
  warn "lsof not installed — cannot check for deleted files"
fi

# --------------------------------------------------------------------------- #
#  SECTION 10: Top Disk Consumers
# --------------------------------------------------------------------------- #
hdr "10. Top Disk Consumers"

info "Largest directories (top 10):"
du -sh /var/* /opt/* /home/* /tmp 2>/dev/null | sort -rh | head -10 | sed 's/^/  /'

echo ""
info "Largest files > 100MB:"
sudo find / -size +100M -type f \
  -not \( -path '/proc/*' -o -path '/sys/*' -o -path '/dev/*' -o -path '/run/*' \) \
  2>/dev/null \
  | xargs ls -lh 2>/dev/null \
  | sort -k5 -rh \
  | head -10 \
  | awk '{printf "  %-8s %s\n", $5, $9}' || true

# --------------------------------------------------------------------------- #
#  SUMMARY
# --------------------------------------------------------------------------- #
hdr "HEALTH SUMMARY"

echo ""
printf "  %-20s %s\n" "Host:"     "$HOSTNAME_VAL"
printf "  %-20s %s\n" "Checked:"  "$REPORT_DATE"
printf "  %-20s ${RED}%s${RESET}\n"    "Critical:" "$CRIT_COUNT"
printf "  %-20s ${YELLOW}%s${RESET}\n" "Warnings:" "$WARN_COUNT"
echo ""

if [[ ${#ISSUES[@]} -gt 0 ]]; then
  echo -e "  ${BOLD}Issues:${RESET}"
  for issue in "${ISSUES[@]}"; do
    [[ "$issue" == CRIT* ]] && \
      echo -e "  ${RED}  $issue${RESET}" || \
      echo -e "  ${YELLOW}  $issue${RESET}"
  done
else
  echo -e "  ${GREEN}  ✔ All disk health checks passed.${RESET}"
fi

echo ""
[[ -n "$OUTPUT_FILE" ]] && echo "  Report saved to: ${OUTPUT_FILE}"

# --------------------------------------------------------------------------- #
#  Slack notification
# --------------------------------------------------------------------------- #
if [[ -n "$SLACK_WEBHOOK" ]] && [[ ${#ISSUES[@]} -gt 0 ]]; then
  EMOJI=":warning:"
  (( CRIT_COUNT > 0 )) && EMOJI=":red_circle:"
  ALERT_TEXT=$(printf '%s\n' "${ISSUES[@]}" | sed 's/^/• /')
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-type: application/json' \
    --data "{\"text\": \"${EMOJI} *Disk Health — ${HOSTNAME_VAL}*\n\`\`\`${ALERT_TEXT}\`\`\`\"}" \
    > /dev/null && echo "  Slack alert sent."
fi

# --------------------------------------------------------------------------- #
#  JSON output
# --------------------------------------------------------------------------- #
if $JSON_MODE; then
  ALERT_JSON=$(printf '"%s",' "${ISSUES[@]:-}" | sed 's/,$//')
  cat <<EOF
{
  "host": "${HOSTNAME_VAL}",
  "date": "${REPORT_DATE}",
  "critical": ${CRIT_COUNT},
  "warnings": ${WARN_COUNT},
  "issues": [${ALERT_JSON}],
  "healthy": $(( CRIT_COUNT == 0 && WARN_COUNT == 0 ))
}
EOF
fi

(( CRIT_COUNT > 0 )) && exit 2
(( WARN_COUNT > 0 )) && exit 1
exit 0

# =============================================================================
# IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE
# Author : Eknatha
# Repo   : linux-for-devops/04-disk-management
# ============================================================================= 
