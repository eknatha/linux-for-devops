# 06 - Linux User Management for DevOps

> **Production-grade Linux user management** — covering account lifecycle, permissions, sudo policies, SSH hardening, auditing, and automation for real-world DevOps environments.

---

## 📁 Module Structure

```
06-user-management/
├── README.md                        ← You are here
├── user-management.md               ← Deep-dive reference guide
├── scripts/
│   ├── create-service-account.sh    ← Automate service user creation
│   ├── audit-users.sh               ← Audit users & sudo privileges
│   └── rotate-ssh-keys.sh           ← SSH key rotation script
└── examples/
    ├── sudoers-production.conf      ← Sample sudoers policy
    └── sshd_config.hardened         ← Hardened SSH config
```

---

## 🚀 Quick Start

### Check existing users

```bash
# List all non-system users (UID >= 1000)
awk -F: '$3 >= 1000 {print $1, $3, $6}' /etc/passwd

# List users with login shells
grep -v '/nologin\|/false' /etc/passwd | cut -d: -f1
```

### Create a DevOps operator account

```bash
sudo useradd -m -s /bin/bash -c "DevOps Engineer" -G sudo,docker devops-user
sudo passwd devops-user
sudo mkdir -p /home/devops-user/.ssh
sudo chmod 700 /home/devops-user/.ssh
```

### Create a service/application account (no login shell)

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin --comment "App Service Account" appuser
```

---

## 📚 Topics Covered

| Topic | Description |
|---|---|
| [User Lifecycle](#) | create, modify, lock, delete accounts |
| [Groups & Permissions](#) | primary/secondary groups, ACLs |
| [sudo Policies](#) | least-privilege sudo configuration |
| [SSH Key Management](#) | deploy, rotate, and audit SSH keys |
| [PAM & Password Policy](#) | enforce password complexity and aging |
| [Auditing & Monitoring](#) | track logins, sudo usage, changes |
| [Service Accounts](#) | non-interactive accounts for apps/daemons |
| [Automation](#) | scripting user management at scale |

---

## ⚡ Production Checklist

- [ ] Disable root SSH login (`PermitRootLogin no`)
- [ ] Enforce SSH key-only authentication (`PasswordAuthentication no`)
- [ ] Apply least-privilege sudo — no blanket `ALL=(ALL) ALL`
- [ ] Set password aging (`PASS_MAX_DAYS 90` in `/etc/login.defs`)
- [ ] Lock or remove unused accounts
- [ ] Enable `auditd` for user management event logging
- [ ] Use service accounts (nologin shell) for all daemons
- [ ] Document all privileged accounts in your CMDB/runbook

---

## 🔗 See Also

- [user-management.md] — full reference with all commands and production examples
- Linux man pages: `man useradd`, `man sudoers`, `man sshd_config`, `man auditd`
- [CIS Benchmark for Linux](https://www.cisecurity.org/cis-benchmarks/)

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha  
> **Repository:** linux-for-devops / 06-user-management 
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
