#!/bin/bash
# =============================================================================
# dns-check.sh
# DNS resolution and propagation tester — checks A/AAAA/MX/TXT/NS records,
# tests multiple resolvers, measures query time, and verifies certificate
# hostname matching. Useful for deployments, migrations, and incident triage.
#
# Usage:
#   ./dns-check.sh --domain DOMAIN [options]
#
# Options:
#   --domain DOMAIN       Domain to check (required)
#   --type TYPE           Record type: A|AAAA|MX|TXT|NS|CNAME|PTR|all (default: all)
#   --resolvers LIST      Comma-separated resolvers to test (default: built-in set)
#   --expected-ip IP      Assert the A record resolves to this IP
#   --check-cert          Check TLS certificate validity and expiry
#   --check-propagation   Test against multiple public resolvers
#   --output FILE         Save report to file
#   --slack WEBHOOK       Post results to Slack
#   --quiet               Suppress output (use with --output)
#
# Examples:
#   ./dns-check.sh --domain api.example.com
#   ./dns-check.sh --domain api.example.com --expected-ip 10.0.1.20 --check-cert
#   ./dns-check.sh --domain example.com --type MX
#   ./dns-check.sh --domain api.example.com --check-propagation
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
fail() { echo -e "  ${RED}✘${RESET}  $*"; FAIL_COUNT=$((FAIL_COUNT+1)); ISSUES+=("FAIL: $*"); }
info() { echo -e "  ${CYAN}➜${RESET}  $*"; }
hdr()  { echo ""; echo -e "${BOLD}  ── $* ──${RESET}"; }

# --------------------------------------------------------------------------- #
#  Defaults
# --------------------------------------------------------------------------- #
DOMAIN=""
RECORD_TYPE="all"
CUSTOM_RESOLVERS=""
EXPECTED_IP=""
CHECK_CERT=false
CHECK_PROPAGATION=false
OUTPUT_FILE=""
SLACK_WEBHOOK=""
QUIET=false
WARN_COUNT=0
FAIL_COUNT=0
ISSUES=()

# Public resolvers for propagation checks
PROPAGATION_RESOLVERS=(
  "8.8.8.8:Google"
  "8.8.4.4:Google-2"
  "1.1.1.1:Cloudflare"
  "1.0.0.1:Cloudflare-2"
  "9.9.9.9:Quad9"
  "208.67.222.222:OpenDNS"
  "208.67.220.220:OpenDNS-2"
  "185.228.168.9:CleanBrowsing"
)

# --------------------------------------------------------------------------- #
#  Argument parsing
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)             DOMAIN="$2";          shift 2 ;;
    --type)               RECORD_TYPE="$2";     shift 2 ;;
    --resolvers)          CUSTOM_RESOLVERS="$2"; shift 2 ;;
    --expected-ip)        EXPECTED_IP="$2";     shift 2 ;;
    --check-cert)         CHECK_CERT=true;       shift ;;
    --check-propagation)  CHECK_PROPAGATION=true; shift ;;
    --output)             OUTPUT_FILE="$2";     shift 2 ;;
    --slack)              SLACK_WEBHOOK="$2";   shift 2 ;;
    --quiet)              QUIET=true;           shift ;;
    -h|--help) sed -n '3,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$DOMAIN" ]] && { echo "Error: --domain is required." >&2; exit 1; }
[[ -n "$OUTPUT_FILE" ]] && exec > >(tee "$OUTPUT_FILE") 2>&1
$QUIET && [[ -n "$OUTPUT_FILE" ]] && exec >/dev/null

# --------------------------------------------------------------------------- #
#  Dependency check
# --------------------------------------------------------------------------- #
for cmd in dig; do
  command -v "$cmd" &>/dev/null || { echo "Error: '$cmd' not found. Install dnsutils." >&2; exit 1; }
done

# --------------------------------------------------------------------------- #
#  Header
# --------------------------------------------------------------------------- #
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║       DNS Check Report                           ║${RESET}"
echo -e "${BOLD}║       Author: Eknatha                            ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
printf "  %-20s %s\n" "Domain:"     "$DOMAIN"
printf "  %-20s %s\n" "Record type:" "$RECORD_TYPE"
printf "  %-20s %s\n" "Date:"       "$(date '+%Y-%m-%d %H:%M:%S %Z')"

# --------------------------------------------------------------------------- #
#  Helper: query a record type
# --------------------------------------------------------------------------- #
query_record() {
  local resolver="${1:-}"
  local domain="$2"
  local type="$3"
  local server_flag=""
  [[ -n "$resolver" ]] && server_flag="@${resolver}"

  dig +short +time=5 +tries=2 $server_flag "$domain" "$type" 2>/dev/null || echo ""
}

query_time() {
  local resolver="${1:-}"
  local domain="$2"
  local type="$3"
  local server_flag=""
  [[ -n "$resolver" ]] && server_flag="@${resolver}"

  dig +time=5 +tries=2 $server_flag "$domain" "$type" 2>/dev/null \
    | grep "Query time:" | awk '{print $4}'
}

# --------------------------------------------------------------------------- #
#  SECTION 1: System resolver check
# --------------------------------------------------------------------------- #
hdr "1. System Resolver"

SYS_RESOLVER=$(grep '^nameserver' /etc/resolv.conf 2>/dev/null | head -1 | awk '{print $2}')
printf "  %-20s %s\n" "System resolver:" "${SYS_RESOLVER:-default}"

# --------------------------------------------------------------------------- #
#  SECTION 2: A Record
# --------------------------------------------------------------------------- #
check_a_record() {
  hdr "2. A Record (IPv4)"
  RESULT=$(query_record "" "$DOMAIN" "A")
  QT=$(query_time "" "$DOMAIN" "A")

  if [[ -n "$RESULT" ]]; then
    while IFS= read -r ip; do
      ok "${DOMAIN} → ${ip}"
    done <<< "$RESULT"
    printf "  %-20s %s ms\n" "Query time:" "${QT:-?}"

    if [[ -n "$EXPECTED_IP" ]]; then
      if echo "$RESULT" | grep -q "^${EXPECTED_IP}$"; then
        ok "Expected IP ${EXPECTED_IP} — MATCHED"
      else
        fail "Expected IP ${EXPECTED_IP} — GOT: $(echo "$RESULT" | tr '\n' ',')"
      fi
    fi
  else
    fail "${DOMAIN} — no A record found (NXDOMAIN or timeout)"
  fi
}

# --------------------------------------------------------------------------- #
#  SECTION 3: AAAA Record (IPv6)
# --------------------------------------------------------------------------- #
check_aaaa_record() {
  hdr "3. AAAA Record (IPv6)"
  RESULT=$(query_record "" "$DOMAIN" "AAAA")
  if [[ -n "$RESULT" ]]; then
    while IFS= read -r ip; do ok "${DOMAIN} → ${ip}"; done <<< "$RESULT"
  else
    info "No AAAA record (IPv6 not configured — OK if IPv6 not needed)"
  fi
}

# --------------------------------------------------------------------------- #
#  SECTION 4: NS Records
# --------------------------------------------------------------------------- #
check_ns_record() {
  hdr "4. NS Records (Nameservers)"
  RESULT=$(query_record "" "$DOMAIN" "NS")
  if [[ -n "$RESULT" ]]; then
    while IFS= read -r ns; do
      ok "NS: ${ns}"
    done <<< "$RESULT"
  else
    fail "No NS records found for ${DOMAIN}"
  fi
}

# --------------------------------------------------------------------------- #
#  SECTION 5: MX Records
# --------------------------------------------------------------------------- #
check_mx_record() {
  hdr "5. MX Records (Mail)"
  RESULT=$(query_record "" "$DOMAIN" "MX")
  if [[ -n "$RESULT" ]]; then
    while IFS= read -r mx; do ok "MX: ${mx}"; done <<< "$RESULT"
  else
    warn "No MX records found for ${DOMAIN} — email delivery not configured"
  fi
}

# --------------------------------------------------------------------------- #
#  SECTION 6: TXT Records
# --------------------------------------------------------------------------- #
check_txt_record() {
  hdr "6. TXT Records (SPF, DKIM, DMARC)"
  RESULT=$(query_record "" "$DOMAIN" "TXT")
  if [[ -n "$RESULT" ]]; then
    echo "$RESULT" | while IFS= read -r txt; do
      # Identify record type
      if echo "$txt" | grep -qi 'v=spf'; then
        ok "SPF: ${txt}"
      elif echo "$txt" | grep -qi 'v=DMARC'; then
        ok "DMARC: ${txt}"
      elif echo "$txt" | grep -qi 'v=DKIM'; then
        ok "DKIM: ${txt}"
      else
        info "TXT: ${txt}"
      fi
    done

    # Check SPF present
    if ! echo "$RESULT" | grep -qi 'v=spf'; then
      warn "No SPF record found — email spoofing risk"
    fi

    # Check DMARC
    DMARC=$(query_record "" "_dmarc.${DOMAIN}" "TXT")
    if [[ -n "$DMARC" ]]; then
      ok "DMARC: ${DMARC}"
    else
      warn "No DMARC record found at _dmarc.${DOMAIN}"
    fi
  else
    warn "No TXT records found for ${DOMAIN}"
  fi
}

# --------------------------------------------------------------------------- #
#  SECTION 7: CNAME Check
# --------------------------------------------------------------------------- #
check_cname_record() {
  hdr "7. CNAME Record"
  RESULT=$(query_record "" "$DOMAIN" "CNAME")
  if [[ -n "$RESULT" ]]; then
    ok "CNAME: ${DOMAIN} → ${RESULT}"
  else
    info "No CNAME record (domain is apex or A record — OK)"
  fi
}

# --------------------------------------------------------------------------- #
#  SECTION 8: Reverse DNS (PTR)
# --------------------------------------------------------------------------- #
check_ptr_record() {
  hdr "8. Reverse DNS (PTR)"
  IP=$(query_record "" "$DOMAIN" "A" | head -1)
  if [[ -n "$IP" ]]; then
    PTR=$(dig +short -x "$IP" 2>/dev/null | head -1)
    if [[ -n "$PTR" ]]; then
      ok "PTR: ${IP} → ${PTR}"
      # Forward-confirmed reverse DNS check
      FWD=$(query_record "" "$PTR" "A" | head -1)
      if [[ "$FWD" == "$IP" ]]; then
        ok "FCrDNS: ${PTR} resolves back to ${IP} ✔"
      else
        warn "FCrDNS mismatch: ${PTR} resolves to ${FWD:-nothing}, expected ${IP}"
      fi
    else
      warn "No PTR record for ${IP} — may affect email deliverability"
    fi
  fi
}

# --------------------------------------------------------------------------- #
#  SECTION 9: TLS Certificate
# --------------------------------------------------------------------------- #
check_certificate() {
  hdr "9. TLS Certificate"
  if ! command -v openssl &>/dev/null; then
    warn "openssl not installed — skipping certificate check"
    return
  fi

  CERT_INFO=$(echo | timeout 5 openssl s_client \
    -connect "${DOMAIN}:443" \
    -servername "$DOMAIN" 2>/dev/null || echo "")

  if [[ -z "$CERT_INFO" ]]; then
    fail "Could not connect to ${DOMAIN}:443"
    return
  fi

  SUBJECT=$(echo "$CERT_INFO" | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//')
  ISSUER=$(echo "$CERT_INFO" | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//')
  END_DATE=$(echo "$CERT_INFO" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  DAYS_LEFT=$(( ($(date -d "$END_DATE" +%s 2>/dev/null || echo 0) - $(date +%s)) / 86400 ))
  SANS=$(echo "$CERT_INFO" | openssl x509 -noout -text 2>/dev/null \
    | grep -A1 'Subject Alternative Name' | tail -1 | tr ',' '\n' | grep DNS | xargs)

  printf "  %-20s %s\n" "Subject:"  "$SUBJECT"
  printf "  %-20s %s\n" "Issuer:"   "$ISSUER"
  printf "  %-20s %s\n" "Expires:"  "$END_DATE"
  printf "  %-20s %s\n" "SANs:"     "${SANS:-none}"

  if (( DAYS_LEFT <= 0 )); then
    fail "Certificate EXPIRED"
  elif (( DAYS_LEFT <= 14 )); then
    fail "Certificate expires in ${DAYS_LEFT} days — RENEW IMMEDIATELY"
  elif (( DAYS_LEFT <= 30 )); then
    warn "Certificate expires in ${DAYS_LEFT} days — schedule renewal"
  else
    ok "Certificate valid for ${DAYS_LEFT} more days"
  fi

  # Check domain matches
  if echo "$SANS $SUBJECT" | grep -qi "$DOMAIN\|\\*\.${DOMAIN#*.}"; then
    ok "Certificate covers ${DOMAIN}"
  else
    fail "Certificate does NOT cover ${DOMAIN}"
  fi
}

# --------------------------------------------------------------------------- #
#  SECTION 10: Propagation Check
# --------------------------------------------------------------------------- #
check_propagation() {
  hdr "10. DNS Propagation (Public Resolvers)"
  info "Testing A record propagation across public resolvers..."
  echo ""

  printf "  %-25s %-20s %-12s %s\n" "Resolver" "Name" "Result" "Time"
  printf "  %s\n" "$(printf '%.0s─' {1..70})"

  UNIQUE_IPS=()
  for entry in "${PROPAGATION_RESOLVERS[@]}"; do
    resolver="${entry%%:*}"
    name="${entry##*:}"

    RESULT=$(query_record "$resolver" "$DOMAIN" "A")
    QT=$(query_time "$resolver" "$DOMAIN" "A")

    if [[ -n "$RESULT" ]]; then
      FIRST_IP=$(echo "$RESULT" | head -1)
      printf "  %-25s %-20s %-12s %s ms\n" "$resolver" "$name" "$FIRST_IP" "${QT:-?}"
      UNIQUE_IPS+=("$FIRST_IP")
    else
      printf "  %-25s %-20s %-12s\n" "$resolver" "$name" "FAILED"
      warn "Resolver ${resolver} (${name}) failed to resolve ${DOMAIN}"
    fi
  done

  # Check consistency
  echo ""
  UNIQUE=$(printf '%s\n' "${UNIQUE_IPS[@]}" | sort -u | wc -l)
  if (( UNIQUE == 1 )); then
    ok "All resolvers return consistent answer: $(printf '%s\n' "${UNIQUE_IPS[@]}" | sort -u)"
  elif (( UNIQUE > 1 )); then
    warn "Inconsistent answers across resolvers — DNS may be propagating or split-horizon:"
    printf '%s\n' "${UNIQUE_IPS[@]}" | sort -u | while read -r ip; do echo "    ${ip}"; done
  fi
}

# --------------------------------------------------------------------------- #
#  Dispatch
# --------------------------------------------------------------------------- #
case "$RECORD_TYPE" in
  A)     check_a_record ;;
  AAAA)  check_aaaa_record ;;
  NS)    check_ns_record ;;
  MX)    check_mx_record ;;
  TXT)   check_txt_record ;;
  CNAME) check_cname_record ;;
  PTR)   check_ptr_record ;;
  all)
    check_a_record
    check_aaaa_record
    check_ns_record
    check_mx_record
    check_txt_record
    check_cname_record
    check_ptr_record
    ;;
esac

$CHECK_CERT && check_certificate
$CHECK_PROPAGATION && check_propagation

# --------------------------------------------------------------------------- #
#  Summary
# --------------------------------------------------------------------------- #
echo ""
echo -e "${BOLD}  ── Summary ──${RESET}"
printf "  %-20s %s\n" "Domain:"   "$DOMAIN"
printf "  %-20s ${RED}%s${RESET}\n" "Failures:"  "$FAIL_COUNT"
printf "  %-20s ${YELLOW}%s${RESET}\n" "Warnings:" "$WARN_COUNT"
echo ""

if [[ ${#ISSUES[@]} -gt 0 ]]; then
  echo -e "  ${BOLD}Issues:${RESET}"
  for issue in "${ISSUES[@]}"; do
    [[ "$issue" == FAIL* ]] && echo -e "  ${RED}  $issue${RESET}" || \
      echo -e "  ${YELLOW}  $issue${RESET}"
  done
else
  echo -e "  ${GREEN}  ✔ All DNS checks passed.${RESET}"
fi

# Slack
if [[ -n "$SLACK_WEBHOOK" ]] && [[ ${#ISSUES[@]} -gt 0 ]]; then
  ALERT_TEXT=$(printf '%s\n' "${ISSUES[@]}" | sed 's/^/• /')
  curl -s -X POST "$SLACK_WEBHOOK" \
    -H 'Content-type: application/json' \
    --data "{\"text\": \":warning: *DNS Check — ${DOMAIN}*\n\`\`\`${ALERT_TEXT}\`\`\`\"}" \
    > /dev/null
fi

echo ""
(( FAIL_COUNT > 0 )) && exit 2
(( WARN_COUNT > 0 )) && exit 1
exit 0

# =============================================================================
# IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE
# Author : Eknatha
# Repo   : linux-for-devops/03-networking
# =============================================================================
