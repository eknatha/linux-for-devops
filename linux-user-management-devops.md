# Linux User Management for DevOps / SRE / Platform Engineers 

User management is an important part of Linux system administration. DevOps and SRE engineers often manage multiple users, automate deployments, configure permissions, and enforce security policies on servers.

This guide covers **essential Linux user and group management concepts and commands** used in production environments.

---

# 1. Understanding Users in Linux 

A **user** represents an account that can log in to the system and run processes.

Types of users:

| Type | Description |
|---|---|
| Root user | Superuser with full system access |
| System users | Used by services and applications |
| Regular users | Human users who log in to the system |

The root user has **UID 0** and unrestricted privileges.

---

# 2. Important User Files

Linux stores user information in several system files.

| File | Purpose |
|---|---|
| `/etc/passwd` | User account information |
| `/etc/shadow` | Encrypted passwords |
| `/etc/group` | Group definitions |
| `/etc/sudoers` | Sudo permissions |

Example entry from `/etc/passwd`:

```
john:x:1001:1001:John Doe:/home/john:/bin/bash
```

Fields:

| Field | Description |
|---|---|
| Username | Login name |
| Password placeholder | Stored in `/etc/shadow` |
| UID | User ID |
| GID | Primary group |
| Comment | Description |
| Home directory | User home |
| Shell | Default shell |

---

# 3. Create a User

Create a new user:

```bash
sudo useradd username
```

Create a user with a home directory:

```bash
sudo useradd -m username
```

Set password:

```bash
sudo passwd username
```

---

# 4. Delete a User

Remove a user account:

```bash
sudo userdel username
```

Remove user and home directory:

```bash
sudo userdel -r username
```

---

# 5. Modify a User

Change username:

```bash
sudo usermod -l newname oldname
```

Change home directory:

```bash
sudo usermod -d /new/home username
```

Change default shell:

```bash
sudo usermod -s /bin/bash username
```

---

# 6. Group Management

Groups allow multiple users to share permissions.

## Create a group

```bash
sudo groupadd developers
```

---

## Delete a group

```bash
sudo groupdel developers
```

---

## Add user to group

```bash
sudo usermod -aG developers username
```

Explanation:

| Flag | Meaning |
|---|---|
| `-a` | Append |
| `-G` | Secondary group |

---

# 7. View User Information 

Display current user:

```bash
whoami
```

---

Show user ID and group memberships:

```bash
id username
```

Example:

```
uid=1001(john) gid=1001(john) groups=1001(john),1002(developers)
```

---

List logged-in users:

```bash
who
```

---

# 8. Switch Users

Switch to another user:

```bash
su username
```

Switch to root:

```bash
su -
```

---

# 9. Sudo Privileges

`sudo` allows users to run commands with elevated privileges.

Example:

```bash
sudo systemctl restart nginx
```

---

Add user to sudo group:

```bash
sudo usermod -aG sudo username
```

On some systems:

```bash
sudo usermod -aG wheel username
```

---

# 10. Password Management

Change password:

```bash
passwd
```

Change password for another user:

```bash
sudo passwd username
```

Lock a user account:

```bash
sudo passwd -l username
```

Unlock account:

```bash
sudo passwd -u username
```

---

# 11. User Login History

View login history:

```bash
last
```

Example output:

```
john  pts/0  192.168.1.10  Fri Mar 15 10:00 - 11:00
```

---

Check failed login attempts:

```bash
grep "Failed password" /var/log/auth.log
```

---

# 12. File Ownership

Files are owned by users and groups.

Check ownership:

```bash
ls -l
```

Example:

```
-rw-r--r-- 1 john developers 1200 Mar 12 file.txt
```

---

Change file owner:

```bash
sudo chown username file.txt
```

Change owner and group:

```bash
sudo chown username:developers file.txt
```

---

# 13. Permission Management

Change file permissions:

```bash
chmod 755 script.sh
```

Permission structure:

```
Owner  Group  Others
rwx    r-x    r-x
```

---

# 14. DevOps Use Cases

## Create deployment user

```bash
sudo useradd -m deploy
```

---

## Add deploy user to docker group

```bash
sudo usermod -aG docker deploy
```

---

## Grant sudo access

```bash
sudo usermod -aG sudo deploy
```

---

## Check running user in scripts

```bash
whoami
```

---

# 15. Useful User Management Commands

| Command | Purpose |
|---|---|
| `useradd` | Create user |
| `userdel` | Delete user |
| `usermod` | Modify user |
| `groupadd` | Create group |
| `groupdel` | Delete group |
| `passwd` | Manage passwords |
| `id` | Show user identity |
| `whoami` | Show current user |
| `who` | Show logged-in users |
| `sudo` | Run command as root |

---

# Best Practices for DevOps Engineers

- Use **least privilege access**
- Avoid using root directly
- Use **groups for permission management**
- Rotate passwords and credentials
- Monitor login activity

---

# Conclusion

User management helps engineers:

- Control system access
- Manage permissions securely
- Automate deployments
- Maintain secure infrastructure
- Monitor system usage

Understanding Linux user management improves **security, access control, and operational efficiency**.

---

⭐ If you found this useful, consider **starring the repository**. 
