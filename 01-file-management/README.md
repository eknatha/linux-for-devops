# 01 - Linux File Management for DevOps

> **Production-grade Linux file management** — covering navigation, permissions, ownership, searching, archiving, text processing, symbolic links, and file system operations for real-world DevOps environments.

---
![Eknatha](https://img.shields.io/badge/Eknatha-4EAA25?style=flat&logo=gnu-bash&logoColor=white)

## 📁 Module Structure

```
01-file-management/
├── README.md                          ← You are here
├── file-management.md                 ← Deep-dive reference guide
├── scripts/
│   ├── file-audit.sh                  ← Audit permissions, owners, and SUID files
│   ├── bulk-rename.sh                 ← Safe bulk rename with dry-run
│   ├── archive-manager.sh             ← Create, extract, and verify archives
│   └── find-cleanup.sh                ← Find and remove stale files safely
└── examples/
    ├── find-examples.sh               ← Production find command patterns
    ├── awk-examples.sh                ← AWK for log parsing and reporting
    └── sed-examples.sh                ← sed for config file manipulation
```

---

## 🚀 Quick Start

### Navigate and inspect files

```bash
# List with details, hidden files, human-readable sizes
ls -lah

# Show directory tree (2 levels deep)
tree -L 2 /opt/app

# Find a file by name
find /etc -name "nginx.conf" 2>/dev/null

# Show file type and encoding
file /opt/app/config.yaml
```

### Check permissions and ownership

```bash
# Long listing with permissions
ls -la /opt/app/

# Show octal permissions
stat -c "%a %U:%G %n" /opt/app/*

# Find files with dangerous permissions
sudo find / -perm -4000 -type f 2>/dev/null   # SUID files
sudo find / -perm -0002 -type f 2>/dev/null   # World-writable files
```

### Quick text processing

```bash
# Search logs for errors
grep -iE "error|fail|crit" /var/log/app.log | tail -20

# Count requests per HTTP status code
awk '{print $9}' /var/log/nginx/access.log | sort | uniq -c | sort -rn

# Replace a value in a config file
sed -i 's/localhost/10.0.1.5/g' /etc/app/config.conf
```

---

## 📚 Topics Covered

| Topic | Description |
|---|---|
| [Navigation](#) | ls, cd, pwd, tree — directory traversal |
| [File Operations](#) | cp, mv, rm, touch, mkdir — create and manage files |
| [Permissions & Ownership](#) | chmod, chown, chgrp, umask, ACLs |
| [Searching](#) | find, locate, which, whereis — find anything |
| [Text Processing](#) | grep, awk, sed, cut, sort, uniq |
| [Archiving](#) | tar, gzip, bzip2, zip — compress and extract |
| [Links](#) | hard links, symbolic links, readlink |
| [File Comparison](#) | diff, comm, md5sum, sha256sum |
| [Special Files](#) | /proc, /dev, pipes, redirects |
| [Production Patterns](#) | Log rotation, config deployment, audit trails |

---

## ⚡ Production File Management Checklist

- [ ] Set `umask 027` in service account profiles — new files default to `640`
- [ ] Never use `chmod 777` — use group permissions and ACLs instead
- [ ] Always use `-i` flag with `rm` in scripts, or test with `find ... -print` first
- [ ] Set correct ownership on app directories — service account, not root
- [ ] Use `rsync --dry-run` before any bulk file operation
- [ ] Verify archive integrity with `tar -tvf` after creation
- [ ] Use `find -mtime` to automate cleanup of old logs and temp files
- [ ] Prefer `cp -p` to preserve timestamps and permissions when copying
- [ ] Use `ln -s` for config files that need to be in multiple locations
- [ ] Always redirect both stdout and stderr when logging: `> file 2>&1`

---

## 🛠️ Essential File Commands — Quick Reference

```bash
# Navigation
ls -lah                            List with details + hidden files
ls -lah --sort=size                Sort by size (largest first)
pwd                                Print current directory
cd -                               Go to previous directory
tree -L 2 -a /opt                  Tree view, 2 levels, show hidden

# File operations
cp -rp src/ dest/                  Copy recursively, preserve permissions
mv -i old new                      Move (prompt before overwrite)
rm -rf dir/                        Remove directory (careful!)
mkdir -p /opt/app/{bin,conf,logs}  Create nested directories at once
touch /opt/app/logs/.gitkeep       Create empty file

# Permissions
chmod 750 script.sh                rwxr-x--- (owner+group, not others)
chmod -R 640 /opt/app/conf/        Recursively set permissions
chown -R appuser:appgroup /opt/app/ Change owner and group
umask 027                          Set default: files=640, dirs=750

# Find
find /var/log -name "*.log" -mtime +30 -delete   Delete logs older than 30 days
find / -user root -perm -4000 2>/dev/null        Find all SUID binaries
find /opt -empty -type f -delete                 Remove empty files

# Grep
grep -rn "password" /etc/ --include="*.conf"    Search all .conf files
grep -v "^#\|^$" /etc/nginx/nginx.conf          Show config without comments
grep -c "ERROR" /var/log/app.log               Count error lines

# Archive
tar -czf backup-$(date +%F).tar.gz /opt/app/   Create compressed archive
tar -tvf backup.tar.gz                          List archive contents
tar -xzf backup.tar.gz -C /restore/            Extract to specific dir

# Text processing
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10
sed -n '100,200p' large-file.log               Print lines 100-200
cut -d: -f1,3 /etc/passwd                      Extract fields 1 and 3
```

---

## 🔗 See Also

- [file-management.md] — full reference with all commands and production examples
- `man ls`, `man find`, `man chmod`, `man tar`, `man grep`, `man awk`, `man sed`
- [GNU Coreutils documentation](https://www.gnu.org/software/coreutils/manual/)
- [Advanced Bash Scripting Guide](https://tldp.org/LDP/abs/html/)

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha Reddy Puli
> **Repository:** linux-for-devops / 01-file-management
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
