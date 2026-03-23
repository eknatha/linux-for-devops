# Linux User Management — Production Reference Guide

> Comprehensive reference for managing users, groups, permissions, sudo policies, SSH keys, and auditing in production Linux environments.

---

## Table of Contents

1. [Understanding /etc/passwd and /etc/shadow](#1-understanding-etcpasswd-and-etcshadow)
2. [User Account Lifecycle](#2-user-account-lifecycle)
3. [Group Management](#3-group-management)
4. [Password Policy and PAM](#4-password-policy-and-pam)
5. [sudo Configuration — Least Privilege](#5-sudo-configuration--least-privilege)
6. [SSH Key Management](#6-ssh-key-management)
7. [Service Accounts for Applications](#7-service-accounts-for-applications)
8. [File Permissions, Ownership, and ACLs](#8-file-permissions-ownership-and-acls)
9. [Auditing and Monitoring](#9-auditing-and-monitoring)
10. [Automation at Scale](#10-automation-at-scale)
11. [Production Hardening Checklist](#11-production-hardening-checklist)

---

## 1. Understanding /etc/passwd and /etc/shadow

### /etc/passwd — Field Breakdown

```
username:password:UID:GID:GECOS:home:shell
deployer:x:1001:1001:Deploy Bot:/home/deployer:/bin/bash
```

| Field | Meaning | Production Note |
|---|---|---|
| `username` | Login name | Use lowercase, no spaces |
| `x` | Password hash stored in shadow | Always `x` on modern systems |
| `UID` | User ID | `< 1000` = system, `>= 1000` = human |
| `GID` | Primary group ID | Match to group in /etc/group |
| `GECOS` | Full name / comment | Use for role description |
| `home` | Home directory | Set to `/var/lib/appname` for services |
| `shell` | Login shell | `/usr/sbin/nologin` for service accounts |

### /etc/shadow — Password Aging Fields

```bash
# View password aging info for a user
sudo chage -l appuser

# Output:
# Last password change        : Jan 01, 2024
# Password expires            : Apr 01, 2024
# Password inactive           : never
# Account expires             : never
# Minimum number of days between password change : 7
# Maximum number of days between password change : 90
# Number of days of warning before password expires : 14
```

---

## 2. User Account Lifecycle

### Create a Human (Operator) Account

```bash
# Full-featured operator account
sudo useradd \
  --create-home \
  --shell /bin/bash \
  --comment "DevOps Engineer - John Doe" \
  --groups sudo,docker,adm \
  john.doe

# Set initial password (force change on first login)
sudo passwd john.doe
sudo chage --lastday 0 john.doe   # Forces password reset on next login
```

### Create a Deployment / CI Account

```bash
# Account used by CI/CD pipelines (e.g., Jenkins, GitHub Actions runner)
sudo useradd \
  --create-home \
  --shell /bin/bash \
  --comment "CI/CD Deploy Account" \
  --groups docker,deployers \
  ci-deploy

# No password — SSH key only
sudo passwd --lock ci-deploy      # Lock password auth
sudo mkdir -p /home/ci-deploy/.ssh
sudo chmod 700 /home/ci-deploy/.ssh
sudo touch /home/ci-deploy/.ssh/authorized_keys
sudo chmod 600 /home/ci-deploy/.ssh/authorized_keys
sudo chown -R ci-deploy:ci-deploy /home/ci-deploy/.ssh
```

### Modify an Existing Account

```bash
# Add user to an additional group (e.g., grant docker access)
sudo usermod --append --groups docker john.doe

# Change login shell
sudo usermod --shell /bin/zsh john.doe

# Rename a user (also update home dir)
sudo usermod --login newname --home /home/newname --move-home oldname

# Set account expiry date (for contractors)
sudo usermod --expiredate 2024-12-31 contractor.alice
```

### Lock and Unlock Accounts

```bash
# Lock — disables password login, SSH key login still works
sudo usermod --lock john.doe
# OR
sudo passwd --lock john.doe

# Truly disable all login (locks password AND disables account)
sudo usermod --expiredate 1 john.doe   # Sets expiry to Jan 2 1970

# Unlock
sudo usermod --unlock john.doe
sudo usermod --expiredate "" john.doe  # Remove expiry

# Verify lock status (! or * prefix = locked)
sudo grep john.doe /etc/shadow
```

### Delete an Account

```bash
# Safe delete — keep home directory as archive
sudo userdel john.doe

# Delete + remove home directory (DESTRUCTIVE — backup first!)
sudo userdel --remove john.doe

# Production-safe offboarding: archive, then delete
sudo tar -czf /archive/users/john.doe-$(date +%F).tar.gz /home/john.doe
sudo userdel --remove john.doe
```

---

## 3. Group Management

### Group Concepts

```
group-name:password:GID:member1,member2
docker:x:998:john.doe,ci-deploy
```

### Common Production Groups

| Group | Purpose |
|---|---|
| `sudo` / `wheel` | Full sudo access (restrict carefully) |
| `docker` | Run Docker — treat as near-root |
| `adm` | Read system logs (`/var/log/`) |
| `www-data` | Web server process group |
| `deployers` | Shared group for deployment scripts |

### Create and Manage Groups

```bash
# Create a custom group
sudo groupadd deployers
sudo groupadd --gid 2000 appteam    # Explicit GID (useful across servers)

# Add user to group (append — don't replace existing groups)
sudo usermod --append --groups deployers john.doe

# View all groups for a user
groups john.doe
id john.doe

# Remove user from a group
sudo gpasswd --delete john.doe deployers

# List all members of a group
getent group docker

# Delete a group
sudo groupdel deployers
```

### Shared Directory with Group Access

```bash
# Common pattern: shared deployment directory
sudo mkdir -p /opt/releases
sudo chown root:deployers /opt/releases
sudo chmod 2775 /opt/releases     # setgid bit: new files inherit group

# Verify
ls -ld /opt/releases
# drwxrwsr-x 2 root deployers 4096 ...
```

---

## 4. Password Policy and PAM

### /etc/login.defs — System-wide Defaults

```bash
sudo vi /etc/login.defs
```

```ini
# Recommended production values
PASS_MAX_DAYS   90      # Force rotation every 90 days
PASS_MIN_DAYS   7       # Minimum 7 days before change allowed
PASS_WARN_AGE   14      # Warn 14 days before expiry
PASS_MIN_LEN    14      # Minimum password length

LOGIN_RETRIES   5       # Lock after 5 failed attempts
LOGIN_TIMEOUT   60      # 60 second login timeout
```

### PAM — Password Complexity (Ubuntu/Debian)

```bash
# Install
sudo apt install libpam-pwquality

# Edit PAM config
sudo vi /etc/pam.d/common-password
```

```
# Add/update this line:
password requisite pam_pwquality.so retry=3 minlen=14 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1 reject_username enforce_for_root
```

| Option | Meaning |
|---|---|
| `minlen=14` | Minimum 14 characters |
| `dcredit=-1` | At least 1 digit |
| `ucredit=-1` | At least 1 uppercase |
| `ocredit=-1` | At least 1 special character |
| `lcredit=-1` | At least 1 lowercase |
| `reject_username` | Disallow username in password |

### Account Lockout with faillock (RHEL/CentOS)

```bash
# /etc/security/faillock.conf
deny = 5           # Lock after 5 failures
unlock_time = 900  # Auto-unlock after 15 minutes
fail_interval = 900

# View locked accounts
sudo faillock

# Manually unlock a user
sudo faillock --user john.doe --reset
```

### Set Password Aging for Existing Users

```bash
# Apply aging policy to specific user
sudo chage \
  --maxdays 90 \
  --mindays 7 \
  --warndays 14 \
  --inactive 30 \
  john.doe

# Apply to all human users in bulk
for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
  sudo chage --maxdays 90 --warndays 14 "$user"
  echo "Updated: $user"
done
```

---

## 5. sudo Configuration — Least Privilege

> **Golden Rule:** Grant the minimum sudo rights required. Never use `ALL=(ALL) ALL` in production.

### Edit sudoers Safely

```bash
# ALWAYS use visudo — validates syntax before saving
sudo visudo

# Edit a drop-in file (preferred for production)
sudo visudo -f /etc/sudoers.d/deployers
```

### sudoers Syntax

```
# Format: WHO  WHERE=(AS_WHOM)  COMMAND
user    ALL=(ALL)      /usr/bin/systemctl restart nginx
%group  ALL=(ALL)      NOPASSWD: /usr/bin/docker ps
```

### Production sudoers Examples

```bash
# /etc/sudoers.d/10-operators
# Senior ops team: manage services, no shell escalation
%ops-team ALL=(ALL) NOPASSWD: \
    /usr/bin/systemctl start *, \
    /usr/bin/systemctl stop *, \
    /usr/bin/systemctl restart *, \
    /usr/bin/systemctl reload *, \
    /usr/bin/journalctl *

# /etc/sudoers.d/20-deployers
# CI/CD deploy account: only restart app services
ci-deploy ALL=(ALL) NOPASSWD: \
    /usr/bin/systemctl restart myapp, \
    /usr/bin/systemctl restart nginx, \
    /usr/bin/systemctl reload nginx

# /etc/sudoers.d/30-dbadmins
# DBA group: only database management commands
%dbadmins ALL=(ALL) NOPASSWD: \
    /usr/bin/systemctl restart postgresql, \
    /usr/bin/systemctl restart mysql, \
    /usr/bin/pg_dump *, \
    /usr/bin/mysqldump *

# /etc/sudoers.d/40-readonly
# Monitoring account: read-only system commands
monitoring ALL=(ALL) NOPASSWD: \
    /usr/bin/ss -tulnp, \
    /usr/bin/netstat -tulnp, \
    /usr/bin/df *, \
    /usr/bin/free *, \
    /bin/cat /var/log/nginx/*, \
    /usr/bin/journalctl --no-pager *
```

### Audit Sudo Access

```bash
# List all users/groups with sudo access
sudo grep -r 'ALL' /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v '^#'

# Check if a user can sudo
sudo -l -U john.doe

# View sudo usage log
sudo journalctl _COMM=sudo | tail -50
grep 'sudo' /var/log/auth.log | grep -v '#'
```

---

## 6. SSH Key Management

### Generate SSH Key Pair (Ed25519 — recommended)

```bash
# On the user's LOCAL machine
ssh-keygen -t ed25519 -C "john.doe@company.com-$(date +%Y)" -f ~/.ssh/id_ed25519_prod

# For older systems that require RSA
ssh-keygen -t rsa -b 4096 -C "john.doe@company.com" -f ~/.ssh/id_rsa_prod
```

### Deploy Public Key to a Server

```bash
# Method 1: ssh-copy-id (easy)
ssh-copy-id -i ~/.ssh/id_ed25519_prod.pub john.doe@server.example.com

# Method 2: Manual (useful in automation)
cat ~/.ssh/id_ed25519_prod.pub | \
  ssh john.doe@server.example.com \
  "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# Method 3: From server side (when deploying for another user)
sudo -u john.doe bash -c "
  mkdir -p /home/john.doe/.ssh
  echo 'ssh-ed25519 AAAA...pubkeyhere... john.doe@company.com' >> /home/john.doe/.ssh/authorized_keys
  chmod 700 /home/john.doe/.ssh
  chmod 600 /home/john.doe/.ssh/authorized_keys
"
```

### Rotate SSH Keys

```bash
# Step 1: Generate new key on client
ssh-keygen -t ed25519 -C "john.doe@company.com-2024" -f ~/.ssh/id_ed25519_prod_2024

# Step 2: Add new key FIRST (don't remove old key yet)
ssh-copy-id -i ~/.ssh/id_ed25519_prod_2024.pub john.doe@server.example.com

# Step 3: Verify new key works
ssh -i ~/.ssh/id_ed25519_prod_2024 john.doe@server.example.com "echo OK"

# Step 4: Remove the old key from authorized_keys
# (identify old key fingerprint)
ssh-keygen -lf ~/.ssh/id_ed25519_prod.pub

# Remove old key from server
ssh john.doe@server.example.com \
  "sed -i '/OLD_KEY_COMMENT_OR_FINGERPRINT/d' ~/.ssh/authorized_keys"

# Step 5: Remove old private key locally
rm ~/.ssh/id_ed25519_prod ~/.ssh/id_ed25519_prod.pub
```

### Audit Authorized Keys Across Servers

```bash
# List all authorized_keys files on the server
sudo find /home /root /var/lib -name "authorized_keys" 2>/dev/null | while read f; do
  echo "=== $f ==="
  sudo cat "$f"
done

# Count keys per user
for user in $(awk -F: '$3 >= 1000 {print $1}' /etc/passwd); do
  keyfile="/home/$user/.ssh/authorized_keys"
  if [ -f "$keyfile" ]; then
    count=$(grep -c 'ssh-' "$keyfile" 2>/dev/null || echo 0)
    echo "$user: $count key(s)"
  fi
done
```

### Harden sshd_config

```bash
# /etc/ssh/sshd_config — Production hardening
sudo vi /etc/ssh/sshd_config
```

```ini
# Disable root login
PermitRootLogin no

# SSH keys only — disable password auth
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes

# Disable empty passwords
PermitEmptyPasswords no

# Only allow specific groups
AllowGroups ssh-users ops-team ci-deploy

# Use strong ciphers only
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org

# Timeouts
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30

# Logging
LogLevel VERBOSE
```

```bash
# Test config before restart
sudo sshd -t && sudo systemctl restart sshd
```

---

## 7. Service Accounts for Applications

Service accounts run application processes. They should never have interactive shells or be able to SSH into servers.

### Create a Service Account

```bash
# Application service account pattern
APP="myapp"

sudo useradd \
  --system \                         # Low UID (< 1000), no home by default
  --no-create-home \
  --home-dir /opt/$APP \             # App data directory
  --shell /usr/sbin/nologin \        # No interactive login
  --comment "$APP service account" \
  $APP

# Create app directories with proper ownership
sudo mkdir -p /opt/$APP/{bin,conf,data,logs}
sudo chown -R $APP:$APP /opt/$APP/data /opt/$APP/logs
sudo chown root:$APP /opt/$APP/conf
sudo chmod 750 /opt/$APP/conf       # Service can read config, not write
```

### systemd Unit with Service Account

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Application
After=network.target

[Service]
Type=simple
User=myapp
Group=myapp
WorkingDirectory=/opt/myapp

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/myapp/data /opt/myapp/logs
PrivateTmp=yes
CapabilityBoundingSet=

ExecStart=/opt/myapp/bin/myapp --config /opt/myapp/conf/config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now myapp
```

### Common Production Service Accounts

```bash
# Nginx / Apache
sudo useradd --system --no-create-home --shell /usr/sbin/nologin www-data

# PostgreSQL
sudo useradd --system --create-home --home /var/lib/postgresql \
  --shell /bin/bash --comment "PostgreSQL Server" postgres

# Note: postgres needs a real shell for pg tools; restrict via SSH and sudo instead

# Redis
sudo useradd --system --no-create-home --shell /usr/sbin/nologin redis

# Prometheus
sudo useradd --system --no-create-home --shell /usr/sbin/nologin \
  --comment "Prometheus monitoring" prometheus
```

---

## 8. File Permissions, Ownership, and ACLs

### Permission Basics

```bash
# Permission string: -rwxr-x---
# Type: - (file) d (dir) l (symlink)
# Owner: rwx (read, write, execute)
# Group: r-x (read, execute)
# Others: --- (none)

chmod 750 /opt/myapp/bin/myapp   # Owner: rwx, Group: r-x, Others: none
chown myapp:deployers /opt/myapp/bin/myapp
```

### Numeric (Octal) Reference

| Octal | Symbolic | Use Case |
|---|---|---|
| `700` | `rwx------` | Private dirs, SSH keys |
| `750` | `rwxr-x---` | App binaries, group access |
| `755` | `rwxr-xr-x` | Public binaries, web root |
| `640` | `rw-r-----` | Config files with group read |
| `600` | `rw-------` | Secret files, private keys |
| `644` | `rw-r--r--` | Public config, web assets |
| `2775` | `rwxrwsr-x` | Shared directories (setgid) |

### ACLs — Fine-grained Access

```bash
# Install
sudo apt install acl    # Debian/Ubuntu
sudo yum install acl    # RHEL/CentOS

# Grant a specific user read access to a log dir
sudo setfacl -m u:monitoring:rx /var/log/myapp

# Grant a group write access to a deployment dir
sudo setfacl -m g:deployers:rwx /opt/releases

# Set default ACL (new files inherit this)
sudo setfacl -d -m g:deployers:rwx /opt/releases

# View ACLs
getfacl /opt/releases

# Remove ACL
sudo setfacl -x u:monitoring /var/log/myapp

# Recursive ACL
sudo setfacl -R -m u:monitoring:rx /var/log/myapp
```

### Find Files with Dangerous Permissions

```bash
# SUID binaries (run as file owner)
sudo find / -perm -4000 -type f 2>/dev/null

# SGID binaries
sudo find / -perm -2000 -type f 2>/dev/null

# World-writable files (security risk)
sudo find / -perm -0002 -type f -not -path '/proc/*' 2>/dev/null

# Files with no owner
sudo find / -nouser -o -nogroup 2>/dev/null | grep -v '/proc'
```

---

## 9. Auditing and Monitoring

### Track Login Events

```bash
# Current logged in users
w
who

# Login history (last 20 logins)
last -20

# Failed login attempts
lastb | head -20          # Requires root
sudo grep 'Failed' /var/log/auth.log | tail -30

# Last login per user
lastlog | grep -v 'Never logged in'

# SSH logins today
sudo journalctl -u sshd --since today | grep 'Accepted'
```

### auditd — Comprehensive Event Logging

```bash
# Install
sudo apt install auditd    # Debian/Ubuntu
sudo yum install audit     # RHEL/CentOS

sudo systemctl enable --now auditd
```

```bash
# /etc/audit/rules.d/user-management.rules
# Monitor user account changes
-w /etc/passwd -p wa -k user-modify
-w /etc/shadow -p wa -k user-modify
-w /etc/group -p wa -k group-modify
-w /etc/sudoers -p wa -k sudoers-modify
-w /etc/sudoers.d/ -p wa -k sudoers-modify

# Monitor SSH authorized_keys changes
-w /root/.ssh -p wa -k ssh-keys
-w /home -p wa -k ssh-keys

# Track use of privileged commands
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -k root-commands

# Monitor su and sudo
-w /bin/su -p x -k privilege-escalation
-w /usr/bin/sudo -p x -k privilege-escalation
```

```bash
# Reload rules
sudo augenrules --load

# Query audit logs
sudo ausearch -k user-modify | tail -20
sudo ausearch -k sudoers-modify
sudo ausearch -k privilege-escalation | aureport -au

# Summary report
sudo aureport --login --summary
sudo aureport --auth --summary
```

### Monitor sudo Usage in Real-Time

```bash
# Tail auth log for sudo activity
sudo tail -f /var/log/auth.log | grep sudo

# Or via journalctl
sudo journalctl -f _COMM=sudo
```

### Cron Job: Daily User Audit Report

```bash
# /etc/cron.daily/user-audit
#!/bin/bash
REPORT="/var/log/user-audit-$(date +%F).txt"

{
  echo "=== User Audit Report: $(date) ==="
  echo ""
  echo "--- Active Human Accounts ---"
  awk -F: '$3 >= 1000 && $7 !~ /nologin|false/ {print $1, "UID:"$3, "Shell:"$7}' /etc/passwd

  echo ""
  echo "--- Sudo Privileges ---"
  grep -r 'ALL' /etc/sudoers /etc/sudoers.d/ 2>/dev/null | grep -v '^#'

  echo ""
  echo "--- Recent Logins (24h) ---"
  last -s "$(date -d '24 hours ago' '+%Y-%m-%d %H:%M')" | head -20

  echo ""
  echo "--- Failed Login Attempts (24h) ---"
  sudo grep 'Failed password' /var/log/auth.log | \
    grep "$(date '+%b %e')" | \
    awk '{print $11}' | sort | uniq -c | sort -rn | head -10
} > "$REPORT"

# Optionally: mail -s "User Audit $(date +%F)" ops@company.com < "$REPORT"
```

---

## 10. Automation at Scale

### Ansible Playbook — Create Standard Accounts

```yaml
# user-management.yml
---
- name: Manage users across production servers
  hosts: all
  become: yes

  vars:
    ops_users:
      - name: john.doe
        comment: "DevOps Engineer - John Doe"
        groups: ["sudo", "docker", "adm"]
        ssh_key: "ssh-ed25519 AAAA...key1... john.doe@company.com"
      - name: jane.smith
        comment: "SRE - Jane Smith"
        groups: ["sudo", "adm"]
        ssh_key: "ssh-ed25519 AAAA...key2... jane.smith@company.com"

    service_users:
      - name: ci-deploy
        comment: "CI/CD Deploy Account"
        groups: ["docker", "deployers"]
        ssh_key: "ssh-ed25519 AAAA...key3... ci@github-actions"

  tasks:
    - name: Create ops user accounts
      user:
        name: "{{ item.name }}"
        comment: "{{ item.comment }}"
        groups: "{{ item.groups }}"
        append: yes
        shell: /bin/bash
        create_home: yes
        state: present
      loop: "{{ ops_users }}"

    - name: Deploy SSH keys for ops users
      authorized_key:
        user: "{{ item.name }}"
        key: "{{ item.ssh_key }}"
        state: present
        exclusive: no   # Don't remove other keys
      loop: "{{ ops_users }}"

    - name: Create service user accounts
      user:
        name: "{{ item.name }}"
        comment: "{{ item.comment }}"
        groups: "{{ item.groups }}"
        append: yes
        shell: /bin/bash
        create_home: yes
        state: present
        password_lock: yes   # No password auth
      loop: "{{ service_users }}"

    - name: Deploy SSH keys for service accounts
      authorized_key:
        user: "{{ item.name }}"
        key: "{{ item.ssh_key }}"
        state: present
        exclusive: yes   # Only this key
      loop: "{{ service_users }}"

    - name: Deploy sudoers policy for ops team
      copy:
        dest: /etc/sudoers.d/10-ops-team
        content: |
          %sudo ALL=(ALL) NOPASSWD: /usr/bin/systemctl *, /usr/bin/journalctl *
        validate: /usr/sbin/visudo -cf %s
        mode: '0440'
```

### Shell Script — Onboard a New Engineer

```bash
#!/bin/bash
# onboard-engineer.sh — Run as root on each production server

set -euo pipefail

USERNAME="$1"
FULLNAME="$2"
SSH_PUBKEY="$3"
GROUPS="${4:-sudo,docker,adm}"

if [[ -z "$USERNAME" || -z "$FULLNAME" || -z "$SSH_PUBKEY" ]]; then
  echo "Usage: $0 <username> <full-name> <ssh-pubkey> [groups]"
  exit 1
fi

echo "[+] Creating account: $USERNAME ($FULLNAME)"
useradd \
  --create-home \
  --shell /bin/bash \
  --comment "$FULLNAME" \
  --groups "$GROUPS" \
  "$USERNAME"

echo "[+] Deploying SSH key"
mkdir -p /home/$USERNAME/.ssh
echo "$SSH_PUBKEY" > /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys

echo "[+] Locking password (key-only auth)"
passwd --lock "$USERNAME"

echo "[+] Setting password aging policy"
chage --maxdays 90 --warndays 14 "$USERNAME"

echo "[+] Done. User $USERNAME created successfully."
echo "    Groups: $(id $USERNAME)"
```

### Shell Script — Offboard an Engineer

```bash
#!/bin/bash
# offboard-engineer.sh — Run as root

set -euo pipefail

USERNAME="$1"
ARCHIVE_DIR="/archive/users"

if [[ -z "$USERNAME" ]]; then
  echo "Usage: $0 <username>"
  exit 1
fi

echo "[+] Offboarding: $USERNAME"

# Kill active sessions
pkill -u "$USERNAME" 2>/dev/null || true

# Lock account immediately
usermod --lock "$USERNAME"
usermod --expiredate 1 "$USERNAME"   # Expire immediately

# Revoke sudo access
rm -f /etc/sudoers.d/*$USERNAME*

# Archive home directory
mkdir -p "$ARCHIVE_DIR"
tar -czf "$ARCHIVE_DIR/$USERNAME-$(date +%F).tar.gz" "/home/$USERNAME"
echo "[+] Home archived to $ARCHIVE_DIR/$USERNAME-$(date +%F).tar.gz"

# Remove account (keep archive)
userdel --remove "$USERNAME"

# Log the action
logger "OFFBOARDED: $USERNAME by $(whoami) on $(date)"
echo "[+] $USERNAME offboarded successfully."
```

---

## 11. Production Hardening Checklist

### Account Policy

```bash
# Disable root login via SSH
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Disable direct root login via console (set to sbin/nologin or require su)
sudo passwd --lock root

# Verify no UID 0 accounts other than root
awk -F: '($3 == 0 && $1 != "root") {print "WARNING: " $1 " has UID 0!"}' /etc/passwd
```

### Find Risky Accounts

```bash
# Accounts with no password (empty password hash)
sudo awk -F: '($2 == "" || $2 == "!!" || $2 == "") {print $1}' /etc/shadow

# Accounts with passwords older than 90 days
sudo awk -F: 'NR>1 {if ($5 != "" && $5 != "99999") {
  days_since_change = int(systime()/86400) - $3;
  if (days_since_change > 90) print $1, "last changed:", $3
}}' /etc/shadow

# Service accounts with interactive shells (should be nologin)
awk -F: '$3 < 1000 && $7 !~ /nologin|false|sync|shutdown|halt/ {print $1, $7}' /etc/passwd

# Users with world-readable home directories
for dir in /home/*/; do
  perms=$(stat -c "%a" "$dir")
  user=$(basename "$dir")
  if [[ "$perms" == *"7" ]] || [[ "$perms" == *"5" ]]; then
    echo "WARNING: $dir is readable by others (perms: $perms)"
  fi
done
```

### Quick Security Scan

```bash
# Run a full user security summary
echo "=== UID 0 accounts ==="
awk -F: '$3==0 {print $1}' /etc/passwd

echo "=== Accounts with no password ==="
sudo awk -F: '$2 == "" || $2 == "!!" {print $1}' /etc/shadow

echo "=== Users with sudo access ==="
grep -r '^[^#].*ALL' /etc/sudoers /etc/sudoers.d/ 2>/dev/null

echo "=== Service accounts with login shells ==="
awk -F: '$3 < 1000 && $7 ~ /bash|sh|zsh/ {print $1, $7}' /etc/passwd

echo "=== SSH authorized_keys locations ==="
find /home /root -name authorized_keys -ls 2>/dev/null

echo "=== sshd_config key settings ==="
grep -E 'PermitRootLogin|PasswordAuthentication|PermitEmptyPasswords' /etc/ssh/sshd_config
```

---

## Quick Reference Card

```
# Create user          useradd -m -s /bin/bash -G sudo username
# Delete user          userdel --remove username
# Lock user            usermod --lock username
# Unlock user          usermod --unlock username
# Add to group         usermod -aG groupname username
# Password aging       chage -l username
# Set expiry           usermod --expiredate YYYY-MM-DD username
# View sudo rights     sudo -l -U username
# Edit sudoers         sudo visudo -f /etc/sudoers.d/custom
# Deploy SSH key       ssh-copy-id -i key.pub user@host
# Audit logins         last | head -20
# Audit failures       lastb | head -20
# Who is logged in     w
# User info            id username
# Group members        getent group groupname
```

---

*Reference: `man useradd`, `man usermod`, `man sudoers`, `man sshd_config`, `man auditd`, `man chage`, `man pam_pwquality`*

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha  
> **Repository:** linux-for-devops / 06-user-management  
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
