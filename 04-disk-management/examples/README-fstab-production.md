# fstab-production.conf

A production-ready `/etc/fstab` reference covering all common mount scenarios — root filesystem, LVM volumes, NFS shares, tmpfs, bind mounts, and swap — with the correct options for performance, safety, and boot reliability.

---

**eknatha** 

## What It Covers

| Entry Type | Use Case |
|---|---|
| Root (`/`) | `errors=remount-ro` — prevents corruption on filesystem errors |
| Boot (`/boot`, `/boot/efi`) | Separate boot and EFI partitions |
| App / data volumes | XFS with `noatime` — reduces unnecessary writes by ~30% |
| LVM volumes | `/dev/mapper/` paths — stable names that don't change after reboots |
| Swap | UUID-based or LVM swap |
| NFS shares | `nofail,_netdev` — won't stall boot if NFS is unreachable |
| CIFS/SMB shares | Credentials file, correct UID/GID, `nofail` |
| tmpfs | RAM-based filesystem for `/tmp` and build caches |
| Bind mounts | Map a directory to another path without copying |

---

## fstab Line Format

```
<device>   <mountpoint>   <type>   <options>   <dump>   <pass>
```

| Field | Values | Meaning |
|---|---|---|
| `device` | `UUID=...`, `/dev/mapper/...`, `hostname:/path` | What to mount |
| `mountpoint` | `/data`, `/mnt/nfs` | Where to mount it |
| `type` | `ext4`, `xfs`, `nfs4`, `tmpfs`, `swap` | Filesystem type |
| `options` | `defaults,noatime` | Mount options (comma-separated) |
| `dump` | `0` or `1` | Backup priority — always `0` in modern setups |
| `pass` | `0`, `1`, `2` | `0` = skip fsck, `1` = root first, `2` = after root |

---

## Installation

```bash
# Step 1: Find UUIDs of your devices
blkid
lsblk -f

# Step 2: Backup current fstab
sudo cp /etc/fstab /etc/fstab.bak-$(date +%F)

# Step 3: Edit fstab
sudo vi /etc/fstab

# Step 4: Test without rebooting
sudo mount -fav       # Dry-run — shows what would be mounted
sudo mount -a         # Apply — mounts everything not yet mounted
sudo findmnt --verify # Verify fstab has no errors
```

---

## Basic Examples

### Standard server disk layout

```fstab
# Root — remount read-only on error (prevents further corruption)
UUID="a1b2c3d4-1234-..."   /         ext4   defaults,errors=remount-ro   0  1

# Boot partition
UUID="e5f6a7b8-5678-..."   /boot     ext4   defaults                     0  2

# Application data — XFS with noatime (high-write workloads benefit most)
UUID="c9d0e1f2-9012-..."   /opt/app  xfs    defaults,noatime             0  2

# Swap
UUID="k7l8m9n0-3456-..."   none      swap   sw                           0  0
```

### LVM logical volumes

```fstab
# Use /dev/mapper/ path — these names are stable across reboots
# Format: /dev/mapper/<vg_name>-<lv_name>
/dev/mapper/vg_data-lv_app    /opt/app         xfs    defaults,noatime   0  2
/dev/mapper/vg_data-lv_logs   /var/log         ext4   defaults,noatime   0  2
/dev/mapper/vg_data-lv_db     /var/lib/postgresql  xfs  defaults,noatime 0  2
```

### NFS network share

```fstab
# nofail   → don't halt boot if NFS server is unreachable
# _netdev  → wait for network before attempting mount
# bg       → retry in background if first attempt fails
10.0.1.20:/shared/assets   /mnt/assets   nfs4   defaults,nofail,_netdev,timeo=30,bg   0  0
```

### tmpfs — RAM-based temporary storage

```fstab
# Size limits prevent runaway processes from filling RAM
# mode=1777 — world-writable with sticky bit (same as standard /tmp)
tmpfs   /tmp        tmpfs   defaults,size=2G,mode=1777   0  0
tmpfs   /tmp/build  tmpfs   defaults,size=4G,mode=1777   0  0
```

### Bind mount — expose a directory at a second path

```fstab
# Useful when migrating paths without changing application configs
# Source must exist before binding
/opt/app/data   /data   none   bind   0  0
```

### Secure /tmp (prevent script execution)

```fstab
# noexec — prevents running binaries from /tmp (common attack vector)
# nosuid — ignore setuid/setgid bits
# nodev  — ignore device files
tmpfs   /tmp   tmpfs   defaults,size=2G,mode=1777,noexec,nosuid,nodev   0  0
```

---

## Key Mount Options

| Option | Effect | When to Use |
|---|---|---|
| `noatime` | Skip access timestamp updates on reads | Data, log, and app volumes — reduces I/O |
| `errors=remount-ro` | Remount read-only on filesystem error | Root filesystem (`/`) |
| `nofail` | Don't fail boot if device is missing | NFS, USB, non-critical mounts |
| `_netdev` | Wait for network before mounting | NFS, iSCSI, CIFS |
| `noexec` | Block binary execution | `/tmp`, `/var`, user-owned paths |
| `nosuid` | Ignore setuid/setgid bits | `/tmp`, `/home`, external storage |
| `discard` | Enable SSD TRIM on file deletion | SSDs (prefer `fstrim.timer` instead) |
| `barrier=0` | Disable write barriers | SSD with battery-backed write cache |

---

## Getting UUIDs

Always use UUIDs in `/etc/fstab`. Device names like `/dev/sdb1` can change after adding a disk or rebooting — UUIDs never change.

```bash
# Show UUID for all block devices
blkid

# Show UUID for a specific device
blkid /dev/sdb1

# Tree view with filesystems and UUIDs
lsblk -f

# Show only the UUID (for scripting)
blkid /dev/sdb1 -s UUID -o value
```

---

## Testing After Every Change

```bash
# 1. Dry-run — see what mount -a would do without actually mounting
sudo mount -fav

# 2. Apply new entries (mounts everything in fstab not already mounted)
sudo mount -a

# 3. Check for fstab syntax errors
sudo findmnt --verify

# 4. Confirm a specific mount is working
findmnt /opt/app
df -hT /opt/app
```

---

## Common Mistakes

**Using device names instead of UUIDs** — `/dev/sdb1` can become `/dev/sdc1` after adding a disk. Use `UUID=...` always.

**Missing `nofail` on NFS mounts** — without it, a missing NFS server at boot will prevent the server from finishing startup.

**Missing `_netdev` on NFS/CIFS mounts** — without it, the mount may be attempted before the network is up.

**Not testing with `mount -a`** — a typo in fstab won't be caught until the next reboot, which could leave the server unbootable. Always test immediately after editing.

**Wrong `pass` value** — only the root filesystem should be `1`. All other filesystems should be `2` or `0`.

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 04-disk-management
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
