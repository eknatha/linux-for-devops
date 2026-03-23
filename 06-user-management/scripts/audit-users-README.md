# audit-users.sh

A production security audit script that inspects every user-related risk on a Linux server — accounts, passwords, sudo grants, SSH keys, sshd configuration, login history, cron jobs, and dangerous file permissions — then summarises all findings with warnings in one report.

---
![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat&logo=gnu-bash&logoColor=white)
**eknatha**

 

## What It Does

Runs **10 audit checks** in a single pass and flags anything that deviates from secure defaults:

| # | Check | What It Looks For |
|---|---|---|
| 1 | **Human Accounts** | All UID ≥ 1000 accounts — shell, home dir, lock status, last login, expiry |
| 2 | **UID 0 Accounts** | Any account with root-level UID that is not `root` |
| 3 | **Password Security** | Empty hashes, never-changed passwords, aging policy from `login.defs` |
| 4 | **Service Accounts** | System accounts (UID < 1000) with interactive login shells |
| 5 | **sudo Privileges** | All grants in `/etc/sudoers` and `/etc/sudoers.d/` — flags blanket `ALL` and unrestricted `NOPASSWD` |
| 6 | **SSH Authorized Keys** | Every `authorized_keys` file — permissions, key type, fingerprint, weak RSA keys |
| 7 | **sshd_config** | Checks `PermitRootLogin`, `PasswordAuthentication`, `AllowGroups`, `MaxAuthTries`, and more |
| 8 | **Login Activity** | Last 20 logins and last 20 failed login attempts |
| 9 | **Cron Jobs** | Per-user crontabs and system cron files |
| 10 | **File Permissions** | SUID binaries and world-writable files outside `/tmp` |

---

## Quick Start

```bash
chmod +x audit-users.sh

# Run interactively — report prints to stdout and saves to /var/log/user-audit-DATE.log
sudo ./audit-users.sh

# Save to a specific file
sudo ./audit-users.sh --output /tmp/audit-$(date +%F).txt

# Email report to ops team
sudo ./audit-users.sh --send-mail ops@company.com --quiet

# Quiet mode — file only, no stdout
sudo ./audit-users.sh --quiet --output /var/log/user-audit.log
```

---

## Options

| Flag | Default | Description |
|---|---|---|
| `--output FILE` | `/var/log/user-audit-DATE.log` | Save report to a custom file path |
| `--format FORMAT` | `text` | Output format: `text` or `json` |
| `--send-mail EMAIL` | — | Email the report after generation (requires `mailutils`) |
| `--quiet` | — | Suppress stdout — write to file only |

> Always runs as root. The script will exit with an error if not run with `sudo`.

---

## What Gets Flagged

The script raises a `WARNING` for any of the following — all warnings are collected and printed together in the final summary:

| Finding | Warning Raised |
|---|---|
| Human account with an unusual shell | ✔ |
| Human account with missing home directory | ✔ |
| Any UID 0 account that is not `root` | ✔ |
| Account with empty or no password hash | ✔ |
| Password that has never been changed | ✔ |
| Service account (UID < 1000) with a login shell | ✔ |
| Blanket sudo `ALL=(ALL) ALL` grant | ✔ |
| Unrestricted `NOPASSWD ALL` sudo grant | ✔ |
| `authorized_keys` file with permissions other than `600` | ✔ |
| RSA SSH key weaker than 4096 bits | ✔ |
| `PermitRootLogin` not set to `no` | ✔ |
| `PasswordAuthentication` not set to `no` | ✔ |
| `AllowGroups` not configured in `sshd_config` | ✔ |
| World-writable files outside `/proc`, `/sys`, `/tmp` | ✔ |

---

## Sample Summary Output

```
════ AUDIT SUMMARY ════

  Total warnings:               5

Issues found:
  • john.old: Password never changed
  • ci-deploy: authorized_keys permissions should be 600, found: 644
  • PasswordAuthentication = yes (expected: no)
  • AllowGroups not set — all users can attempt SSH
  • World-writable: /opt/deploy/config.sh

  Full report saved to: /var/log/user-audit-2024-01-15.log
```

---

## Cron — Scheduled Audits

```bash
# Weekly audit every Monday at 7am — email to security team
0 7 * * 1 root /opt/scripts/audit-users.sh \
    --send-mail security@company.com \
    --quiet \
    --output /var/log/user-audit-$(date +\%F).log

# Daily silent audit — file only, reviewed on-demand
0 3 * * * root /opt/scripts/audit-users.sh \
    --quiet \
    --output /var/log/user-audit-$(date +\%F).log

# Keep only last 30 audit reports
0 4 * * * root find /var/log -name 'user-audit-*.log' -mtime +30 -delete
```

---

## Report File

By default the report is written to `/var/log/user-audit-YYYY-MM-DD.log` and **also** printed to stdout simultaneously (using `tee`). Use `--quiet` to suppress stdout.

```bash
# View today's report
sudo cat /var/log/user-audit-$(date +%F).log

# Search for all warnings across past reports
sudo grep 'WARNING' /var/log/user-audit-*.log
```

---

## Requirements

| Tool | Purpose |
|---|---|
| `bash` ≥ 4.x | Script runtime |
| `root` / `sudo` | Required — reads `/etc/shadow`, `/proc`, system files |
| `chage` | Password aging per user |
| `lastlog`, `last`, `lastb` | Login and failure history |
| `ssh-keygen` | Key fingerprint and bit-strength checks |
| `getent` | Group membership lookups |
| `find` | SUID and world-writable file scan |
| `mail` *(optional)* | Email delivery (`mailutils` package) |

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 06-user-management
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
