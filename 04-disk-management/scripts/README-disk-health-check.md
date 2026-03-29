# disk-health-check.sh

A comprehensive disk health audit script for production Linux servers. Checks disk space, inode usage, SMART drive health, kernel errors, I/O performance, LVM/RAID status, and hidden space consumers — all in a single run with colour-coded output.

---

![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)
**eknatha**

## What It Does

Runs **10 checks** in sequence and flags anything outside safe thresholds:

| # | Check | What It Looks At |
|---|---|---|
| 1 | **Block Layout** | `lsblk` tree showing all disks, partitions, LVM, RAID, and mount points |
| 2 | **Disk Space** | Used % per filesystem — warn and critical thresholds |
| 3 | **Inode Usage** | Inode used % — a full inode table prevents new files even with free space |
| 4 | **SMART Health** | Overall health + 5 critical SMART attributes per physical disk |
| 5 | **Kernel Errors** | `dmesg` scan for I/O errors, bad blocks, ATA/SCSI/NVMe failures |
| 6 | **I/O Stats** | `iostat` snapshot — throughput, await latency, device utilisation % |
| 7 | **LVM Status** | PV/VG/LV summary + snapshot usage alerts |
| 8 | **RAID Status** | `/proc/mdstat` scan for degraded or failed RAID arrays |
| 9 | **Deleted-Open Files** | Files deleted but still held open — consuming space `df` doesn't show |
| 10 | **Top Consumers** | Largest directories and files over 100MB |

---

## Quick Start

```bash
chmod +x disk-health-check.sh

# Basic health check
sudo ./disk-health-check.sh

# Custom thresholds
sudo ./disk-health-check.sh --warn-pct 70 --crit-pct 85

# Save report to file
sudo ./disk-health-check.sh --output /var/log/disk-health-$(date +%F).log

# Alert Slack on issues
sudo ./disk-health-check.sh --slack https://hooks.slack.com/services/XXX/YYY/ZZZ

# JSON output for dashboards
sudo ./disk-health-check.sh --json | jq .
```

---

## Options

| Flag | Default | Description |
|---|---|---|
| `--warn-pct N` | `75` | Disk space warn threshold (%) |
| `--crit-pct N` | `90` | Disk space critical threshold (%) |
| `--inode-warn N` | `80` | Inode usage warn threshold (%) |
| `--output FILE` | stdout | Save full report to file |
| `--slack WEBHOOK` | — | Post alert summary to Slack (only on issues) |
| `--json` | — | Output a JSON summary to stdout |
| `--quiet` | — | Suppress stdout (use with `--output`) |

---

## Basic Examples

### Run a quick check interactively

```bash
sudo ./disk-health-check.sh
```

### Check with tighter thresholds for a busy server

```bash
sudo ./disk-health-check.sh --warn-pct 65 --crit-pct 80
```

### Save today's report silently

```bash
sudo ./disk-health-check.sh \
  --output /var/log/disk-health-$(date +%F).log \
  --quiet
```

### Alert Slack if anything is wrong

```bash
sudo ./disk-health-check.sh \
  --slack https://hooks.slack.com/services/T00.../B00.../xxx \
  --quiet
```

### Get JSON output for a monitoring pipeline

```bash
sudo ./disk-health-check.sh --json
```

```json
{
  "host": "prod-web-01.example.com",
  "date": "2024-01-15 09:00:01 UTC",
  "critical": 1,
  "warnings": 2,
  "issues": [
    "CRIT: /var: 92% used — CRITICAL (threshold: 90%)",
    "WARN: /opt: 78% used (threshold: 75%)",
    "WARN: Deleted files still open: 3 file(s) consuming ~450MB"
  ],
  "healthy": 0
}
```

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | All checks passed |
| `1` | One or more warnings |
| `2` | One or more critical alerts |

```bash
sudo ./disk-health-check.sh || echo "Disk issues found (exit: $?)"
```

---

## What Gets Flagged

| Condition | Severity |
|---|---|
| Filesystem usage ≥ `--crit-pct` | ✘ Critical |
| Filesystem usage ≥ `--warn-pct` | ⚠ Warning |
| Inode usage ≥ 90% | ✘ Critical |
| Inode usage ≥ `--inode-warn` | ⚠ Warning |
| SMART health test FAILED | ✘ Critical |
| SMART attributes 5, 187, 196, 197, 198 non-zero | ✘ Critical |
| SMART status unknown | ⚠ Warning |
| Kernel disk errors in `dmesg` | ✘ Critical |
| RAID array degraded or failed | ✘ Critical |
| LVM snapshot over 80% full | ✘ Critical |
| Deleted files still held open | ⚠ Warning |
| `iostat` await > 50ms | ⚠ Warning (inline) |
| `iostat` utilisation > 80% | ⚠ Warning (inline) |

---

## Sample Output

```
╔══════════════════════════════════════════════════╗
║       Disk Health Check Report                   ║
╚══════════════════════════════════════════════════╝

  Host:               prod-web-01
  Thresholds:         75% / 90%

━━━━ 2. Disk Space Usage ━━━━
  /                   50G   18G   30G   36%
  ✔  /: 36% — healthy
  /var                80G   71G    7G   89%
  ⚠  /var: 89% used (threshold: 75%)
  /opt/app           200G  192G    6G   96%
  ✘  /opt/app: 96% used — CRITICAL (threshold: 90%)

━━━━ 4. SMART Disk Health ━━━━
  ✔  /dev/sda: SMART health PASSED
  ✘  /dev/sdb: Reallocated_Sector_Ct = 12 (non-zero = disk degrading!)

━━━━ HEALTH SUMMARY ━━━━
  Critical:           2
  Warnings:           1
  Issues:
    CRIT: /opt/app: 96% used — CRITICAL
    CRIT: /dev/sdb: Reallocated_Sector_Ct = 12
    WARN: /var: 89% used
```

---

## Cron — Scheduled Checks

```bash
# Every 15 minutes — alert Slack on issues
*/15 * * * * root /opt/scripts/disk-health-check.sh \
    --slack https://hooks.slack.com/services/XXX/YYY/ZZZ \
    --quiet

# Daily report saved to file
0 6 * * * root /opt/scripts/disk-health-check.sh \
    --output /var/log/disk-health-$(date +\%F).log \
    --quiet

# Keep only last 30 reports
0 7 * * * root find /var/log -name 'disk-health-*.log' -mtime +30 -delete
```

---

## Requirements

| Tool | Purpose |
|---|---|
| `bash` ≥ 4.x | Script runtime |
| `lsblk`, `df`, `du` | Layout and usage checks |
| `smartctl` *(optional)* | SMART health — install `smartmontools` |
| `iostat` *(optional)* | I/O stats — install `sysstat` |
| `lsof` *(optional)* | Deleted-open file detection |
| `lvs`, `pvs`, `vgs` *(optional)* | LVM status |
| `curl` *(optional)* | Slack alert delivery |

Missing optional tools produce a warning rather than a script failure.

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 04-disk-management
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE --> 
