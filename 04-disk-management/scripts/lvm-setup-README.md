# lvm-setup.sh

A guided LVM setup script that takes a raw disk and walks through all 7 steps — Physical Volume → Volume Group → Logical Volumes → format → mount → fstab — in the correct order. Supports single-volume and multi-volume layouts with interactive safety prompts and a dry-run preview mode.

---


![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)
**eknatha**

## What It Does

Executes **7 steps** in sequence on a new disk:

| Step | Command | Action |
|---|---|---|
| 1 | `lsblk` / safety check | Verify disk exists, detect existing data, confirm before proceeding |
| 2 | `pvcreate` | Mark disk as an LVM Physical Volume |
| 3 | `vgcreate` | Create a Volume Group from the PV |
| 4 | `lvcreate` | Create one or more Logical Volumes inside the VG |
| 5 | `mkfs.xfs` / `mkfs.ext4` | Format each LV with the chosen filesystem |
| 6 | `mount` | Mount each LV to its target directory |
| 7 | `/etc/fstab` | Write persistent mount entries so volumes survive reboots |

---

## Quick Start

```bash
chmod +x lvm-setup.sh

# Preview all steps without making any changes
sudo ./lvm-setup.sh --disk /dev/sdb --dry-run

# Single volume — use the entire disk for /data
sudo ./lvm-setup.sh --disk /dev/sdb

# Multi-volume layout — app, logs, and database
sudo ./lvm-setup.sh --disk /dev/sdb \
  --lv-app 50G \
  --lv-logs 20G \
  --lv-db 100G

# Non-interactive (CI/automation)
sudo ./lvm-setup.sh --disk /dev/sdb \
  --vg vg_data \
  --lv-app 50G --lv-db 200G \
  --auto
```

---

## Options

| Flag | Default | Description |
|---|---|---|
| `--disk DEVICE` | *(required)* | Raw disk to use (e.g., `/dev/sdb`) |
| `--vg NAME` | `vg_data` | Volume Group name |
| `--lv-app SIZE` | — | Create `lv_app` LV, mounted at `/opt/app` |
| `--lv-db SIZE` | — | Create `lv_db` LV, mounted at `/var/lib/database` |
| `--lv-logs SIZE` | — | Create `lv_logs` LV, mounted at `/var/log/app` |
| `--fstype TYPE` | `xfs` | Filesystem type: `xfs` or `ext4` |
| `--auto` | — | Skip confirmation prompts (for automation) |
| `--dry-run` | — | Print all commands without executing |

---

## Basic Examples

### Example 1 — Preview before doing anything

Always run `--dry-run` first on production systems to confirm the correct disk is targeted.

```bash
sudo ./lvm-setup.sh --disk /dev/sdb --dry-run
```

```
▶ Step 1: Verify disk
  [DRY-RUN] Disk: /dev/sdb — Size: 500GB

▶ Step 2: Create Physical Volume (pvcreate)
  [DRY-RUN] pvcreate '/dev/sdb'

▶ Step 3: Create Volume Group (vgcreate)
  [DRY-RUN] vgcreate 'vg_data' '/dev/sdb'

▶ Step 4: Create Logical Volumes (lvcreate)
  [DRY-RUN] lvcreate -l 100%FREE -n lv_data 'vg_data'
...
```

---

### Example 2 — Single volume (entire disk as `/data`)

The simplest setup: one LV that uses 100% of the VG.

```bash
sudo ./lvm-setup.sh --disk /dev/sdb
```

Creates: `/dev/vg_data/lv_data` → formatted as XFS → mounted at `/data`

---

### Example 3 — Web application server layout

Separate LVs for app code and application logs.

```bash
sudo ./lvm-setup.sh \
  --disk /dev/sdb \
  --vg vg_app \
  --lv-app 80G \
  --lv-logs 30G
```

Creates:
- `/dev/vg_app/lv_app` (80G, XFS) → `/opt/app`
- `/dev/vg_app/lv_logs` (30G, XFS) → `/var/log/app`

---

### Example 4 — Database server layout

Dedicated volume for the database with the remaining space for logs.

```bash
sudo ./lvm-setup.sh \
  --disk /dev/sdb \
  --vg vg_db \
  --lv-db 300G \
  --lv-logs 50G \
  --fstype ext4
```

Creates:
- `/dev/vg_db/lv_db` (300G, ext4) → `/var/lib/database`
- `/dev/vg_db/lv_logs` (50G, ext4) → `/var/log/app`

---

### Example 5 — Full three-volume layout (automated)

No prompts — suitable for CI/CD provisioning pipelines.

```bash
sudo ./lvm-setup.sh \
  --disk /dev/sdb \
  --vg vg_data \
  --lv-app 100G \
  --lv-db 200G \
  --lv-logs 50G \
  --auto
```

---

## What Gets Written to `/etc/fstab`

For each LV created, the script appends a persistent mount entry using the stable `/dev/mapper/` path:

```fstab
/dev/mapper/vg_data-lv_app    /opt/app          xfs  defaults,noatime  0  2
/dev/mapper/vg_data-lv_db     /var/lib/database xfs  defaults,noatime  0  2
/dev/mapper/vg_data-lv_logs   /var/log/app      xfs  defaults,noatime  0  2
```

It checks for existing entries before appending — safe to run multiple times.

---

## Default Mount Points

| LV Name | Mounted at |
|---|---|
| `lv_data` | `/data` |
| `lv_app` | `/opt/app` |
| `lv_db` | `/var/lib/database` |
| `lv_logs` | `/var/log/app` |

---

## Extending a Volume Later

LVM's main advantage is online resizing. After the initial setup, you can grow any LV without downtime.

```bash
# Extend lv_app by 20GB and grow the filesystem in one step
sudo lvextend -L +20G -r /dev/vg_data/lv_app

# Extend to use all remaining free space in the VG
sudo lvextend -l +100%FREE -r /dev/vg_data/lv_app

# For XFS — grow the filesystem while mounted
sudo lvextend -L +20G /dev/vg_data/lv_app
sudo xfs_growfs /opt/app

# For ext4 — grow the filesystem while mounted
sudo lvextend -L +20G /dev/vg_data/lv_app
sudo resize2fs /dev/vg_data/lv_app
```

---

## Requirements

| Tool | Purpose |
|---|---|
| `bash` ≥ 4.x | Script runtime |
| `lvm2` | `pvcreate`, `vgcreate`, `lvcreate`, `lvs` etc. |
| `xfsprogs` | `mkfs.xfs` (for XFS filesystems) |
| `e2fsprogs` | `mkfs.ext4` (for ext4 filesystems) |
| `root` / `sudo` | Required for all LVM operations |

```bash
# Install on Debian/Ubuntu
sudo apt install lvm2 xfsprogs e2fsprogs

# Install on RHEL/CentOS
sudo yum install lvm2 xfsprogs e2fsprogs
```

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 04-disk-management
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
