# 04 - Linux Disk Management for DevOps

> **Production-grade Linux disk management** — covering partitioning, filesystems, LVM, RAID, mounting, disk health monitoring, performance tuning, backup strategies, and storage troubleshooting for real-world DevOps environments.

---

## 📁 Module Structure

```
04-disk-management/
├── README.md                          ← You are here
├── disk-management.md                 ← Deep-dive reference guide
├── scripts/
│   ├── disk-health-check.sh           ← SMART, filesystem, and usage audit
│   ├── lvm-snapshot-backup.sh         ← LVM snapshot-based backup
│   ├── disk-benchmark.sh              ← I/O throughput and latency benchmark
│   └── storage-cleanup.sh             ← Find and clean large/old files safely
└── examples/
    ├── fstab-production.conf          ← /etc/fstab for production mounts
    ├── lvm-setup.sh                   ← LVM volume group creation walkthrough
    └── mdadm-raid.conf                ← Software RAID-1 configuration
```

---

## Always Check befor executing any commands in production. 

## 🚀 Quick Start

### View disk layout and usage

```bash
# Block device tree (disks, partitions, LVM)
lsblk -f

# Disk usage by filesystem
df -hT | grep -vE 'tmpfs|devtmpfs'

# Directory sizes — find what's consuming space
du -sh /var/* 2>/dev/null | sort -rh | head -10

# Inode usage (can fill up even when disk space is available)
df -i | grep -vE 'tmpfs|devtmpfs'
```

### Check disk health

```bash
# SMART status (requires smartmontools)
sudo smartctl -H /dev/sda

# I/O stats — throughput, latency, utilisation
iostat -xz 1 3

# Check filesystem errors
sudo dmesg | grep -iE 'error|fail|bad block|i/o error'
```

### Find what's eating disk space

```bash
# Top 20 largest files
sudo find / -size +100M -type f -not -path '/proc/*' 2>/dev/null \
  | xargs ls -lh | sort -k5 -rh | head -20

# Deleted files still held open (disk not freed)
sudo lsof +L1 | grep deleted
```

---

## 📚 Topics Covered

| Topic | Description |
|---|---|
| [Block Devices](#) | lsblk, fdisk, parted — disk and partition management |
| [Filesystems](#) | ext4, xfs, btrfs — format, mount, check, repair |
| [LVM](#) | Physical volumes, volume groups, logical volumes, snapshots |
| [Software RAID](#) | mdadm RAID-1/5/6 — setup, monitoring, recovery |
| [Mount Management](#) | /etc/fstab, systemd mounts, bind mounts, NFS |
| [Disk Health](#) | SMART monitoring, iostat, badblocks, fsck |
| [Performance Tuning](#) | I/O scheduler, readahead, filesystem options |
| [Space Management](#) | du, find, lsof +L1, log rotation |
| [Backup Strategies](#) | LVM snapshots, rsync, dd, tar over network |
| [Encryption](#) | LUKS, cryptsetup, encrypted volumes |
| [Production Runbook](#) | Disk full, I/O hang, filesystem corruption incidents |

---

## ⚡ Production Disk Management Checklist

- [ ] Monitor all filesystems — alert at 75% warn / 90% critical
- [ ] Monitor inode usage — alert at 80% (can fill even with free space)
- [ ] Enable SMART monitoring on all physical drives (`smartd`)
- [ ] Use LVM for all non-boot volumes — enables live resizing and snapshots
- [ ] Mount data volumes with `noatime` to reduce unnecessary writes
- [ ] Configure `logrotate` for all application log directories
- [ ] Set up automated LVM snapshots before deployments
- [ ] Test filesystem mount at boot with `nofail` on non-critical mounts
- [ ] Enable `fstrim` timer for SSD volumes (`systemctl enable fstrim.timer`)
- [ ] Audit for deleted-but-held-open files regularly (`lsof +L1`)
- [ ] Test disk replacement procedure on staging before production
- [ ] Document all disk layout — LVM VG/LV names, RAID members, mount points

---

## 🛠️ Essential Disk Commands — Quick Reference

```bash
# Layout
lsblk -f                            Block devices with filesystems
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT  Custom view
fdisk -l                            Partition table
parted -l                           All disk partition info
pvs / vgs / lvs                     LVM physical/group/logical volumes

# Usage
df -hT                              Disk space by filesystem
df -i                               Inode usage
du -sh /path/*                      Directory sizes
du -sh --exclude=proc /*            Root directory sizes

# Health
smartctl -H /dev/sda                SMART health status
smartctl -a /dev/sda                Full SMART data
iostat -xz 1                        I/O stats (throughput, await, util%)
iotop -o                            Processes doing I/O

# Filesystem
fsck -n /dev/sdb1                   Check filesystem (read-only, safe)
xfs_check /dev/sdb1                 Check XFS (unmounted)
tune2fs -l /dev/sdb1                ext4 filesystem info
xfs_info /dev/sdb1                  XFS filesystem info

# LVM
pvcreate /dev/sdb                   Create physical volume
vgcreate vg_data /dev/sdb           Create volume group
lvcreate -L 50G -n lv_app vg_data  Create logical volume
lvextend -L +20G /dev/vg_data/lv_app  Extend volume
resize2fs /dev/vg_data/lv_app      Resize ext4 after LV extend
xfs_growfs /mount/point            Grow XFS (while mounted)

# Performance
hdparm -t /dev/sda                  Read throughput test
fio --name=test --rw=read ...       Full I/O benchmark
echo deadline > /sys/block/sda/queue/scheduler  Set I/O scheduler
```

---

## 🔗 See Also

- [disk-management.md] — full reference with all commands and production examples
- `man lsblk`, `man fdisk`, `man parted`, `man lvm`, `man mdadm`, `man fstab`, `man smartctl`
- [Linux RAID documentation](https://raid.wiki.kernel.org/)
- [LVM HOWTO](https://tldp.org/HOWTO/LVM-HOWTO/)
- [XFS documentation](https://xfs.wiki.kernel.org/)
- [Brendan Gregg — Linux Storage](https://www.brendangregg.com/linuxperf.html)

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 04-disk-management
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
