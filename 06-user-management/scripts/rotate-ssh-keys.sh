#!/bin/bash
# =============================================================================
# rotate-ssh-keys.sh
# Safely rotate SSH keys for a user on one or more remote servers.
# Follows the safe add-verify-remove pattern so access is never lost mid-rotation.
#
# Usage:
#   ./rotate-ssh-keys.sh --user USER --servers "host1 host2 host3" [options]
#
# Options:
#   --user USER          Local username whose key is being rotated (required)
#   --servers HOSTS      Space-separated list of target servers (required)
#   --old-key FILE       Path to old private key (default: ~/.ssh/id_ed25519)
#   --new-key FILE       Path for new private key (generated if not provided)
#   --key-type TYPE      Key type: ed25519 (default) or rsa
#   --key-bits BITS      Bits for RSA keys (default: 4096)
#   --comment COMMENT    Key comment (default: user@host-YEAR)
#   --dry-run            Preview steps without making changes
#   --skip-verify        Skip new-key verification step (not recommended)
#   --remove-old         Remove old private key locally after successful rotation
#   --backup-dir DIR     Directory to archive old keys (default: ~/.ssh/retired)
#
# Examples:
#   ./rotate-ssh-keys.sh --user deployer --servers "web1 web2 web3"
#   ./rotate-ssh-keys.sh --user ci-deploy --servers "prod-1 prod-2" \
#       --old-key ~/.ssh/id_ed25519_2023 --new-key ~/.ssh/id_ed25519_2024
#   ./rotate-ssh-keys.sh --user john.doe --servers "bastion.example.com" --remove-old
#
# Author : Eknatha
# Repo   : linux-for-devops/06-user-management
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
#  Colours
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
step()    { echo ""; echo -e "${BOLD}▶ Step $*${RESET}"; }

# --------------------------------------------------------------------------- #
#  Defaults
# --------------------------------------------------------------------------- #
ROTATE_USER="${USER:-}"
SERVERS=""
OLD_KEY="${HOME}/.ssh/id_ed25519"
NEW_KEY=""
KEY_TYPE="ed25519"
KEY_BITS="4096"
KEY_COMMENT=""
DRY_RUN=false
SKIP_VERIFY=false
REMOVE_OLD=false
BACKUP_DIR="${HOME}/.ssh/retired"
YEAR=$(date +%Y)
FAILED_SERVERS=()
SUCCESS_SERVERS=()

# --------------------------------------------------------------------------- #
#  Argument parsing
# --------------------------------------------------------------------------- #
usage() { sed -n '3,24p' "$0" | sed 's/^# \?//'; exit 0; }

[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)        ROTATE_USER="$2";  shift 2 ;;
    --servers)     SERVERS="$2";      shift 2 ;;
    --old-key)     OLD_KEY="$2";      shift 2 ;;
    --new-key)     NEW_KEY="$2";      shift 2 ;;
    --key-type)    KEY_TYPE="$2";     shift 2 ;;
    --key-bits)    KEY_BITS="$2";     shift 2 ;;
    --comment)     KEY_COMMENT="$2";  shift 2 ;;
    --dry-run)     DRY_RUN=true;      shift   ;;
    --skip-verify) SKIP_VERIFY=true;  shift   ;;
    --remove-old)  REMOVE_OLD=true;   shift   ;;
    --backup-dir)  BACKUP_DIR="$2";   shift 2 ;;
    -h|--help)     usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

# --------------------------------------------------------------------------- #
#  Validation
# --------------------------------------------------------------------------- #
[[ -z "$ROTATE_USER" ]] && die "--user is required."
[[ -z "$SERVERS"     ]] && die "--servers is required."

[[ -z "$KEY_COMMENT" ]] && KEY_COMMENT="${ROTATE_USER}@$(hostname -s)-${YEAR}"
[[ -z "$NEW_KEY"     ]] && NEW_KEY="${HOME}/.ssh/id_${KEY_TYPE}_${YEAR}"

if [[ ! -f "${OLD_KEY}" ]]; then
  warn "Old private key not found: ${OLD_KEY}"
  warn "Will attempt rotation using default SSH agent / keys."
fi

# --------------------------------------------------------------------------- #
#  Dry-run wrapper
# --------------------------------------------------------------------------- #
run() {
  if $DRY_RUN; then
    echo -e "  ${YELLOW}[DRY-RUN]${RESET} $*"
    return 0
  fi
  eval "$@"
}

# --------------------------------------------------------------------------- #
#  Banner
# --------------------------------------------------------------------------- #
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}   SSH Key Rotation Script — linux-for-devops       ${RESET}"
echo -e "${BOLD}   Author: Eknatha                                   ${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
printf "  %-20s %s\n" "User:"        "$ROTATE_USER"
printf "  %-20s %s\n" "Servers:"     "$SERVERS"
printf "  %-20s %s\n" "Old key:"     "$OLD_KEY"
printf "  %-20s %s\n" "New key:"     "$NEW_KEY"
printf "  %-20s %s\n" "Key type:"    "$KEY_TYPE"
printf "  %-20s %s\n" "Comment:"     "$KEY_COMMENT"
printf "  %-20s %s\n" "Remove old:"  "$REMOVE_OLD"
printf "  %-20s %s\n" "Backup dir:"  "$BACKUP_DIR"
$DRY_RUN && warn "DRY-RUN mode — no changes will be made."
echo ""

# --------------------------------------------------------------------------- #
#  PHASE 1: Generate new key pair
# --------------------------------------------------------------------------- #
step "1/5 — Generate new SSH key pair"

if [[ -f "${NEW_KEY}" ]]; then
  warn "New key already exists at ${NEW_KEY}. Skipping generation."
  info "Fingerprint: $(ssh-keygen -lf "${NEW_KEY}" 2>/dev/null || echo 'N/A')"
else
  info "Generating new ${KEY_TYPE} key: ${NEW_KEY}"

  if [[ "$KEY_TYPE" == "ed25519" ]]; then
    run "ssh-keygen -t ed25519 -C '${KEY_COMMENT}' -f '${NEW_KEY}' -N ''"
  elif [[ "$KEY_TYPE" == "rsa" ]]; then
    run "ssh-keygen -t rsa -b ${KEY_BITS} -C '${KEY_COMMENT}' -f '${NEW_KEY}' -N ''"
  else
    die "Unsupported key type: ${KEY_TYPE}. Use ed25519 or rsa."
  fi

  if ! $DRY_RUN; then
    chmod 600 "${NEW_KEY}"
    chmod 644 "${NEW_KEY}.pub"
    success "New key pair generated."
    info "Fingerprint: $(ssh-keygen -lf "${NEW_KEY}.pub")"
  fi
fi

NEW_PUBKEY_CONTENT=$(cat "${NEW_KEY}.pub" 2>/dev/null || echo "DRY-RUN-PLACEHOLDER-KEY")

# --------------------------------------------------------------------------- #
#  PHASE 2: Deploy new key to all servers
# --------------------------------------------------------------------------- #
step "2/5 — Deploy new public key to servers"
info "Adding new key ALONGSIDE the old key (safe rotation)."
echo ""

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes"
[[ -f "$OLD_KEY" ]] && SSH_OPTS="${SSH_OPTS} -i ${OLD_KEY}"

for server in $SERVERS; do
  info "Deploying to ${server}..."

  REMOTE_CMD="
    set -e
    AUTH_FILE=\$(eval echo ~${ROTATE_USER})/.ssh/authorized_keys
    mkdir -p \$(eval echo ~${ROTATE_USER})/.ssh
    chmod 700 \$(eval echo ~${ROTATE_USER})/.ssh

    # Add new key only if not already present
    if ! grep -qF '${NEW_PUBKEY_CONTENT}' \"\${AUTH_FILE}\" 2>/dev/null; then
      echo '${NEW_PUBKEY_CONTENT}' >> \"\${AUTH_FILE}\"
      chmod 600 \"\${AUTH_FILE}\"
      chown ${ROTATE_USER}:${ROTATE_USER} \"\${AUTH_FILE}\"
      echo 'KEY_ADDED'
    else
      echo 'KEY_ALREADY_PRESENT'
    fi
  "

  if $DRY_RUN; then
    echo -e "  ${YELLOW}[DRY-RUN]${RESET} ssh ${ROTATE_USER}@${server} '... add new key to authorized_keys ...'"
  else
    RESULT=$(ssh $SSH_OPTS "${ROTATE_USER}@${server}" "sudo bash -s" <<< "$REMOTE_CMD" 2>&1) || {
      error "Failed to deploy to ${server}: ${RESULT}"
      FAILED_SERVERS+=("${server}")
      continue
    }
    echo "  Result: ${RESULT}"
    success "New key deployed to ${server}."
  fi
done

# --------------------------------------------------------------------------- #
#  PHASE 3: Verify new key works on all servers
# --------------------------------------------------------------------------- #
step "3/5 — Verify new key authentication"

if $SKIP_VERIFY; then
  warn "Skipping verification (--skip-verify set)."
else
  info "Testing authentication with NEW key on each server..."
  echo ""

  for server in $SERVERS; do
    # Skip servers that already failed
    [[ " ${FAILED_SERVERS[*]:-} " == *" ${server} "* ]] && continue

    if $DRY_RUN; then
      echo -e "  ${YELLOW}[DRY-RUN]${RESET} ssh -i ${NEW_KEY} ${ROTATE_USER}@${server} echo OK"
    else
      VERIFY=$(ssh \
        -i "${NEW_KEY}" \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        "${ROTATE_USER}@${server}" \
        "echo SSH_OK" 2>&1) || {
          error "New key verification FAILED on ${server}!"
          error "Old key NOT removed from ${server}. Fix manually before proceeding."
          FAILED_SERVERS+=("${server}")
          continue
      }

      if [[ "$VERIFY" == *"SSH_OK"* ]]; then
        success "New key verified on ${server}."
        SUCCESS_SERVERS+=("${server}")
      else
        warn "Unexpected response from ${server}: ${VERIFY}"
        FAILED_SERVERS+=("${server}")
      fi
    fi
  done
fi

# --------------------------------------------------------------------------- #
#  PHASE 4: Remove old key from servers
# --------------------------------------------------------------------------- #
step "4/5 — Remove old public key from servers"

OLD_PUBKEY_CONTENT=""
if [[ -f "${OLD_KEY}.pub" ]]; then
  OLD_PUBKEY_CONTENT=$(cat "${OLD_KEY}.pub")
  info "Old key to remove: $(ssh-keygen -lf "${OLD_KEY}.pub" 2>/dev/null)"
else
  warn "Old public key file not found (${OLD_KEY}.pub). Cannot auto-remove from servers."
  warn "You must manually remove the old key from each server's authorized_keys."
fi

if [[ -n "$OLD_PUBKEY_CONTENT" ]]; then
  for server in $SERVERS; do
    [[ " ${FAILED_SERVERS[*]:-} " == *" ${server} "* ]] && {
      warn "Skipping old key removal on ${server} (deploy/verify failed)."
      continue
    }

    info "Removing old key from ${server}..."
    REMOVE_CMD="
      AUTH_FILE=\$(eval echo ~${ROTATE_USER})/.ssh/authorized_keys
      if [ -f \"\${AUTH_FILE}\" ]; then
        # Escape special chars for grep
        sed -i '/${OLD_PUBKEY_CONTENT//\//\\/}/d' \"\${AUTH_FILE}\" 2>/dev/null || true
        grep -vF '${OLD_PUBKEY_CONTENT}' \"\${AUTH_FILE}\" > /tmp/.ak_tmp && mv /tmp/.ak_tmp \"\${AUTH_FILE}\"
        chmod 600 \"\${AUTH_FILE}\"
        echo 'OLD_KEY_REMOVED'
      else
        echo 'AUTH_FILE_NOT_FOUND'
      fi
    "

    if $DRY_RUN; then
      echo -e "  ${YELLOW}[DRY-RUN]${RESET} ssh ${ROTATE_USER}@${server} '... remove old key from authorized_keys ...'"
    else
      RESULT=$(ssh \
        -i "${NEW_KEY}" \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        "${ROTATE_USER}@${server}" \
        "sudo bash -s" <<< "$REMOVE_CMD" 2>&1) || {
          error "Failed to remove old key from ${server}: ${RESULT}"
          continue
      }
      echo "  Result: ${RESULT}"
      success "Old key removed from ${server}."
    fi
  done
fi

# --------------------------------------------------------------------------- #
#  PHASE 5: Archive / Remove old local key
# --------------------------------------------------------------------------- #
step "5/5 — Handle old local key"

mkdir -p "$BACKUP_DIR"

if [[ -f "$OLD_KEY" ]]; then
  BACKUP_NAME="${BACKUP_DIR}/$(basename ${OLD_KEY})-retired-$(date +%Y%m%d)"
  info "Archiving old private key to ${BACKUP_NAME}"
  run "cp '${OLD_KEY}' '${BACKUP_NAME}'"
  run "chmod 400 '${BACKUP_NAME}'"

  if [[ -f "${OLD_KEY}.pub" ]]; then
    run "cp '${OLD_KEY}.pub' '${BACKUP_NAME}.pub'"
  fi

  if $REMOVE_OLD && ! $DRY_RUN; then
    warn "Removing old private key: ${OLD_KEY}"
    rm -f "${OLD_KEY}" "${OLD_KEY}.pub"
    success "Old key removed locally."
  elif ! $REMOVE_OLD; then
    info "Old key retained at ${OLD_KEY} (use --remove-old to delete after confirming access)."
  fi
else
  info "Old private key not found locally — nothing to archive."
fi

# --------------------------------------------------------------------------- #
#  SUMMARY
# --------------------------------------------------------------------------- #
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}   Rotation Summary${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
printf "  %-25s %s\n" "New key:"  "${NEW_KEY}"
if ! $DRY_RUN && [[ -f "${NEW_KEY}.pub" ]]; then
  printf "  %-25s %s\n" "Fingerprint:" "$(ssh-keygen -lf "${NEW_KEY}.pub")"
fi
echo ""

if [[ ${#SUCCESS_SERVERS[@]} -gt 0 ]]; then
  echo -e "${GREEN}  ✔ Successfully rotated on:${RESET}"
  for s in "${SUCCESS_SERVERS[@]}"; do echo "    - $s"; done
fi

if [[ ${#FAILED_SERVERS[@]} -gt 0 ]]; then
  echo -e "${RED}  ✘ Failed on:${RESET}"
  for s in "${FAILED_SERVERS[@]}"; do echo "    - $s (old key still active)"; done
  echo ""
  warn "Manual intervention required on failed servers."
fi

echo ""
echo -e "  ${CYAN}Next steps:${RESET}"
echo "  1. Update ~/.ssh/config to point to the new key: ${NEW_KEY}"
echo "  2. Inform team members if this is a shared deploy key"
echo "  3. Update CI/CD secrets (GitHub Actions, Jenkins, GitLab, etc.)"
echo "  4. Update any key tracking documentation / CMDB"
echo ""

# =============================================================================
# IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE
# Author : Eknatha
# Repo   : linux-for-devops/06-user-management
# =============================================================================
