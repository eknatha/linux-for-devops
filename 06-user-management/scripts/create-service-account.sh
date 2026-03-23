#!/bin/bash
# =============================================================================
# create-service-account.sh
# Automate service/application user creation for production Linux systems
#
# Usage:
#   sudo ./create-service-account.sh <app-name> [options]
#
# Options:
#   --home DIR        Custom home/data directory (default: /opt/<app-name>)
#   --group GROUP     Additional group to add (can repeat)
#   --ssh-key KEY     SSH public key string to deploy
#   --port PORT       Port the service uses (for documentation only)
#   --no-home         Skip home directory creation
#   --dry-run         Preview actions without making changes
#
# Examples:
#   sudo ./create-service-account.sh myapp
#   sudo ./create-service-account.sh prometheus --home /var/lib/prometheus
#   sudo ./create-service-account.sh ci-deploy --group docker --group deployers \
#        --ssh-key "ssh-ed25519 AAAA... ci@github"
#
# Author : Eknatha
# Repo   : linux-for-devops/06-user-management
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
#  Colour helpers
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# --------------------------------------------------------------------------- #
#  Root check
# --------------------------------------------------------------------------- #
[[ $EUID -eq 0 ]] || die "This script must be run as root (use sudo)."

# --------------------------------------------------------------------------- #
#  Defaults
# --------------------------------------------------------------------------- #
APP_NAME=""
HOME_DIR=""
EXTRA_GROUPS=()
SSH_KEY=""
CREATE_HOME=true
DRY_RUN=false
SHELL_PATH="/usr/sbin/nologin"

# --------------------------------------------------------------------------- #
#  Argument parsing
# --------------------------------------------------------------------------- #
usage() {
  sed -n '3,18p' "$0" | sed 's/^# \?//'
  exit 0
}

[[ $# -eq 0 ]] && usage

APP_NAME="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home)      HOME_DIR="$2";        shift 2 ;;
    --group)     EXTRA_GROUPS+=("$2"); shift 2 ;;
    --ssh-key)   SSH_KEY="$2";         shift 2 ;;
    --port)      shift 2 ;;   # accepted but informational only
    --no-home)   CREATE_HOME=false;    shift   ;;
    --dry-run)   DRY_RUN=true;         shift   ;;
    -h|--help)   usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

# Default home dir
[[ -z "$HOME_DIR" ]] && HOME_DIR="/opt/${APP_NAME}"

# --------------------------------------------------------------------------- #
#  Validation
# --------------------------------------------------------------------------- #
[[ "$APP_NAME" =~ ^[a-z][a-z0-9_-]{1,31}$ ]] || \
  die "Invalid app name '$APP_NAME'. Use lowercase letters, digits, hyphens, underscores (2-32 chars)."

# --------------------------------------------------------------------------- #
#  Dry-run wrapper
# --------------------------------------------------------------------------- #
run() {
  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN]${RESET} $*"
  else
    eval "$@"
  fi
}

# --------------------------------------------------------------------------- #
#  Banner
# --------------------------------------------------------------------------- #
echo ""
echo -e "${BOLD}=================================================${RESET}"
echo -e "${BOLD}  Service Account Creator — linux-for-devops     ${RESET}"
echo -e "${BOLD}  Author: Eknatha                                ${RESET}"
echo -e "${BOLD}=================================================${RESET}"
echo ""
info  "App name   : ${APP_NAME}"
info  "Home dir   : ${HOME_DIR}"
info  "Shell      : ${SHELL_PATH}"
info  "Extra groups: ${EXTRA_GROUPS[*]:-none}"
info  "SSH key    : ${SSH_KEY:+provided}${SSH_KEY:-none}"
$DRY_RUN && warn "DRY-RUN mode — no changes will be made."
echo ""

# --------------------------------------------------------------------------- #
#  1. Check if user already exists
# --------------------------------------------------------------------------- #
if id "$APP_NAME" &>/dev/null; then
  warn "User '${APP_NAME}' already exists. Skipping creation."
else
  info "Creating system user: ${APP_NAME}"
  if $CREATE_HOME; then
    run "useradd \
      --system \
      --home-dir '${HOME_DIR}' \
      --no-create-home \
      --shell '${SHELL_PATH}' \
      --comment '${APP_NAME} service account' \
      '${APP_NAME}'"
  else
    run "useradd \
      --system \
      --no-create-home \
      --shell '${SHELL_PATH}' \
      --comment '${APP_NAME} service account' \
      '${APP_NAME}'"
  fi
  success "User '${APP_NAME}' created (UID: $(id -u ${APP_NAME} 2>/dev/null || echo 'N/A (dry-run)'))"
fi

# --------------------------------------------------------------------------- #
#  2. Add to extra groups
# --------------------------------------------------------------------------- #
for grp in "${EXTRA_GROUPS[@]}"; do
  if getent group "$grp" &>/dev/null; then
    info "Adding ${APP_NAME} to group: ${grp}"
    run "usermod --append --groups '${grp}' '${APP_NAME}'"
    success "Added to group: ${grp}"
  else
    warn "Group '${grp}' does not exist — skipping."
  fi
done

# --------------------------------------------------------------------------- #
#  3. Create directory structure
# --------------------------------------------------------------------------- #
if $CREATE_HOME; then
  info "Creating directory structure under ${HOME_DIR}"
  for dir in "" "/bin" "/conf" "/data" "/logs" "/tmp"; do
    run "mkdir -p '${HOME_DIR}${dir}'"
  done

  # Ownership: service user owns data/logs/tmp; root owns bin/conf
  run "chown root:${APP_NAME}  '${HOME_DIR}'"
  run "chmod 750               '${HOME_DIR}'"

  run "chown root:root         '${HOME_DIR}/bin'"
  run "chmod 755               '${HOME_DIR}/bin'"

  run "chown root:${APP_NAME}  '${HOME_DIR}/conf'"
  run "chmod 750               '${HOME_DIR}/conf'"   # Service can read; not write

  for dir in data logs tmp; do
    run "chown ${APP_NAME}:${APP_NAME} '${HOME_DIR}/${dir}'"
    run "chmod 750 '${HOME_DIR}/${dir}'"
  done

  success "Directory structure created."
fi

# --------------------------------------------------------------------------- #
#  4. Deploy SSH key (if provided — e.g., for deploy accounts)
# --------------------------------------------------------------------------- #
if [[ -n "$SSH_KEY" ]]; then
  SSH_DIR="${HOME_DIR}/.ssh"
  AUTH_KEYS="${SSH_DIR}/authorized_keys"

  info "Deploying SSH public key to ${AUTH_KEYS}"
  run "mkdir -p '${SSH_DIR}'"
  run "echo '${SSH_KEY}' >> '${AUTH_KEYS}'"
  run "chown -R ${APP_NAME}:${APP_NAME} '${SSH_DIR}'"
  run "chmod 700 '${SSH_DIR}'"
  run "chmod 600 '${AUTH_KEYS}'"
  success "SSH key deployed."
fi

# --------------------------------------------------------------------------- #
#  5. Lock password (key/service-only auth)
# --------------------------------------------------------------------------- #
info "Locking password for ${APP_NAME} (no password login)"
run "passwd --lock '${APP_NAME}'"
success "Password locked."

# --------------------------------------------------------------------------- #
#  6. Print systemd unit template
# --------------------------------------------------------------------------- #
echo ""
echo -e "${BOLD}--- Suggested systemd unit: /etc/systemd/system/${APP_NAME}.service ---${RESET}"
cat <<UNIT
[Unit]
Description=${APP_NAME} service
After=network.target

[Service]
Type=simple
User=${APP_NAME}
Group=${APP_NAME}
WorkingDirectory=${HOME_DIR}

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=${HOME_DIR}/data ${HOME_DIR}/logs ${HOME_DIR}/tmp
PrivateTmp=yes
CapabilityBoundingSet=

ExecStart=${HOME_DIR}/bin/${APP_NAME} --config ${HOME_DIR}/conf/config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# --------------------------------------------------------------------------- #
#  7. Summary
# --------------------------------------------------------------------------- #
echo ""
echo -e "${BOLD}=================================================${RESET}"
echo -e "${GREEN}  Account setup complete for: ${APP_NAME}${RESET}"
echo -e "${BOLD}=================================================${RESET}"
if ! $DRY_RUN; then
  echo ""
  id "$APP_NAME"
  echo ""
  echo "  Home    : ${HOME_DIR}"
  echo "  Shell   : ${SHELL_PATH}"
  echo "  Groups  : $(id -Gn ${APP_NAME})"
fi
echo ""

# =============================================================================
# IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE
# Author : Eknatha
# Repo   : linux-for-devops/06-user-management
# =============================================================================
