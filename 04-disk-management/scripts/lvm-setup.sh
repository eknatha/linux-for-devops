#!/bin/bash
# =============================================================================
# lvm-setup.sh
# Step-by-step LVM setup walkthrough for a new data disk.
# Creates PV → VG → LVs → formats → mounts → fstab.
#
# Usage (interactive walkthrough):
#   sudo ./lvm-setup.sh --disk /dev/sdb --vg vg_data
#
# Usage (automated):
#   sudo ./lvm-setup.sh --disk /dev/sdb --vg vg_data \
#       --lv-app 50G --lv-logs 20G --lv-db 100G --auto
#
# Options:
#   --disk DEVICE        Disk to use (e.g., /dev/sdb) required
#   --vg NAME            Volume group name (default: vg_data)
#   --lv-app SIZE        Size for app logical volume (e.g., 50G)
#   --lv-db SIZE         Size for DB logical volume
#   --lv-logs SIZE       Size for logs logical volume
#   --fstype TYPE        Filesystem: xfs (default) or ext4
#   --auto               Non-interactive (no prompts)
#   --dry-run            Show commands without running
#
# Author : Eknatha
# Repo   : linux-for-devops/04-disk-management
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
die()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()    { echo ""; echo -e "${BOLD}▶ $*${RESET}"; }
run()     { $DRY_RUN && echo -e "  ${YELLOW}[DRY-RUN]${RESET} $*" || eval "$@"; }

# Defaults
DISK=""
VG_NAME="vg_data"
LV_APP=""
LV_DB=""
LV_LOGS=""
FSTYPE="xfs"
AUTO=false
DRY_RUN=false
HOSTNAME_VAL=$(hostname -f 2>/dev/null || hostname)

# Parse args
usage() { sed -n '3,21p' "$0" | sed 's/^# \?//'; exit 0; }
[[ $# -eq 0 ]] && usage

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk)    DISK="$2";    shift 2 ;;
    --vg)      VG_NAME="$2"; shift 2 ;;
    --lv-app)  LV_APP="$2";  shift 2 ;;
    --lv-db)   LV_DB="$2";   shift 2 ;;
    --lv-logs) LV_LOGS="$2"; shift 2 ;;
    --fstype)  FSTYPE="$2";  shift 2 ;;
    --auto)    AUTO=true;    shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -z "$DISK" ]] && die "--disk is required"
[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"

# ── Banner ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}   LVM Setup Walkthrough — linux-for-devops         ${RESET}"
echo -e "${BOLD}   Author: Eknatha                                   ${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
printf "  %-20s %s\n" "Disk:"      "$DISK"
printf "  %-20s %s\n" "VG name:"   "$VG_NAME"
printf "  %-20s %s\n" "Filesystem:" "$FSTYPE"
$DRY_RUN && warn "DRY-RUN mode"
echo ""

# ── Step 1: Verify disk ──────────────────────────────────────────────────────
step "Step 1: Verify disk"

[[ -b "$DISK" ]] || die "Block device not found: $DISK"
DISK_SIZE=$(lsblk -bdn -o SIZE "$DISK" | awk '{printf "%.0fGB", $1/1024/1024/1024}')
info "Disk: $DISK — Size: $DISK_SIZE"

# Safety check: ensure disk has no existing data
EXISTING_FS=$(lsblk -f "$DISK" 2>/dev/null | grep -v NAME | awk '{print $2}' | grep -v '^$' || true)
if [[ -n "$EXISTING_FS" ]]; then
  warn "Disk $DISK appears to have existing filesystems: $EXISTING_FS"
  if ! $AUTO; then
    read -rp "  Continue? This will DESTROY existing data! [yes/no]: " CONFIRM
    [[ "$CONFIRM" == "yes" ]] || { info "Aborted."; exit 0; }
  fi
fi

# ── Step 2: Create Physical Volume ──────────────────────────────────────────
step "Step 2: Create Physical Volume (pvcreate)"

run "pvcreate '$DISK'"
success "PV created: $DISK"
$DRY_RUN || pvdisplay "$DISK" | grep -E 'PV Name|PV Size'

# ── Step 3: Create Volume Group ─────────────────────────────────────────────
step "Step 3: Create Volume Group (vgcreate)"

run "vgcreate '$VG_NAME' '$DISK'"
success "VG created: $VG_NAME"
$DRY_RUN || vgdisplay "$VG_NAME" | grep -E 'VG Name|VG Size|Free'

# ── Step 4: Create Logical Volumes ──────────────────────────────────────────
step "Step 4: Create Logical Volumes (lvcreate)"

declare -A LV_MAP
[[ -n "$LV_APP"  ]] && LV_MAP["lv_app"]="$LV_APP"
[[ -n "$LV_DB"   ]] && LV_MAP["lv_db"]="$LV_DB"
[[ -n "$LV_LOGS" ]] && LV_MAP["lv_logs"]="$LV_LOGS"

if [[ ${#LV_MAP[@]} -eq 0 ]]; then
  # Default: single data volume using all space
  warn "No LV sizes specified — creating single lv_data using 100% of VG"
  run "lvcreate -l 100%FREE -n lv_data '$VG_NAME'"
  LV_MAP["lv_data"]="100%"
else
  for lv_name in "${!LV_MAP[@]}"; do
    size="${LV_MAP[$lv_name]}"
    run "lvcreate -L '$size' -n '$lv_name' '$VG_NAME'"
    success "LV created: /dev/${VG_NAME}/${lv_name} (${size})"
  done
fi

echo ""
$DRY_RUN || lvs "$VG_NAME"

# ── Step 5: Format filesystems ───────────────────────────────────────────────
step "Step 5: Format filesystems (mkfs.${FSTYPE})"

for lv_name in "${!LV_MAP[@]}"; do
  LV_DEV="/dev/${VG_NAME}/${lv_name}"
  info "Formatting ${LV_DEV} as ${FSTYPE}..."
  if [[ "$FSTYPE" == "xfs" ]]; then
    run "mkfs.xfs -L '${lv_name}' '${LV_DEV}'"
  else
    run "mkfs.ext4 -L '${lv_name}' -m 1 '${LV_DEV}'"
  fi
  success "Formatted: ${LV_DEV} → ${FSTYPE}"
done

# ── Step 6: Create mount points and mount ────────────────────────────────────
step "Step 6: Mount logical volumes"

MOUNT_MAP=(
  ["lv_data"]="/data"
  ["lv_app"]="/opt/app"
  ["lv_db"]="/var/lib/database"
  ["lv_logs"]="/var/log/app"
)

for lv_name in "${!LV_MAP[@]}"; do
  LV_DEV="/dev/${VG_NAME}/${lv_name}"
  MOUNT="${MOUNT_MAP[$lv_name]:-/mnt/${lv_name}}"
  run "mkdir -p '${MOUNT}'"
  run "mount '${LV_DEV}' '${MOUNT}'"
  success "Mounted: ${LV_DEV} → ${MOUNT}"
done

# ── Step 7: Add to /etc/fstab ────────────────────────────────────────────────
step "Step 7: Add to /etc/fstab"

for lv_name in "${!LV_MAP[@]}"; do
  LV_DEV="/dev/${VG_NAME}/${lv_name}"
  MOUNT="${MOUNT_MAP[$lv_name]:-/mnt/${lv_name}}"
  FSTAB_LINE="/dev/mapper/${VG_NAME//-/--}-${lv_name}  ${MOUNT}  ${FSTYPE}  defaults,noatime  0  2"

  if $DRY_RUN; then
    echo -e "  ${YELLOW}[DRY-RUN]${RESET} Would add to /etc/fstab: $FSTAB_LINE"
  else
    if ! grep -q "${VG_NAME}-${lv_name}" /etc/fstab; then
      echo "$FSTAB_LINE" >> /etc/fstab
      success "Added to fstab: $FSTAB_LINE"
    else
      info "Already in fstab: ${VG_NAME}-${lv_name}"
    fi
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  ✔ LVM setup complete.${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
$DRY_RUN || { pvs; echo ""; vgs; echo ""; lvs; echo ""; df -hT | grep -v tmpfs; }
echo ""
info "To extend a volume later:"
info "  sudo lvextend -L +20G /dev/${VG_NAME}/lv_app"
info "  sudo xfs_growfs /opt/app   (XFS)"
info "  sudo resize2fs /dev/${VG_NAME}/lv_app  (ext4)"

# =============================================================================
# IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE
# Author : Eknatha
# Repo   : linux-for-devops/04-disk-management
# =============================================================================
