# Linux Disk Management — Production Reference Guide

> Comprehensive reference for block devices, partitioning, filesystems, LVM, software RAID, mounts, disk health, I/O performance, encryption, and storage troubleshooting on production Linux servers.

---


![Eknatha](https://img.shields.io/badge/Eknatha-4EAA25?style=flat&logo=gnu-bash&logoColor=white)


## Table of Contents

1. [Block Devices and Disk Layout]
2. [Partitioning — fdisk and parted]
3. [Filesystems — Format, Mount, and Repair]
4. [/etc/fstab and Persistent Mounts]
5. [LVM — Logical Volume Management]
6. [Software RAID with mdadm]
7. [Disk Health and SMART Monitoring]
8. [I/O Performance Monitoring and Tuning]
9. [Space Management and Cleanup]
10. [Disk Encryption with LUKS]
11. [Backup Strategies — LVM, rsync, dd]
12. [Production Disk Runbook]

---

## 1. Block Devices and Disk Layout

### Viewing Storage Layout

```bash
# Block device tree — best overview command
lsblk
lsblk -f         # Include filesystem type and UUID
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID

# Example output:
# NAME        SIZE TYPE FSTYPE   MOUNTPOINT
# sda         500G disk
# ├─sda1        1G part vfat     /boot/efi
# ├─sda2        2G part ext4     /boot
# └─sda3      497G part LVM2_member
#   ├─vg0-root  50G lvm  ext4    /
#   ├─vg0-var   80G lvm  xfs     /var
#   └─vg0-data 367G lvm  xfs     /data

# Disk and partition tables
sudo fdisk -l              # All disks and partitions
sudo fdisk -l /dev/sdb     # Specific disk
sudo parted -l             # All disks — better for GPT

# Disk identification
ls -la /dev/disk/by-id/         # By device serial/model
ls -la /dev/disk/by-uuid/       # By filesystem UUID
ls -la /dev/disk/by-path/       # By hardware path
ls -la /dev/disk/by-label/      # By filesystem label

# Physical disk info
sudo hdparm -I /dev/sda | grep -E 'Model|Serial|Capacity|RPM'
sudo lshw -class disk
cat /sys/block/sda/size         # Sectors (multiply by 512 for bytes)
cat /proc/partitions            # All registered partitions

# NVMe devices
nvme list
nvme smart-log /dev/nvme0
```

### Understanding Device Naming

```
/dev/sda         → First SCSI/SATA disk
/dev/sdb         → Second SCSI/SATA disk
/dev/sda1        → First partition of sda
/dev/sda2        → Second partition of sda
/dev/nvme0n1     → First NVMe disk
/dev/nvme0n1p1   → First partition of first NVMe disk
/dev/vda         → First virtio disk (KVM/QEMU VMs)
/dev/xvda        → First Xen virtual disk (AWS)
/dev/md0         → Software RAID device
/dev/dm-0        → Device mapper (LVM logical volume)
/dev/mapper/vg0-lv_data  → LVM logical volume (friendly name)
```

---

## 2. Partitioning — fdisk and parted

### fdisk — MBR and GPT Partitioning

```bash
# Interactive partitioning
sudo fdisk /dev/sdb

# fdisk commands:
# p → print partition table
# n → new partition
# d → delete partition
# t → change partition type
# l → list partition types
# g → create GPT table
# o → create MBR/DOS table
# w → write and exit
# q → quit without saving

# Non-interactive: create a single partition using entire disk
sudo fdisk /dev/sdb << 'EOF'
g       # GPT partition table
n       # New partition
1       # Partition number
        # First sector (default)
        # Last sector (default = entire disk)
w       # Write
EOF

# Verify
lsblk /dev/sdb
```

### parted — GPT Partitioning (Better for Large Disks)

```bash
# Interactive
sudo parted /dev/sdb

# Non-interactive examples
sudo parted /dev/sdb --script mklabel gpt

# Create boot partition (1MB BIOS boot + 512MB EFI)
sudo parted /dev/sdb --script \
  mkpart primary fat32 1MiB 513MiB \
  set 1 esp on

# Create main data partition
sudo parted /dev/sdb --script \
  mkpart primary ext4 513MiB 100%

# Split disk: 100GB for var, rest for data
sudo parted /dev/sdb --script \
  mklabel gpt \
  mkpart primary 1MiB 100GiB \
  mkpart primary 100GiB 100%

# Align check (important for performance)
sudo parted /dev/sdb align-check optimal 1
# Result: 1 aligned

# View
sudo parted /dev/sdb print

# Tell kernel about new partition table without reboot
sudo partprobe /dev/sdb
```

---

## 3. Filesystems — Format, Mount, and Repair

### Formatting Filesystems

```bash
# ext4 — most common, stable, mature
sudo mkfs.ext4 -L data /dev/sdb1
sudo mkfs.ext4 -L data -m 1 /dev/sdb1     # 1% reserved (default 5% — save space on data disks)
sudo mkfs.ext4 -T largefile4 /dev/sdb1    # Optimise for large files

# XFS — high-performance, scales to very large filesystems, preferred for data
sudo mkfs.xfs -L data /dev/sdb1
sudo mkfs.xfs -f /dev/sdb1                # Force (overwrite existing)
sudo mkfs.xfs -d su=256k,sw=4 /dev/sdb1  # RAID stripe optimisation

# Btrfs — copy-on-write, snapshots, compression (good for backup storage)
sudo mkfs.btrfs -L data /dev/sdb1
sudo mkfs.btrfs -d raid1 -m raid1 /dev/sdb1 /dev/sdc1   # Btrfs RAID-1

# tmpfs (RAM-based filesystem — for volatile temp data)
sudo mount -t tmpfs -o size=2G tmpfs /tmp/ramdisk

# FAT32 (for EFI partitions)
sudo mkfs.vfat -F 32 /dev/sdb1
```

### Mounting Filesystems

```bash
# Basic mount
sudo mount /dev/sdb1 /mnt/data

# Mount with specific options
sudo mount -o noatime,nodiratime /dev/sdb1 /mnt/data    # Reduce write ops
sudo mount -o ro /dev/sdb1 /mnt/data                    # Read-only
sudo mount -o remount,rw /mnt/data                      # Remount read-write

# Mount by UUID (safer than device name — names can change)
sudo mount -U "$(blkid /dev/sdb1 -s UUID -o value)" /mnt/data

# Bind mount — map a directory to another location
sudo mount --bind /opt/data /mnt/data

# Temporary mount (RAM-based, fast I/O)
sudo mount -t tmpfs -o size=512M tmpfs /tmp/build

# Show all mounts
mount | column -t
findmnt                    # Tree view of all mounts
findmnt /mnt/data          # Info about a specific mountpoint
cat /proc/mounts           # Kernel-reported mount table

# Unmount
sudo umount /mnt/data
sudo umount -l /mnt/data   # Lazy unmount (detach when not in use)
sudo umount -f /mnt/nfs    # Force unmount (for hung NFS)
```

### Filesystem Check and Repair

```bash
# IMPORTANT: Always unmount before running fsck

# ext4 check
sudo umount /dev/sdb1
sudo e2fsck -f /dev/sdb1         # Force check even if clean
sudo e2fsck -p /dev/sdb1         # Auto-fix safe errors
sudo e2fsck -y /dev/sdb1         # Auto-answer yes to all (be careful!)
sudo fsck -n /dev/sdb1           # Read-only check — safe to run

# XFS check and repair
sudo umount /dev/sdb1
sudo xfs_check /dev/sdb1         # Check (deprecated, use xfs_repair -n)
sudo xfs_repair -n /dev/sdb1     # Dry run — no changes
sudo xfs_repair /dev/sdb1        # Repair

# Schedule ext4 check on next boot
sudo tune2fs -C 30 /dev/sdb1     # Force fsck after 30 mounts
sudo touch /forcefsck             # Trigger fsck on next boot (Ubuntu)

# Get filesystem info
sudo tune2fs -l /dev/sdb1         # ext4 superblock info
sudo xfs_info /mnt/data           # XFS info (while mounted)
sudo dumpe2fs /dev/sdb1 | head -30   # Detailed ext4 info

# Resize ext4 (after extending the block device)
sudo resize2fs /dev/mapper/vg-lv_data    # Grow to fill device
sudo resize2fs /dev/sdb1 50G            # Resize to specific size

# Grow XFS (online — while mounted)
sudo xfs_growfs /mnt/data
```

---

## 4. /etc/fstab and Persistent Mounts

### /etc/fstab Format

```
# <device>          <mountpoint>  <type>   <options>           <dump> <pass>
UUID=abc123...      /             ext4     defaults            0      1
UUID=def456...      /boot         ext4     defaults            0      2
UUID=ghi789...      /data         xfs      defaults,noatime    0      2
/dev/mapper/vg-data /opt/app      xfs      defaults,noatime    0      2
```

```
Fields:
  device:     UUID=..., /dev/..., LABEL=..., or //server/share for NFS/CIFS
  mountpoint: where to mount
  type:       ext4, xfs, btrfs, nfs, cifs, tmpfs, none (for bind mounts)
  options:    comma-separated mount options
  dump:       0=ignore, 1=include in dump backup (rarely used)
  pass:       0=no fsck, 1=fsck first (root only), 2=fsck after root
```

### Production /etc/fstab

```bash
# /etc/fstab — Production configuration

# Root filesystem
UUID="a1b2c3d4-..."   /           ext4    defaults,errors=remount-ro   0  1

# Boot partition
UUID="e5f6a7b8-..."   /boot       ext4    defaults                     0  2

# Application data — XFS, noatime for performance
UUID="c9d0e1f2-..."   /opt/app    xfs     defaults,noatime             0  2

# Database storage — noatime, barrier=0 for SSD-backed storage
UUID="g3h4i5j6-..."   /var/lib/postgresql  xfs  defaults,noatime       0  2

# Log volume
UUID="k7l8m9n0-..."   /var/log    ext4    defaults,noatime             0  2

# Shared NFS mount — nofail prevents boot failure if NFS is unavailable
10.0.1.20:/shared     /mnt/shared nfs     defaults,nofail,_netdev,\
                                          timeo=30,retrans=3            0  0

# tmpfs for build cache (RAM-based)
tmpfs                 /tmp/build  tmpfs   defaults,size=2G,mode=1777   0  0

# Bind mount — map legacy path to new location
/opt/app/data         /data       none    bind                         0  0
```

```bash
# Test fstab without rebooting
sudo mount -a        # Mount everything in fstab not already mounted
sudo mount -fav      # Dry run — show what would be mounted

# Verify a specific entry
sudo mount -v UUID="abc123..." /mnt/test

# Reload systemd's view of fstab changes
sudo systemctl daemon-reload
```

### Mount Options Reference

| Option | Effect | Use Case |
|---|---|---|
| `defaults` | rw, suid, dev, exec, auto, nouser, async | General purpose |
| `noatime` | Don't update access timestamps on reads | Data/log disks — reduces writes |
| `nodiratime` | Don't update directory access timestamps | Combined with noatime |
| `relatime` | Update atime only if newer than mtime | Compromise between atime/noatime |
| `ro` | Read-only | Backup sources, immutable data |
| `noexec` | Prevent executing binaries | /tmp, /var for security |
| `nosuid` | Ignore setuid bits | /tmp, user-mounted filesystems |
| `nodev` | Ignore device files | /tmp, user filesystems |
| `nofail` | Don't error if device missing | Non-critical mounts (NFS, USB) |
| `_netdev` | Wait for network before mounting | NFS, iSCSI |
| `user` | Allow non-root mounting | Removable media |
| `errors=remount-ro` | Remount read-only on error | Root filesystem safety |
| `barrier=0` | Disable write barriers (SSD) | SSD with battery-backed controller |
| `commit=60` | Flush journal every 60s (ext4) | Reduce write pressure |

---

## 5. LVM — Logical Volume Management

### LVM Architecture

```
Physical Disks/Partitions → Physical Volumes (PV)
                          → Volume Groups (VG)
                          → Logical Volumes (LV)
                          → Filesystems
```

### Physical Volume Management

```bash
# Create PVs
sudo pvcreate /dev/sdb
sudo pvcreate /dev/sdb /dev/sdc /dev/sdd    # Multiple at once

# List PVs
pvs                          # Summary
pvdisplay                    # Detailed
pvdisplay /dev/sdb           # Specific PV

# Remove PV (must be removed from VG first)
sudo pvmove /dev/sdb         # Move data off this PV
sudo vgreduce vg_data /dev/sdb
sudo pvremove /dev/sdb
```

### Volume Group Management

```bash
# Create VG
sudo vgcreate vg_data /dev/sdb
sudo vgcreate vg_data /dev/sdb /dev/sdc     # VG spanning multiple disks

# Extend VG (add disk to VG)
sudo vgextend vg_data /dev/sdd

# List VGs
vgs                          # Summary
vgdisplay                    # Detailed
vgdisplay vg_data

# Rename VG
sudo vgrename vg_data vg_production

# Activate VG (after import on a new system)
sudo vgchange -ay vg_data

# Export/import VG (move to another system)
sudo vgexport vg_data
sudo vgimport vg_data

# Remove VG (all LVs must be removed first)
sudo vgremove vg_data
```

### Logical Volume Management

```bash
# Create LVs
sudo lvcreate -L 50G -n lv_app vg_data          # Fixed size
sudo lvcreate -l 100%FREE -n lv_data vg_data     # Use all remaining space
sudo lvcreate -l 80%VG -n lv_db vg_data          # 80% of VG
sudo lvcreate -l 50%FREE -n lv_log vg_data       # 50% of free space

# List LVs
lvs                          # Summary
lvdisplay                    # Detailed
lvdisplay /dev/vg_data/lv_app

# Format and mount
sudo mkfs.xfs /dev/vg_data/lv_app
sudo mkdir -p /opt/app
sudo mount /dev/vg_data/lv_app /opt/app

# Add to fstab
echo "/dev/mapper/vg_data-lv_app  /opt/app  xfs  defaults,noatime  0  2" \
  | sudo tee -a /etc/fstab
```

### Extending Logical Volumes (Online — No Downtime)

```bash
# Extend LV and filesystem in one step (ext4)
sudo lvextend -L +20G -r /dev/vg_data/lv_app    # -r = resize filesystem too

# Manual two-step extension
sudo lvextend -L +20G /dev/vg_data/lv_app        # Extend LV only
sudo resize2fs /dev/vg_data/lv_app               # Resize ext4

# For XFS (resize while mounted — XFS only grows, never shrinks)
sudo lvextend -L +20G /dev/vg_data/lv_data
sudo xfs_growfs /opt/data                         # Resize XFS online

# Extend to fill all free space in VG
sudo lvextend -l +100%FREE /dev/vg_data/lv_data -r

# Extend to specific size
sudo lvextend -L 200G /dev/vg_data/lv_data -r
```

### LVM Snapshots — Point-in-Time Copy

```bash
# Create snapshot (for backup — captures state at this moment)
sudo lvcreate \
  --snapshot \
  --name lv_app_snap_$(date +%Y%m%d_%H%M) \
  --size 5G \
  /dev/vg_data/lv_app

# List snapshots
lvs -a | grep snap

# Mount snapshot (read-only to preserve integrity)
sudo mkdir -p /mnt/snapshot
sudo mount -o ro /dev/vg_data/lv_app_snap_20240115_1400 /mnt/snapshot

# Backup from snapshot
sudo tar -czf /backup/app-$(date +%F).tar.gz -C /mnt/snapshot .
sudo rsync -av /mnt/snapshot/ /backup/app-$(date +%F)/

# Unmount and remove snapshot when done
sudo umount /mnt/snapshot
sudo lvremove /dev/vg_data/lv_app_snap_20240115_1400

# Restore from snapshot (dangerous — destroys all changes since snapshot)
sudo umount /opt/app
sudo lvconvert --merge /dev/vg_data/lv_app_snap_20240115_1400
# Reboot or re-activate LV for merge to complete
```

### Thin Provisioning

```bash
# Create thin pool (allocates space only when written)
sudo lvcreate -l 100%FREE --thinpool vg_data/thinpool vg_data

# Create thin volumes from pool
sudo lvcreate -V 100G --thin -n lv_app vg_data/thinpool
sudo lvcreate -V 200G --thin -n lv_db vg_data/thinpool

# Snapshot a thin volume (space-efficient)
sudo lvcreate --snapshot --name lv_app_snap vg_data/lv_app

# Monitor pool usage
lvs -a vg_data
```

---

## 6. Software RAID with mdadm

### RAID Levels for Production

| RAID | Disks | Redundancy | Performance | Use Case |
|---|---|---|---|---|
| RAID-0 | ≥2 | None | Best | Temp/cache — no production data |
| RAID-1 | 2 | 1 disk failure | Read+write | OS drives, small critical data |
| RAID-5 | ≥3 | 1 disk failure | Good | General data storage |
| RAID-6 | ≥4 | 2 disk failures | Good | High-value data |
| RAID-10 | ≥4 | Per-mirror | Best | Databases, high IOPS |

### Creating RAID Arrays

```bash
# RAID-1 (mirror) — two identical copies
sudo mdadm --create /dev/md0 \
  --level=1 \
  --raid-devices=2 \
  /dev/sdb /dev/sdc

# RAID-5 — striped with parity
sudo mdadm --create /dev/md0 \
  --level=5 \
  --raid-devices=3 \
  /dev/sdb /dev/sdc /dev/sdd

# RAID-10 — striped mirror
sudo mdadm --create /dev/md0 \
  --level=10 \
  --raid-devices=4 \
  /dev/sdb /dev/sdc /dev/sdd /dev/sde

# RAID-6 with hot spare
sudo mdadm --create /dev/md0 \
  --level=6 \
  --raid-devices=4 \
  --spare-devices=1 \
  /dev/sdb /dev/sdc /dev/sdd /dev/sde \
  --spare /dev/sdf

# Monitor sync progress
watch cat /proc/mdstat
cat /proc/mdstat
```

### Save RAID Configuration

```bash
# Write mdadm.conf (required for array to assemble on boot)
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u   # Debian/Ubuntu
sudo dracut -f             # RHEL/CentOS
```

### Monitoring RAID Health

```bash
# Overall status
cat /proc/mdstat
sudo mdadm --detail /dev/md0

# Monitor for events
sudo mdadm --monitor --scan --daemonise --mail=ops@company.com

# Check array state
sudo mdadm --detail /dev/md0 | grep -E 'State|Active|Degraded|Failed'

# List all RAID arrays
sudo mdadm --examine --scan
```

### RAID Disk Failure and Replacement

```bash
# Step 1: Check what failed
sudo mdadm --detail /dev/md0
# Look for: State = degraded, Faulty drives

# Step 2: Mark the failed drive as faulty (if not already)
sudo mdadm /dev/md0 --fail /dev/sdb

# Step 3: Remove failed drive from array
sudo mdadm /dev/md0 --remove /dev/sdb

# Step 4: Physically replace the disk, then add new disk
sudo mdadm /dev/md0 --add /dev/sdb    # New disk at same path

# Step 5: Watch rebuild
watch -n5 cat /proc/mdstat
# sdb is now syncing — takes minutes to hours depending on size

# Step 6: Verify rebuild complete
sudo mdadm --detail /dev/md0 | grep State
# Should show: State = clean
```

---

## 7. Disk Health and SMART Monitoring

### smartmontools

```bash
# Install
sudo apt install smartmontools    # Debian/Ubuntu
sudo yum install smartmontools    # RHEL/CentOS

# Quick health check
sudo smartctl -H /dev/sda
# SMART overall-health self-assessment test result: PASSED

# Full SMART data (attributes, error log, self-test log)
sudo smartctl -a /dev/sda

# Key attributes to monitor:
# 5   → Reallocated_Sector_Ct  (non-zero = bad sectors — replace soon)
# 10  → Spin_Retry_Count        (non-zero = mechanical issue)
# 184 → End-to-End_Error        (non-zero = controller/memory issue)
# 187 → Reported_Uncorrect      (non-zero = unrecoverable errors — URGENT)
# 188 → Command_Timeout         (increasing = firmware/cable issue)
# 196 → Reallocated_Event_Count (increasing = disk degrading)
# 197 → Current_Pending_Sector  (unstable sectors — replace disk!)
# 198 → Offline_Uncorrectable   (non-zero = data corruption risk)
# 199 → UDMA_CRC_Error_Count    (increasing = cable/connection issue)

# Run SMART self-test
sudo smartctl -t short /dev/sda    # Short test (2 minutes)
sudo smartctl -t long /dev/sda     # Long test (hours — run offline)

# Check test results
sudo smartctl -l selftest /dev/sda

# NVMe SMART
sudo nvme smart-log /dev/nvme0
sudo smartctl -a /dev/nvme0

# Monitor continuously via smartd daemon
sudo systemctl enable --now smartd
# Configure: /etc/smartd.conf
```

### /etc/smartd.conf

```bash
# /etc/smartd.conf — Monitor all drives, alert on issues
DEVICESCAN \
  -a \
  -o on \
  -S on \
  -n standby,q \
  -s (S/../.././02|L/../../6/03) \
  -W 4,45,50 \
  -m ops@company.com \
  -M exec /usr/share/smartmontools/smartd-runner

# Explanation:
# -a        → Check all SMART attributes
# -o on     → Enable automatic offline testing
# -S on     → Enable automatic attribute saving
# -n standby,q → Don't spin up sleeping drives
# -s ...    → Schedule: short test daily at 2am, long test Saturdays at 3am
# -W 4,45,50 → Temperature warning at 45°C, critical at 50°C
# -m        → Email address for alerts
```

### Checking for I/O Errors in Kernel Log

```bash
# Recent disk errors
sudo dmesg -T | grep -iE 'error|fail|bad block|i/o error|disk' | tail -20

# Watch for new errors in real-time
sudo dmesg -w | grep -iE 'error|fail|i/o'

# Check system journal for disk errors
journalctl -k | grep -iE 'error|fail|i/o error|ata|scsi|nvme'

# Historical disk errors from syslog
grep -iE 'i/o error|bad sector|ata.*error|scsi.*error' /var/log/syslog | tail -20
grep -iE 'i/o error|bad sector' /var/log/kern.log | tail -20

# badblocks — surface scan (WARNING: write mode is destructive)
sudo badblocks -v /dev/sdb        # Read-only scan (safe)
sudo badblocks -sv /dev/sdb       # Read-only, show progress
# NEVER run write mode (-w) on a disk with data!
```

---

## 8. I/O Performance Monitoring and Tuning

### iostat — I/O Statistics

```bash
# Install: sudo apt install sysstat

# Continuous I/O stats every 1 second
iostat -xz 1

# Key columns:
# Device   → disk or partition
# r/s      → reads per second
# w/s      → writes per second
# rkB/s    → read throughput (KB/s)
# wkB/s    → write throughput (KB/s)
# await    → average I/O wait time (ms)
#            HDDs: alert > 20ms, SSDs: alert > 5ms
# r_await  → read average wait time
# w_await  → write average wait time
# svctm    → service time (deprecated — ignore)
# %util    → device utilisation — alert if > 80% sustained

# Extended stats for a specific device
iostat -x 1 -d /dev/sda

# Historical I/O via sar
sar -d 1 10                       # I/O per device, 10 samples
sar -d -f /var/log/sysstat/sa15   # Historical data for day 15
```

### iotop — I/O by Process

```bash
sudo iotop -o            # Only show processes doing I/O
sudo iotop -a            # Accumulated totals
sudo iotop -b -n 5       # Batch mode, 5 iterations (for scripts)
sudo iotop -p $(pgrep postgres)  # Specific process
```

### I/O Scheduler Tuning

```bash
# View current scheduler
cat /sys/block/sda/queue/scheduler
# [mq-deadline] kyber bfq none

# Available schedulers and when to use:
# none/noop   → SSDs/NVMe (no reordering needed)
# mq-deadline → General purpose SSDs and HDDs (good default)
# bfq         → Desktop/workstation (I/O fairness between processes)
# kyber       → High-performance NVMe (low latency)

# Set scheduler temporarily
echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler
echo none | sudo tee /sys/block/nvme0n1/queue/scheduler

# Set permanently via udev rule
cat << 'EOF' | sudo tee /etc/udev/rules.d/60-scheduler.rules
# SSD: use none (NVMe) or mq-deadline (SATA SSD)
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
# HDD: use mq-deadline
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
EOF

sudo udevadm trigger --subsystem-match=block --action=add
```

### Kernel I/O Tuning via sysctl

```bash
# /etc/sysctl.d/99-disk-tuning.conf

# Reduce dirty page writeback (reduce I/O spikes)
vm.dirty_ratio = 10          # Start writeback when 10% of RAM is dirty
vm.dirty_background_ratio = 5   # Start background writeback at 5%
vm.dirty_expire_centisecs = 3000  # Dirty data expires after 30s
vm.dirty_writeback_centisecs = 500  # Check dirty data every 5s

# Swap behaviour (0=avoid swap, 60=default, 100=aggressive)
vm.swappiness = 10

# Read-ahead setting for HDDs (in 512-byte sectors)
# 256 sectors = 128KB readahead
blockdev --setra 256 /dev/sdb

# Permanent readahead via udev
echo 'ACTION=="add|change", KERNEL=="sdb", RUN+="/sbin/blockdev --setra 256 /dev/sdb"' \
  | sudo tee /etc/udev/rules.d/99-readahead.rules
```

### fio — Comprehensive Benchmark

```bash
# Install: sudo apt install fio

# Sequential read test
fio --name=seqread \
  --rw=read \
  --bs=1M \
  --size=10G \
  --numjobs=1 \
  --time_based \
  --runtime=30 \
  --filename=/mnt/data/fio-test \
  --output-format=normal

# Random read IOPS test (database workload)
fio --name=randread \
  --rw=randread \
  --bs=4k \
  --size=10G \
  --numjobs=4 \
  --time_based \
  --runtime=60 \
  --filename=/mnt/data/fio-test \
  --iodepth=16 \
  --direct=1

# Sequential write throughput
fio --name=seqwrite \
  --rw=write \
  --bs=1M \
  --size=10G \
  --numjobs=1 \
  --runtime=30 \
  --filename=/mnt/data/fio-test

# Mixed read/write (70% read, 30% write)
fio --name=mixed \
  --rw=randrw \
  --rwmixread=70 \
  --bs=4k \
  --size=10G \
  --numjobs=4 \
  --runtime=60 \
  --iodepth=32 \
  --direct=1 \
  --filename=/mnt/data/fio-test

# Quick latency test
fio --name=latency \
  --rw=randread \
  --bs=4k \
  --size=1G \
  --numjobs=1 \
  --iodepth=1 \
  --direct=1 \
  --filename=/mnt/data/fio-test \
  --lat_percentiles=1 \
  --percentile_list=50:90:95:99:99.9
```

---

## 9. Space Management and Cleanup

### Finding Large Files and Directories

```bash
# Top 20 largest files
sudo find / -size +100M -type f \
  -not \( -path '/proc/*' -o -path '/sys/*' -o -path '/dev/*' \) \
  2>/dev/null | xargs ls -lh | sort -k5 -rh | head -20

# Directory sizes — top consumers
du -sh /* 2>/dev/null | sort -rh | head -10
du -sh /var/* 2>/dev/null | sort -rh | head -10
du -sh /var/log/* 2>/dev/null | sort -rh | head -10

# Tree with depth limit
du -h --max-depth=2 / 2>/dev/null | sort -rh | head -30

# Find files not accessed in 30 days, larger than 50MB
sudo find /var/log -atime +30 -size +50M -type f -ls

# Find all log files
sudo find / -name "*.log" -type f -size +10M \
  -not -path '/proc/*' 2>/dev/null | xargs ls -lh | sort -k5 -rh
```

### Deleted Files Still Held Open

```bash
# The most common cause of "disk full but du shows space"
sudo lsof +L1 | grep deleted
sudo lsof +L1 | grep deleted | awk '{print $2, $7, $9}'  # PID, SIZE, FILE

# Safely free space without killing the process (truncate the file)
# Find the FD number from lsof output, then:
# lsof +L1 shows: COMMAND PID ... FD ... SIZE FILE(deleted)
PID=1234
FD=7    # File descriptor number from lsof output
> /proc/$PID/fd/$FD    # Truncate — this frees space immediately

# Alternatively, restart the process that holds the file
sudo systemctl restart myapp
```

### Package Cache and Temp Files

```bash
# Debian/Ubuntu package cache
sudo apt clean              # Remove all cached packages
sudo apt autoclean          # Remove only outdated cached packages
sudo apt autoremove         # Remove unneeded packages

# Remove old kernels (be careful — keep at least 2)
sudo apt autoremove --purge

# RHEL/CentOS package cache
sudo yum clean all
sudo dnf clean all

# Systemd journal (can grow very large)
journalctl --disk-usage
sudo journalctl --vacuum-time=14d    # Keep 14 days
sudo journalctl --vacuum-size=1G     # Keep max 1GB

# Find and remove core dumps
sudo find / -name "core" -o -name "core.[0-9]*" 2>/dev/null | head
sudo find /var/crash -name "*.crash" -mtime +7 -delete

# Docker cleanup (can accumulate GBs)
docker system df            # Show Docker disk usage
docker system prune -a --volumes --force   # Remove everything unused
docker image prune -a       # Remove unused images
docker volume prune         # Remove unused volumes
```

---

## 10. Disk Encryption with LUKS

### Creating Encrypted Volumes

```bash
# Install
sudo apt install cryptsetup

# Format a partition with LUKS encryption
sudo cryptsetup luksFormat /dev/sdb1
# WARNING: This will destroy all data! Type YES to confirm.

# Open (decrypt) the volume
sudo cryptsetup open /dev/sdb1 secret_data
# Device appears at /dev/mapper/secret_data

# Format and mount
sudo mkfs.xfs /dev/mapper/secret_data
sudo mkdir /mnt/encrypted
sudo mount /dev/mapper/secret_data /mnt/encrypted

# Close (re-encrypt / lock)
sudo umount /mnt/encrypted
sudo cryptsetup close secret_data
```

### Persistent LUKS Mount

```bash
# Get UUID of LUKS device
sudo blkid /dev/sdb1

# /etc/crypttab (maps LUKS devices to mapper names)
# Format: name  device                  keyfile  options
secret_data UUID=abc123...  none  luks,discard

# Use keyfile (for automated unlocking — production servers)
sudo dd if=/dev/urandom of=/etc/luks-keyfile bs=4096 count=1
sudo chmod 400 /etc/luks-keyfile
sudo cryptsetup luksAddKey /dev/sdb1 /etc/luks-keyfile

# /etc/crypttab with keyfile
secret_data  UUID=abc123...  /etc/luks-keyfile  luks,discard,nofail

# /etc/fstab entry
/dev/mapper/secret_data  /mnt/encrypted  xfs  defaults,nofail  0  2

# Test
sudo cryptdisks_start secret_data
sudo mount /mnt/encrypted
```

### LUKS Key Management

```bash
# List current key slots
sudo cryptsetup luksDump /dev/sdb1 | grep Key

# Add an additional key (passphrase or key file)
sudo cryptsetup luksAddKey /dev/sdb1

# Remove a key slot
sudo cryptsetup luksKillSlot /dev/sdb1 1   # Remove slot 1

# Backup LUKS header (critical — without this, data is unrecoverable!)
sudo cryptsetup luksHeaderBackup /dev/sdb1 \
  --header-backup-file /secure-backup/luks-header-sdb1.img
sudo chmod 400 /secure-backup/luks-header-sdb1.img

# Restore LUKS header
sudo cryptsetup luksHeaderRestore /dev/sdb1 \
  --header-backup-file /secure-backup/luks-header-sdb1.img
```

---

## 11. Backup Strategies — LVM, rsync, dd

### LVM Snapshot Backup (Recommended for Application Data)

```bash
#!/bin/bash
# Production LVM snapshot backup pattern

APP_LV="/dev/vg_data/lv_app"
SNAP_NAME="lv_app_snap_$(date +%Y%m%d_%H%M%S)"
SNAP_SIZE="5G"
BACKUP_DEST="/backup/app/$(date +%F)"

# Create snapshot
lvcreate --snapshot --name "$SNAP_NAME" --size "$SNAP_SIZE" "$APP_LV"

# Mount snapshot
mkdir -p /mnt/snap
mount -o ro,noatime "/dev/vg_data/${SNAP_NAME}" /mnt/snap

# Backup from snapshot (app is live and unaffected)
rsync -avz --delete /mnt/snap/ "${BACKUP_DEST}/"

# Cleanup
umount /mnt/snap
lvremove -f "/dev/vg_data/${SNAP_NAME}"
```

### rsync — Incremental File Backup

```bash
# Local incremental backup with hard-links (space-efficient)
rsync -avz --delete \
  --link-dest=/backup/daily/$(date -d 'yesterday' +%F) \
  /opt/app/ \
  /backup/daily/$(date +%F)/

# Remote backup
rsync -avz --delete -e "ssh -i /root/.ssh/backup_key" \
  /opt/app/ \
  backup@192.168.1.100:/backup/app/

# Exclude patterns
rsync -avz --delete \
  --exclude='*.log' \
  --exclude='tmp/' \
  --exclude='.git/' \
  /opt/app/ /backup/app/

# Dry run to see what would change
rsync -avzn --delete /opt/app/ /backup/app/

# Backup with checksum verification
rsync -avzc --delete /opt/app/ /backup/app/
```

### dd — Raw Disk Backup

```bash
# Backup entire disk to image
sudo dd if=/dev/sdb of=/backup/sdb-$(date +%F).img \
  bs=4M status=progress conv=sync,noerror

# Compressed backup
sudo dd if=/dev/sdb bs=4M status=progress | gzip -9 > /backup/sdb.img.gz

# Backup over SSH
sudo dd if=/dev/sdb bs=4M status=progress \
  | ssh backup@192.168.1.100 "cat > /backup/sdb.img"

# Restore from image
sudo dd if=/backup/sdb.img of=/dev/sdb bs=4M status=progress

# Backup partition only
sudo dd if=/dev/sdb1 of=/backup/sdb1.img bs=4M status=progress

# Wipe a disk securely (overwrite with zeros)
sudo dd if=/dev/zero of=/dev/sdb bs=4M status=progress
```

---

## 12. Production Disk Runbook

### Incident: Disk Full

```bash
# Step 1: Identify which filesystem is full
df -hT | grep -vE 'tmpfs|devtmpfs'
df -i | grep -vE 'tmpfs|devtmpfs'    # Check inodes too

# Step 2: Find what's consuming space
du -sh /var/* 2>/dev/null | sort -rh | head -10
du -sh /var/log/* 2>/dev/null | sort -rh | head -10

# Step 3: Find deleted files still held open
sudo lsof +L1 | grep deleted

# Step 4: Quick cleanup options
sudo journalctl --vacuum-size=500M
sudo apt clean
docker system prune -f 2>/dev/null
find /var/log -name "*.gz" -mtime +7 -delete
find /tmp -mtime +1 -type f -delete

# Step 5: If LVM — extend the volume online
sudo lvextend -L +20G /dev/vg_data/lv_var -r
```

### Incident: Slow Disk I/O

```bash
# Step 1: Identify the device with high utilisation
iostat -xz 1 5 | grep -v '^$'
# Look for %util > 80% or await > 20ms (HDD) / 5ms (SSD)

# Step 2: Find which processes are doing the I/O
sudo iotop -o -n 5

# Step 3: Check for filesystem errors
sudo dmesg -T | grep -iE 'error|fail|i/o' | tail -20

# Step 4: Check SMART for failing drive
sudo smartctl -H /dev/sda
sudo smartctl -a /dev/sda | grep -E 'Reallocated|Pending|Uncorrectable'

# Step 5: Check I/O scheduler
cat /sys/block/sda/queue/scheduler

# Step 6: Temporary mitigation — reduce I/O pressure
ionice -c 3 -p $(pgrep heavy-process)
renice +15 -p $(pgrep heavy-process)
```

### Incident: Filesystem Corruption

```bash
# Step 1: Check dmesg for filesystem errors
sudo dmesg -T | grep -iE 'filesystem|ext4|xfs|error' | tail -20

# Step 2: Remount read-only to prevent further damage
sudo mount -o remount,ro /mnt/data

# Step 3: Unmount filesystem
sudo fuser -vm /mnt/data    # Find processes using it
sudo umount /mnt/data

# Step 4: Run filesystem check
# ext4:
sudo e2fsck -f -y /dev/vg_data/lv_data
# XFS:
sudo xfs_repair /dev/vg_data/lv_data

# Step 5: If repair fails — restore from backup
sudo mount /dev/vg_data/lv_data /mnt/data    # Try to remount
# If unusable, restore from LVM snapshot or last backup

# Step 6: Monitor for recurrence
sudo tune2fs -l /dev/vg_data/lv_data | grep -i error
sudo smartctl -a /dev/sda | grep -E 'Reallocated|Pending|Uncorrect'
```

---

## Quick Reference Card

```
# Layout
lsblk -f                    Block devices + filesystem
fdisk -l                    Partition table
pvs / vgs / lvs             LVM summary
cat /proc/mdstat            RAID status

# Usage
df -hT                      Disk space
df -i                       Inode usage
du -sh /path/*              Directory sizes
lsof +L1 | grep deleted     Deleted files still open

# Health
smartctl -H /dev/sda        SMART health check
iostat -xz 1                I/O stats (await, %util)
iotop -o                    I/O by process
dmesg -T | grep error       Kernel disk errors

# LVM
lvcreate -L 50G -n name vg  Create volume
lvextend -L +20G dev -r     Extend + resize
lvcreate --snapshot ...     Create snapshot
lvremove /dev/vg/snap       Remove snapshot

# Filesystem
mkfs.xfs /dev/sdb1          Format as XFS
mkfs.ext4 /dev/sdb1         Format as ext4
mount -o noatime ...        Mount with noatime
xfs_growfs /mountpoint      Grow XFS online
resize2fs /dev/...          Grow ext4

# RAID
mdadm --detail /dev/md0     RAID detail
mdadm --fail /dev/md0 /dev/sdb   Mark disk failed
mdadm /dev/md0 --remove /dev/sdb  Remove disk
mdadm /dev/md0 --add /dev/sdb    Add replacement
```

---

*References: `man lsblk`, `man fdisk`, `man parted`, `man lvm`, `man mdadm`, `man smartctl`, `man iostat`, `man cryptsetup`, `man fstab`, [LVM HOWTO](https://tldp.org/HOWTO/LVM-HOWTO/), [Linux RAID Wiki](https://raid.wiki.kernel.org/)*

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 04-disk-management
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
