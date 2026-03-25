#!/bin/bash
# =============================================================================
# network-diagnostics.sh
# Comprehensive network health check — interfaces, routing, DNS, ports,
# connectivity, firewall, and performance snapshot for production Linux servers.
# 
# Usage:
#   ./network-diagnostics.sh [options]
#
# Options:
#   --output FILE       Save report to file (default: stdout)
#   --slack WEBHOOK     Post alert summary to Slack
#   --target HOST       Additional host/IP to test connectivity against
#   --json              Output machine-readable JSON summary
#   --quiet             Suppress stdout (use with --output)
#
# Examples:
#   sudo ./network-diagnostics.sh
#   sudo ./network-diagnostics.sh --output /var/log/net-diag-$(date +%F).log
#   sudo ./network-diagnostics.sh --target api.example.com --slack https://hooks.slack.com/...
#
# Author : Eknatha
# Repo   : linux-for-devops/03-networking
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
OUTPUT_FILE=""
SLACK_WEBHOOK=""
TARGET_HOST=""
JSON_MODE=false
QUIET=false
WARN_COUNT=0
CRIT_COUNT=0
ISSUES=()
HOSTNAME_VAL=$(hostname -f 2>/dev/null || hostname)
REPORT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')

# Test targets
DNS_RESOLVERS=("8.8.8.8" "1.1.1.1" "9.9.9.9")
CONNECTIVITY_TARGETS=("8.8.8.8" "1.1.1.1")
DNS_TEST_DOMAIN="google.com"

# --------------------------------------------------------------------------- #
#  Argument parsing
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)  OUTPUT_FILE="$2"; shift 2 ;;
    --slack)   SLACK_WEBHOOK="$2"; shift 2 ;;
    --target)  TARGET_HOST="$2"; shift 2 ;;
    --json)    JSON_MODE=true; shift ;;
    --quiet)   QUIET=true; shift ;;
    -h|--help) sed -n '3,16p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$OUTPUT_FILE" ]] && exec > >(tee "$OUTPUT_FILE") 2>&1
$QUIET && [[ -n "$OUTPUT_FILE" ]] && exec >/dev/null

# --------------------------------------------------------------------------- #
#  HEADER
# --------------------------------------------------------------------------- #
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       Network Diagnostics Report                 ║${RESET}"
echo -e "${BOLD}║       Author: Eknatha                            ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
printf "  %-20s %s\n" "Host:"    "$HOSTNAME_VAL"
printf "  %-20s %s\n" "Date:"    "$REPORT_DATE"
printf "  %-20s %s\n" "Kernel:"  "$(uname -r)"

# --------------------------------------------------------------------------- #
#  SECTION 1: Network Interfaces
# --------------------------------------------------------------------------- #
hdr "1. Network Interfaces"

while IFS= read -r line; do
  if [[ "$line" =~ ^[0-9]+:\ ([^:]+): ]]; then
    IFACE="${BASH_REMATCH[1]}"
    STATE=$(echo "$line" | grep -oP '(?<=state )\w+' || echo "UNKNOWN")
    MTU=$(echo "$line" | grep -oP '(?<=mtu )\d+' || echo "?")
    printf "  %-15s state:%-10s mtu:%s\n" "$IFACE" "$STATE" "$MTU"
    if [[ "$STATE" == "DOWN" && "$IFACE" != "lo" ]]; then
      warn "Interface ${IFACE} is DOWN"
    fi
  fi
done < <(ip link show 2>/dev/null)

echo ""
info "IP addresses:"
ip -br addr show 2>/dev/null | grep -v '^lo' | while read -r iface state addrs; do
  printf "  %-15s %-10s %s\n" "$iface" "$state" "${addrs:-no IP}"
  if [[ "$state" == "DOWN" ]]; then
    warn "Interface ${iface} is DOWN"
  elif [[ -z "$addrs" ]] && [[ "$iface" != "lo" ]]; then
    warn "Interface ${iface} has no IP address"
  fi
done

echo ""
info "Interface error counters:"
ip -s link show 2>/dev/null | awk '
  /^[0-9]/ {iface=$2; gsub(/:/, "", iface)}
  /RX:/ {getline; rx_err=$3; rx_drop=$4}
  /TX:/ {getline; tx_err=$3; tx_drop=$4}
  rx_err != "" {
    printf "  %-15s RX_err:%-6s RX_drop:%-6s TX_err:%-6s TX_drop:%s\n",
      iface, rx_err, rx_drop, tx_err, tx_drop
    rx_err=""
  }
' | grep -v '^  lo '

# --------------------------------------------------------------------------- #
#  SECTION 2: Routing
# --------------------------------------------------------------------------- #
hdr "2. Routing Table"

DEFAULT_GW=$(ip route show default 2>/dev/null | head -1 | awk '{print $3}')
if [[ -n "$DEFAULT_GW" ]]; then
  ok "Default gateway: ${DEFAULT_GW}"
  # Test gateway reachability
  if ping -c2 -W2 "$DEFAULT_GW" &>/dev/null; then
    ok "Gateway ${DEFAULT_GW} is reachable"
  else
    crit "Gateway ${DEFAULT_GW} is NOT reachable"
  fi
else
  crit "No default gateway configured"
fi

echo ""
info "Full routing table:"
ip route show | sed 's/^/  /'

# --------------------------------------------------------------------------- #
#  SECTION 3: DNS Resolution
# --------------------------------------------------------------------------- #
hdr "3. DNS Configuration and Resolution"

info "Configured resolvers:"
grep '^nameserver' /etc/resolv.conf 2>/dev/null | sed 's/^/  /' || echo "  None found"

SEARCH=$(grep '^search\|^domain' /etc/resolv.conf 2>/dev/null | head -1 || echo "none")
printf "  %-20s %s\n" "Search domain:" "$SEARCH"

echo ""
info "Testing DNS resolution against each resolver:"
for resolver in "${DNS_RESOLVERS[@]}"; do
  RESULT=$(dig +short +time=3 +tries=1 @"$resolver" "$DNS_TEST_DOMAIN" A 2>/dev/null | head -1)
  if [[ -n "$RESULT" ]]; then
    ok "${resolver} → ${DNS_TEST_DOMAIN} resolves to ${RESULT}"
  else
    crit "${resolver} → failed to resolve ${DNS_TEST_DOMAIN}"
  fi
done

echo ""
info "System default resolver test:"
RESULT=$(dig +short +time=3 "$DNS_TEST_DOMAIN" 2>/dev/null | head -1)
if [[ -n "$RESULT" ]]; then
  ok "System DNS resolves ${DNS_TEST_DOMAIN} → ${RESULT}"
else
  crit "System DNS FAILED to resolve ${DNS_TEST_DOMAIN}"
fi

echo ""
info "Reverse DNS (PTR) for own IPs:"
ip -br addr show 2>/dev/null | grep -v '^lo' | awk '{print $3}' | cut -d/ -f1 | while read -r ip; do
  [[ -z "$ip" ]] && continue
  PTR=$(dig +short -x "$ip" 2>/dev/null | head -1 || echo "none")
  printf "  %-20s → %s\n" "$ip" "${PTR:-no PTR record}"
done

# --------------------------------------------------------------------------- #
#  SECTION 4: Internet Connectivity
# --------------------------------------------------------------------------- #
hdr "4. Internet Connectivity"

for target in "${CONNECTIVITY_TARGETS[@]}"; do
  if ping -c3 -W2 "$target" &>/dev/null; then
    RTT=$(ping -c3 -W2 "$target" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
    ok "Ping ${target} — avg RTT: ${RTT}ms"
  else
    crit "Cannot reach ${target} via ICMP"
  fi
done

# HTTP connectivity
if curl -sIo /dev/null -w "%{http_code}" --connect-timeout 5 https://www.google.com &>/dev/null; then
  ok "HTTPS connectivity to www.google.com — OK"
else
  warn "HTTPS connectivity check failed (may be firewall-blocked)"
fi

# Custom target
if [[ -n "$TARGET_HOST" ]]; then
  echo ""
  info "Testing custom target: ${TARGET_HOST}"
  if ping -c3 -W2 "$TARGET_HOST" &>/dev/null; then
    ok "Ping ${TARGET_HOST} — reachable"
  else
    warn "Ping ${TARGET_HOST} — unreachable (may be ICMP-blocked)"
  fi

  for PORT in 80 443; do
    if nc -zw3 "$TARGET_HOST" "$PORT" &>/dev/null; then
      ok "TCP ${TARGET_HOST}:${PORT} — open"
    else
      warn "TCP ${TARGET_HOST}:${PORT} — closed or filtered"
    fi
  done
fi

# --------------------------------------------------------------------------- #
#  SECTION 5: Listening Ports
# --------------------------------------------------------------------------- #
hdr "5. Listening Ports and Services"

info "All listening TCP/UDP ports:"
ss -tulnp 2>/dev/null | grep -E 'LISTEN|udp' | \
  awk '{printf "  %-6s %-35s %s\n", $1, $5, $7}' | sort

echo ""
info "Unexpected high-privilege listeners (port < 1024, non-standard):"
EXPECTED_PORTS="22|80|443|53|25|587|993|3306|5432|6379|27017"
ss -tulnp 2>/dev/null | grep LISTEN | awk '{print $5}' | \
  grep -oP ':\K\d+$' | sort -n | while read -r port; do
  if (( port < 1024 )); then
    if ! echo "$port" | grep -qE "^($EXPECTED_PORTS)$"; then
      warn "Unexpected privileged port listening: ${port}"
    fi
  fi
done

echo ""
info "Connection count by state:"
ss -tan 2>/dev/null | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn | \
  while read -r count state; do printf "  %-25s %s connections\n" "$state" "$count"; done

# --------------------------------------------------------------------------- #
#  SECTION 6: Firewall Status
# --------------------------------------------------------------------------- #
hdr "6. Firewall Status"

# Check iptables
if command -v iptables &>/dev/null; then
  RULES=$(sudo iptables -L INPUT -n 2>/dev/null | grep -c '^[A-Z]' || echo 0)
  INPUT_POLICY=$(sudo iptables -L INPUT -n 2>/dev/null | head -1 | grep -oP '(?<=policy )\w+' || echo "UNKNOWN")
  printf "  %-25s %s\n" "iptables INPUT policy:" "$INPUT_POLICY"
  printf "  %-25s %s\n" "iptables INPUT rules:" "$RULES"

  if [[ "$INPUT_POLICY" == "ACCEPT" ]]; then
    warn "iptables INPUT policy is ACCEPT — no default deny"
  else
    ok "iptables INPUT policy: $INPUT_POLICY (default deny)"
  fi
fi

# Check ufw
if command -v ufw &>/dev/null; then
  UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1 | awk '{print $2}')
  printf "  %-25s %s\n" "UFW status:" "$UFW_STATUS"
  if [[ "$UFW_STATUS" != "active" ]]; then
    warn "UFW is not active"
  else
    ok "UFW is active"
  fi
fi

# Check nftables
if command -v nft &>/dev/null; then
  NFT_RULES=$(sudo nft list ruleset 2>/dev/null | grep -c 'policy\|rule' || echo 0)
  printf "  %-25s %s\n" "nftables rules:" "$NFT_RULES"
fi

# --------------------------------------------------------------------------- #
#  SECTION 7: Network Performance Snapshot
# --------------------------------------------------------------------------- #
hdr "7. Network Performance"

info "Current TCP connection counts:"
printf "  %-30s %s\n" "Total sockets:" "$(ss -s 2>/dev/null | grep 'Total:' | awk '{print $2}')"
printf "  %-30s %s\n" "TCP established:" "$(ss -tn state established 2>/dev/null | wc -l)"
printf "  %-30s %s\n" "TIME_WAIT sockets:" "$(ss -tan state time-wait 2>/dev/null | wc -l)"

echo ""
info "TCP retransmission stats:"
cat /proc/net/snmp 2>/dev/null | awk '
  /^Tcp:/ {
    if (NR%2==0) {
      printf "  RetransSegs:    %s\n", $13
      printf "  InErrors:       %s\n", $15
      printf "  OutRsts:        %s\n", $16
    }
  }
'

echo ""
info "Network sysctl key settings:"
for key in net.ipv4.tcp_syncookies net.ipv4.conf.all.rp_filter \
           net.ipv4.conf.all.accept_redirects net.core.somaxconn; do
  val=$(sysctl -n "$key" 2>/dev/null || echo "not set")
  printf "  %-45s %s\n" "${key}:" "$val"
done

# --------------------------------------------------------------------------- #
#  SECTION 8: NTP / Time Sync
# --------------------------------------------------------------------------- #
hdr "8. NTP / Time Synchronisation"

if command -v timedatectl &>/dev/null; then
  SYNCED=$(timedatectl 2>/dev/null | grep 'synchronized' | awk '{print $NF}')
  NTP_SVC=$(timedatectl 2>/dev/null | grep 'NTP service' | awk '{print $NF}')
  TIME_ZONE=$(timedatectl 2>/dev/null | grep 'Time zone' | awk '{print $3}')

  printf "  %-25s %s\n" "NTP synchronised:" "${SYNCED:-unknown}"
  printf "  %-25s %s\n" "NTP service:" "${NTP_SVC:-unknown}"
  printf "  %-25s %s\n" "Time zone:" "${TIME_ZONE:-unknown}"

  if [[ "$SYNCED" == "yes" ]]; then
    ok "NTP is synchronised"
  else
    warn "NTP is NOT synchronised — clock drift may cause issues"
  fi
fi

# --------------------------------------------------------------------------- #
#  SUMMARY
# --------------------------------------------------------------------------- #
hdr "DIAGNOSTICS SUMMARY"

echo ""
printf "  %-20s %s\n" "Host:"     "$HOSTNAME_VAL"
printf "  %-20s %s\n" "Checked:"  "$REPORT_DATE"
printf "  %-20s ${RED}%s${RESET}\n" "Critical:" "$CRIT_COUNT"
printf "  %-20s ${YELLOW}%s${RESET}\n" "Warnings:" "$WARN_COUNT"
echo ""

if [[ ${#ISSUES[@]} -gt 0 ]]; then
  echo -e "  ${BOLD}Issues:${RESET}"
  for issue in "${ISSUES[@]}"; do
    [[ "$issue" == CRIT* ]] && echo -e "  ${RED}  $issue${RESET}" || \
      echo -e "  ${YELLOW}  $issue${RESET}"
  done
else
  echo -e "  ${GREEN}  ✔ All network checks passed.${RESET}"
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
    --data "{\"text\": \"${EMOJI} *Network Diagnostics — ${HOSTNAME_VAL}*\n\`\`\`${ALERT_TEXT}\`\`\`\"}" \
    > /dev/null && echo "  Slack alert sent." || echo "  Slack send failed."
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
# Repo   : linux-for-devops/03-networking
# =============================================================================
