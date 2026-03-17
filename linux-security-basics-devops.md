# Linux Security Baseline for SRE / DevOps / Platform Engineers

A practical Linux security baseline for engineers managing **Red Hat Enterprise Linux (RHEL)** and RHEL-based systems such as **Rocky Linux**, **AlmaLinux**, and **CentOS Stream**.

This document provides essential **host-level security practices** used in production infrastructure environments.

---

## Table of Contents

- [Overview](#overview)
- [Security Principles](#security-principles)
- [User & Access Management](#user--access-management)
- [SSH Hardening & Restrictions](#ssh-hardening--restrictions)
- [Firewall Configuration](#firewall-configuration)
- [File Permissions & Ownership](#file-permissions--ownership)
- [SELinux Security](#selinux-security)
- [Package & Patch Management](#package--patch-management)
- [Logging & Monitoring](#logging--monitoring)
- [Auditing](#auditing)
- [System Hardening](#system-hardening)
- [Security Checklist](#security-checklist)

---

# Overview

Linux servers power most modern infrastructure platforms.  
SRE, DevOps, and Platform Engineers must ensure systems are **secure, reliable, and auditable**.

This guide provides baseline practices for:

- Secure access control
- SSH restrictions
- Network security
- System hardening
- Monitoring and auditing

---

# Security Principles

## Least Privilege

Users and services should have only the permissions required to perform their tasks.

## Defense in Depth

Multiple layers of protection should exist:

- SSH restrictions
- Firewall rules
- SELinux policies
- Monitoring
- Audit logging

## Auditability

All administrative actions must be logged and traceable.

---

# User & Access Management

## Create User

```bash
sudo useradd devops
sudo passwd devops
```

## Grant Sudo Access

```bash
sudo usermod -aG wheel devops
```

Verify sudo access:

```bash
sudo -l
```

## List Users

```bash
cat /etc/passwd
```

## Check Logged-in Users

```bash
who
w
```

## Remove User

```bash
sudo userdel username
```

---

# SSH Hardening & Restrictions

SSH is the primary remote access method and must be secured.

SSH configuration file:

```
/etc/ssh/sshd_config
```

## Disable Root Login

```
PermitRootLogin no
```

## Disable Password Authentication

```
PasswordAuthentication no
```

## Allow Specific Users

```
AllowUsers devops sre admin
```

## Allow Specific Groups

```
AllowGroups sshusers
```

## Limit Login Attempts

```
MaxAuthTries 3
LoginGraceTime 30
```

## Disable Empty Passwords

```
PermitEmptyPasswords no
```

## Change Default SSH Port (Optional)

```
Port 2222
```

Restart SSH service:

```bash
sudo systemctl restart sshd
```

---

# SSH Key Authentication

Generate SSH key:

```bash
ssh-keygen -t rsa -b 4096
```

Copy key to server:

```bash
ssh-copy-id user@server
```

---

# Firewall Configuration (firewalld)

Check firewall status:

```bash
systemctl status firewalld
```

Enable firewall:

```bash
sudo systemctl enable --now firewalld
```

List firewall rules:

```bash
firewall-cmd --list-all
```

Allow HTTP service:

```bash
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload
```

Allow custom port:

```bash
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

---

# Restrict SSH by IP (Optional)

Example allowing access from a specific IP:

```bash
sudo firewall-cmd --permanent \
--add-rich-rule='rule family="ipv4" source address="10.0.0.5" port protocol="tcp" port="22" accept'

sudo firewall-cmd --reload
```

---

# File Permissions & Ownership

View file permissions:

```bash
ls -l
```

Example output:

```
-rwxr-xr-- 1 user group script.sh
```

| Permission | Meaning |
|------------|--------|
| r | Read |
| w | Write |
| x | Execute |

Change permissions:

```bash
chmod 755 script.sh
```

Change ownership:

```bash
chown user:group file.txt
```

Avoid using:

```
chmod 777
```

---

# SELinux Security

Check SELinux status:

```bash
getenforce
```

Detailed status:

```bash
sestatus
```

Modes:

| Mode | Description |
|-----|-------------|
| Enforcing | Policies enforced |
| Permissive | Violations logged |
| Disabled | SELinux disabled |

Temporary permissive mode:

```bash
sudo setenforce 0
```

Configuration file:

```
/etc/selinux/config
```

Recommended production setting:

```
SELINUX=enforcing
```

---

# Package & Patch Management

Update system packages:

```bash
sudo dnf update
```

List installed packages:

```bash
rpm -qa
```

Verify package integrity:

```bash
rpm -V package_name
```

Best practices:

- Apply updates regularly
- Monitor security advisories
- Remove unused packages

---

# Logging & Monitoring

Linux logs are stored in:

```
/var/log/
```

Important logs:

| Log File | Description |
|----------|-------------|
| /var/log/messages | System logs |
| /var/log/secure | Authentication logs |
| /var/log/audit/audit.log | Security audit logs |

Monitor logs:

```bash
tail -f /var/log/messages
```

---

# Auditing

Install audit framework:

```bash
sudo dnf install audit
```

Enable service:

```bash
sudo systemctl enable --now auditd
```

Audit logs location:

```
/var/log/audit/audit.log
```

Search login events:

```bash
ausearch -m USER_LOGIN
```

---

# System Hardening

Check running services:

```bash
systemctl list-units --type=service
```

Check open ports:

```bash
ss -tulnp
```

Disable unused services:

```bash
sudo systemctl disable service-name
```

---

# Security Checklist

## Access

- Remove unused users
- Restrict sudo privileges
- Disable root SSH login

## SSH

- Use SSH keys
- Disable password authentication
- Restrict SSH users
- Limit login attempts

## Network

- Enable firewall
- Close unused ports
- Restrict SSH access

## System

- Enable SELinux
- Apply security updates
- Remove unnecessary packages

## Monitoring

- Monitor authentication logs
- Enable audit logging
- Review login activity

---

# Recommended Security Tools

Common tools used in DevOps and platform environments:

- Prometheus
- Grafana
- ELK Stack
- Loki
- Falco
- OpenSCAP

---

# Contribution

This document can be extended by platform teams with:

- Security automation
- Hardening scripts
- Compliance checks
- Monitoring integrations 
