# Linux File Management for DevOps / SRE / Platform Engineers  

File management is a **core skill for DevOps, SRE, and Platform Engineers**. Most production systems run on Linux, and engineers frequently interact with logs, configuration files, deployment artifacts, and system directories. 

This guide covers **essential file management commands and concepts every DevOps engineer should know**. 

---

# 1. Basic File & Directory Operations  

These commands are used daily when navigating servers.

## List files  

```bash
ls
ls -l
ls -la
ls -lh
```

| Flag | Meaning |
|-----|------|
| `-l` | Long listing format |
| `-a` | Show hidden files |
| `-h` | Human readable sizes |

---

## Navigate directories 

```bash
pwd
cd /var/log
cd ..
cd ~
```

| Command | Description |
|---|---|
| `pwd` | Print current directory |
| `cd` | Change directory |

---

## Create files and directories

```bash
touch file.txt
mkdir logs
mkdir -p project/src/config
```

| Command | Description |
|---|---|
| `touch` | Create empty file |
| `mkdir` | Create directory |
| `-p` | Create nested directories |

---

## Copy files

```bash
cp file.txt backup.txt
cp -r folder backup-folder
```

---

## Move / Rename files

```bash
mv old.txt new.txt
mv file.txt /tmp/
```

---

## Delete files

```bash
rm file.txt
rm -r folder
rm -rf folder
```

⚠️ Be careful with:

```bash
rm -rf
```

This **force deletes recursively** and can remove critical files.

---

# 2. Reading Files and Logs

Log analysis is a daily task for DevOps engineers.

## View entire file

```bash
cat file.txt
```

---

## View large files safely

```bash
less file.txt
```

Navigation in `less`:

| Key | Action |
|---|---|
| `Space` | Next page |
| `b` | Previous page |
| `q` | Quit |

---

## View beginning of file

```bash
head file.txt
head -n 50 file.txt
```

---

## View end of file

```bash
tail file.txt
tail -n 100 file.txt
```

---

## Monitor logs in real-time

```bash
tail -f /var/log/nginx/access.log
```

Very useful for **debugging running services**.

---

# 3. Searching Files

## Find files

```bash
find /var/log -name "*.log"
```

Example:

```bash
find /etc -name nginx.conf
```

---

## Search text inside files

```bash
grep "ERROR" app.log
```

Useful options:

```bash
grep -i error log.txt
grep -r "database" .
grep -n timeout config.yaml
```

| Flag | Meaning |
|---|---|
| `-i` | Case insensitive |
| `-r` | Recursive search |
| `-n` | Show line numbers |

---

# 4. File Permissions

Linux permissions control **who can read, write, or execute files**.

Check permissions:

```bash
ls -l
```

Example output:

```
-rw-r--r--
```

| Section | Meaning |
|---|---|
| Owner | First 3 bits |
| Group | Next 3 bits |
| Others | Last 3 bits |

---

## Change permissions

```bash
chmod 755 script.sh
chmod +x deploy.sh
```

Example:

```
755 = rwx r-x r-x
```

---

## Change ownership

```bash
chown user:group file.txt
```

Example:

```bash
chown ubuntu:ubuntu app.log
```

---

# 5. Disk Usage

Monitoring disk space is critical in production.

## Check disk space

```bash
df -h
```

---

## Check folder size

```bash
du -sh /var/log
```

---

## Find large files

```bash
du -ah / | sort -rh | head -20
```

Useful during **disk pressure incidents**.

---

# 6. Compression & Archiving

Used for **backups, log storage, and artifact packaging**.

## Create archive

```bash
tar -cvf archive.tar folder/
```

---

## Extract archive

```bash
tar -xvf archive.tar
```

---

## Compress archive

```bash
tar -czvf backup.tar.gz folder/
```

---

## Extract compressed archive

```bash
tar -xzvf backup.tar.gz
```

---

# 7. File Transfer Between Servers

Common in deployments and backups.

## SCP

```bash
scp file.txt user@server:/home/user
```

Example:

```bash
scp backup.tar.gz ubuntu@10.0.0.5:/backup
```

---

## Rsync (Preferred)

```bash
rsync -avz folder/ user@server:/backup/
```

Benefits:

- Efficient
- Incremental
- Faster for large data

---

# 8. Redirection & Pipes

Used heavily in **automation and scripting**.

## Redirect output

```bash
echo "hello" > file.txt
```

Append output:

```bash
echo "new line" >> file.txt
```

---

## Pipes

```bash
cat log.txt | grep ERROR
```

Example:

```bash
ps aux | grep nginx
```

---

# 9. File Links

Linux supports **two types of links**.

## Hard link

```bash
ln file.txt link.txt
```

---

## Soft link (symlink)

```bash
ln -s /var/log/nginx/access.log access.log
```

Used in **deployment versioning**.

Example structure:

```
releases/
current -> releases/v2
```

---

# 10. Important Linux Directories

| Directory | Purpose |
|---|---|
| `/etc` | System configuration |
| `/var/log` | Logs |
| `/var/lib` | Application state |
| `/usr/bin` | Executables |
| `/tmp` | Temporary files |
| `/home` | User directories |
| `/opt` | Optional software |

Example:

```
/etc/nginx/nginx.conf
```

---

# 11. Log Rotation

Log rotation prevents logs from filling disk space.

Config file:

```
/etc/logrotate.conf
```

Example:

```conf
/var/log/app.log {
    daily
    rotate 7
    compress
}
```

Meaning:

- Rotate logs daily
- Keep 7 backups
- Compress old logs

---

# 12. Useful CLI Shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl + r` | Search command history |
| `Ctrl + a` | Move to start of line |
| `Ctrl + e` | Move to end of line |
| `Ctrl + u` | Clear command line |

---

# 13. Real DevOps Use Cases

## Debug application errors

```bash
grep ERROR /var/log/app.log
```

---

## Monitor service logs

```bash
tail -f /var/log/nginx/error.log
```

---

## Check disk issues

```bash
df -h
du -sh *
```

---

## Find configuration files

```bash
find /etc -name "*.conf"
```

---

# 14. Advanced Text Processing 

Powerful tools for log analysis. 

```
awk
sed
cut
sort
uniq
xargs
```

Example: top IP addresses from logs

```bash
cat access.log | awk '{print $1}' | sort | uniq -c
```

---

# Conclusion 

File management skills help DevOps engineers:

- Investigate production issues quickly
- Manage logs and configurations
- Monitor disk usage
- Transfer and archive artifacts
- Automate system operations

Mastering these commands significantly improves **debugging speed and operational efficiency**. 

--- 

⭐ If you found this useful, consider **starring the repository**. 
