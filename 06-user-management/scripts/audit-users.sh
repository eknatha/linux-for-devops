#!/bin/bash
# =============================================================================
# audit-users.sh
# Comprehensive audit of users, groups, sudo privileges, SSH keys,
# password policy, and login activity on production Linux systems.
#
# Usage:
#   sudo ./audit-users.sh [--output FILE] [--format text|json] [--send-mail EMAIL]
#
# Options:
#   --output FILE      Write report to FILE (default: stdout + /var/log/user-audit-DATE.log)
#   --format FORMAT    Output format: text (default) or json
#   --send-mail EMAIL  Email report after generation (requires mailutils)
#   --quiet            Suppress stdout output (write to file only)
#
# Examples:
#   sudo ./audit-users.sh
#   sudo ./audit-users.sh --output /tmp/audit.txt
#   sudo ./audit-users.sh --format json --output /tmp/audit.json
#   sudo ./audit-users.sh --send-mail ops@company.com --quiet
#
# Author : Eknatha
# Repo   : linux-for-devops/06-user-management
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
#  Colour & formatting
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
WARN_ICON="⚠ "; OK_ICON="✔ "; INFO_ICON="➜ "

# --------------------------------------------------------------------------- #
#  Root check
# --------------------------------------------------------------------------- #
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo $0" >&2; exit 1; }

# --------------------------------------------------------------------------- #
#  Defaults
# --------------------------------------------------------------------------- #
REPORT_FILE="/var/log/user-audit-$(date +%F).log"
OUTPUT_FORMAT="text"
SEND_MAIL=""
QUIET=false
HOSTNAME_VAL=$(hostname -f 2>/dev/null || hostname)
AUDIT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')
WARNINGS=0
ISSUES=()

# --------------------------------------------------------------------------- #
#  Argument parsing
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)    REPORT_FILE="$2"; shift 2 ;;
    --format)    OUTPUT_FORMAT="$2"; shift 2 ;;
    --send-mail) SEND_MAIL="$2"; shift 2 ;;
    --quiet)     QUIET=true; shift ;;
    -h|--help)   sed -n '3,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --------------------------------------------------------------------------- #
#  Output multiplexer: write to file AND stdout (unless --quiet)
# --------------------------------------------------------------------------- #
exec > >(tee -a "$REPORT_FILE") 2>&1
$QUIET && exec >/dev/null

# --------------------------------------------------------------------------- #
#  Helpers
# --------------------------------------------------------------------------- #
section() { echo ""; echo -e "${BOLD}════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}  $*${RESET}"; \
            echo -e "${BOLD}════════════════════════════════════════${RESET}"; }

row()     { printf "  %-30s %s\n" "$1" "$2"; }
warn()    { echo -e "  ${YELLOW}${WARN_ICON}WARNING:${RESET} $*"; WARNINGS=$((WARNINGS+1)); ISSUES+=("$*"); }
ok()      { echo -e "  ${GREEN}${OK_ICON}${RESET} $*"; }
info()    { echo -e "  ${CYAN}${INFO_ICON}${RESET} $*"; }

# --------------------------------------------------------------------------- #
#  HEADER
# --------------------------------------------------------------------------- #
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       Linux User Security Audit Report           ║${RESET}"
echo -e "${BOLD}║       Author: Eknatha                            ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
row "Hostname:"    "$HOSTNAME_VAL"
row "Date:"        "$AUDIT_DATE"
row "Audit by:"    "$(logname 2>/dev/null || echo root)"
row "Kernel:"      "$(uname -r)"
row "OS:"          "$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -s)"

# --------------------------------------------------------------------------- #
#  SECTION 1: Human User Accounts (UID >= 1000)
# --------------------------------------------------------------------------- #
section "1. Human User Accounts (UID ≥ 1000)"

HUMAN_USERS=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1":"$3":"$6":"$7}' /etc/passwd)
COUNT=0
while IFS=: read -r uname uid home shell; do
  COUNT=$((COUNT+1))
  LOCKED=""
  SHADOW_ENTRY=$(grep "^${uname}:" /etc/shadow 2>/dev/null || echo "")
  HASH=$(echo "$SHADOW_ENTRY" | cut -d: -f2)

  if [[ "$HASH" == !* ]] || [[ "$HASH" == \** ]]; then
    LOCKED=" [LOCKED]"
  fi

  EXPIRY=$(chage -l "$uname" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
  LAST_LOGIN=$(lastlog -u "$uname" 2>/dev/null | tail -1 | awk '{if ($2=="**Never") print "Never logged in"; else print $4,$5,$6,$7,$8,$9}')

  printf "  %-20s UID:%-6s Shell:%-20s%s\n" "$uname" "$uid" "$shell" "$LOCKED"
  printf "  %-20s Home: %s\n" "" "$home"
  printf "  %-20s Last Login: %s | Expiry: %s\n" "" "${LAST_LOGIN:-unknown}" "${EXPIRY:-never}"
  echo ""

  # Flags
  [[ "$shell" =~ bash|zsh|sh|fish ]] || warn "  ${uname}: Unusual shell: ${shell}"
  [[ -d "$home" ]] || warn "  ${uname}: Home directory missing: ${home}"

done <<< "$HUMAN_USERS"

info "Total human accounts: ${COUNT}"

# --------------------------------------------------------------------------- #
#  SECTION 2: UID 0 (Root-level) Accounts
# --------------------------------------------------------------------------- #
section "2. UID 0 Accounts (Critical — should be root only)"

UID0=$(awk -F: '$3==0 {print $1}' /etc/passwd)
while read -r u; do
  if [[ "$u" == "root" ]]; then
    ok "root (expected)"
  else
    warn "Non-root account with UID 0: ${u} — INVESTIGATE IMMEDIATELY"
  fi
done <<< "$UID0"

# --------------------------------------------------------------------------- #
#  SECTION 3: Accounts with Empty or No Password
# --------------------------------------------------------------------------- #
section "3. Password Security Checks"

info "Accounts with empty/no password hash:"
EMPTY_PASS=$(awk -F: '($2 == "" || $2 == "!!" || $2 == "*") && $3 >= 1000 {print $1}' /etc/shadow 2>/dev/null || true)
if [[ -z "$EMPTY_PASS" ]]; then
  ok "No human accounts with empty passwords."
else
  while read -r u; do warn "Empty/no password: ${u}"; done <<< "$EMPTY_PASS"
fi

echo ""
info "Accounts with expired passwords:"
while IFS=: read -r uname _; do
  [[ $(id -u "$uname" 2>/dev/null) -ge 1000 ]] || continue
  MAX_DAYS=$(chage -l "$uname" 2>/dev/null | grep "Maximum" | grep -oE '[0-9]+' || echo "99999")
  LAST_CHANGE=$(chage -l "$uname" 2>/dev/null | grep "Last password change" | cut -d: -f2 | xargs)
  if [[ "$LAST_CHANGE" == "never" ]]; then
    warn "${uname}: Password never changed"
  fi
done < /etc/passwd

echo ""
info "Password aging policy (login.defs):"
for key in PASS_MAX_DAYS PASS_MIN_DAYS PASS_WARN_AGE PASS_MIN_LEN; do
  val=$(grep "^${key}" /etc/login.defs 2>/dev/null | awk '{print $2}' || echo "not set")
  row "  ${key}:" "$val"
done

# --------------------------------------------------------------------------- #
#  SECTION 4: Service Accounts with Login Shells
# --------------------------------------------------------------------------- #
section "4. Service Accounts with Login Shells (UID < 1000)"

info "Service/system accounts that have interactive shells (potential risk):"
RISKY=$(awk -F: '$3 < 1000 && $7 ~ /bash|zsh|sh|fish/ && $1 !~ /^(root|sync|shutdown|halt)$/ {print $1, $7}' /etc/passwd)
if [[ -z "$RISKY" ]]; then
  ok "No unexpected service accounts with login shells."
else
  while read -r line; do warn "$line"; done <<< "$RISKY"
fi

# --------------------------------------------------------------------------- #
#  SECTION 5: sudo / Privilege Escalation
# --------------------------------------------------------------------------- #
section "5. sudo Privileges"

info "All sudo grants found in /etc/sudoers and /etc/sudoers.d/:"
echo ""
grep -rh '^[^#]' /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v '^$' | while read -r line; do
  if echo "$line" | grep -q 'NOPASSWD.*ALL.*ALL\|ALL.*NOPASSWD.*ALL'; then
    warn "Unrestricted NOPASSWD sudo: ${line}"
  elif echo "$line" | grep -qE '^\s*(root|%wheel|%sudo)\s+ALL=\(ALL(:ALL)?\)\s+ALL'; then
    warn "Blanket ALL sudo: ${line}"
  else
    ok "${line}"
  fi
done

echo ""
info "Users currently in sudo/wheel group:"
for grp in sudo wheel; do
  members=$(getent group "$grp" 2>/dev/null | cut -d: -f4)
  [[ -n "$members" ]] && echo "  ${grp}: ${members}"
done

# --------------------------------------------------------------------------- #
#  SECTION 6: SSH Authorized Keys Audit
# --------------------------------------------------------------------------- #
section "6. SSH Authorized Keys"

KEY_COUNT=0
find /home /root /var/lib -name "authorized_keys" 2>/dev/null | while read -r keyfile; do
  owner=$(stat -c '%U' "$keyfile")
  perms=$(stat -c '%a' "$keyfile")
  count=$(grep -c 'ssh-' "$keyfile" 2>/dev/null || echo 0)
  KEY_COUNT=$((KEY_COUNT + count))

  echo ""
  info "File : ${keyfile}"
  row "  Owner:"       "$owner"
  row "  Permissions:" "$perms"
  row "  Keys:"        "$count"

  # Permissions check
  if [[ "$perms" != "600" ]]; then
    warn "authorized_keys permissions should be 600, found: ${perms}"
  else
    ok "Permissions OK (600)"
  fi

  # List each key with comment/type
  while IFS= read -r key; do
    [[ "$key" =~ ^ssh- || "$key" =~ ^ecdsa || "$key" =~ ^sk- ]] || continue
    KEY_TYPE=$(echo "$key" | awk '{print $1}')
    KEY_COMMENT=$(echo "$key" | awk '{print $NF}')
    FINGERPRINT=$(echo "$key" | ssh-keygen -lf /dev/stdin 2>/dev/null | awk '{print $2}' || echo "N/A")
    printf "  %-12s %-50s %s\n" "$KEY_TYPE" "$KEY_COMMENT" "$FINGERPRINT"

    # Warn on RSA keys < 4096
    if [[ "$KEY_TYPE" == "ssh-rsa" ]]; then
      KEY_BITS=$(echo "$key" | ssh-keygen -lf /dev/stdin 2>/dev/null | awk '{print $1}' || echo 0)
      [[ "$KEY_BITS" -lt 4096 ]] && warn "Weak RSA key (${KEY_BITS} bits) for ${KEY_COMMENT} — use Ed25519 or RSA-4096"
    fi
  done < "$keyfile"
done

# --------------------------------------------------------------------------- #
#  SECTION 7: sshd_config Security Review
# --------------------------------------------------------------------------- #
section "7. sshd_config Security Settings"

SSHD_CONFIG="/etc/ssh/sshd_config"
check_sshd() {
  local key="$1" expected="$2"
  val=$(grep -iE "^\s*${key}\s" "$SSHD_CONFIG" 2>/dev/null | tail -1 | awk '{print $2}' || echo "not set")
  if [[ "$val" == "$expected" ]]; then
    ok "${key} = ${val}"
  else
    warn "${key} = ${val} (expected: ${expected})"
  fi
}

check_sshd "PermitRootLogin"           "no"
check_sshd "PasswordAuthentication"    "no"
check_sshd "PermitEmptyPasswords"      "no"
check_sshd "ChallengeResponseAuthentication" "no"
check_sshd "X11Forwarding"            "no"
check_sshd "MaxAuthTries"             "3"

val=$(grep -iE "^\s*Protocol\s" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}' || echo "2 (default)")
if [[ "$val" == "1" ]]; then warn "SSH Protocol 1 enabled — must be disabled"; else ok "Protocol: ${val}"; fi

AllowGroups=$(grep -iE "^\s*AllowGroups\s" "$SSHD_CONFIG" 2>/dev/null || echo "")
if [[ -z "$AllowGroups" ]]; then
  warn "AllowGroups not set — all users can attempt SSH"
else
  ok "AllowGroups: $(echo $AllowGroups | awk '{$1=""; print $0}')"
fi

# --------------------------------------------------------------------------- #
#  SECTION 8: Recent Login Activity
# --------------------------------------------------------------------------- #
section "8. Recent Login Activity (Last 20)"

last -20 --time-format iso 2>/dev/null | head -22 || last -20 | head -22

echo ""
info "Failed login attempts (last 20):"
lastb 2>/dev/null | head -20 || grep 'Failed password' /var/log/auth.log 2>/dev/null | tail -20 || \
  journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep 'Failed' | tail -20 || \
  echo "  (no failed login data available)"

# --------------------------------------------------------------------------- #
#  SECTION 9: Cron Jobs by Users
# --------------------------------------------------------------------------- #
section "9. User Cron Jobs"

for user in $(awk -F: '$3 >= 1000 {print $1}' /etc/passwd); do
  cron=$(crontab -u "$user" -l 2>/dev/null | grep -v '^#' | grep -v '^$' || true)
  if [[ -n "$cron" ]]; then
    info "Crontab for ${user}:"
    echo "$cron" | sed 's/^/    /'
  fi
done

# System cron
info "System cron files:"
ls /etc/cron.d/ 2>/dev/null | sed 's/^/  /' || echo "  none"

# --------------------------------------------------------------------------- #
#  SECTION 10: World-Writable Files and SUID Binaries
# --------------------------------------------------------------------------- #
section "10. Dangerous File Permissions"

info "SUID binaries (run as file owner — review carefully):"
find / -perm -4000 -type f 2>/dev/null \
  | grep -v -E '^/(proc|sys|dev)' \
  | while read -r f; do printf "  %-50s %s\n" "$f" "$(stat -c '%U' $f)"; done

echo ""
info "World-writable files (excluding /proc /sys /dev /tmp):"
WW=$(find / -perm -0002 -type f 2>/dev/null \
  | grep -v -E '^/(proc|sys|dev|run|tmp)' || true)
if [[ -z "$WW" ]]; then
  ok "No unexpected world-writable files found."
else
  echo "$WW" | while read -r f; do warn "World-writable: $f"; done
fi

# --------------------------------------------------------------------------- #
#  SUMMARY
# --------------------------------------------------------------------------- #
section "AUDIT SUMMARY"

row "Total warnings:" "$WARNINGS"
echo ""

if [[ ${#ISSUES[@]} -gt 0 ]]; then
  echo -e "${YELLOW}Issues found:${RESET}"
  for issue in "${ISSUES[@]}"; do
    echo -e "  ${RED}•${RESET} ${issue}"
  done
else
  echo -e "${GREEN}  No critical issues detected.${RESET}"
fi

echo ""
echo -e "  Full report saved to: ${BOLD}${REPORT_FILE}${RESET}"
echo ""

# --------------------------------------------------------------------------- #
#  Optional email
# --------------------------------------------------------------------------- #
if [[ -n "$SEND_MAIL" ]]; then
  if command -v mail &>/dev/null; then
    mail -s "User Audit Report — ${HOSTNAME_VAL} — $(date +%F)" "$SEND_MAIL" < "$REPORT_FILE"
    echo -e "${GREEN}[OK]${RESET} Report emailed to ${SEND_MAIL}"
  else
    echo -e "${YELLOW}[WARN]${RESET} 'mail' command not found. Install mailutils to send emails."
  fi
fi

# =============================================================================
# IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE
# Author : Eknatha
# Repo   : linux-for-devops/06-user-management
# =============================================================================
