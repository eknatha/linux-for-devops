# Linux File Management — Production Reference Guide

> Comprehensive reference for file navigation, permissions, ownership, searching, text processing, archiving, links, and production file management patterns on Linux servers.

![Eknatha](https://img.shields.io/badge/Eknatha-4EAA25?style=flat&logo=gnu-bash&logoColor=white)

---

## Table of Contents

1. [Navigation and Directory Operations](#1-navigation-and-directory-operations)
2. [File Operations — Create, Copy, Move, Delete](#2-file-operations--create-copy-move-delete)
3. [Permissions and Ownership](#3-permissions-and-ownership)
4. [Searching — find, locate, grep](#4-searching--find-locate-grep)
5. [Text Processing — grep, awk, sed, cut](#5-text-processing--grep-awk-sed-cut)
6. [Archiving and Compression](#6-archiving-and-compression)
7. [Symbolic and Hard Links](#7-symbolic-and-hard-links)
8. [File Comparison and Verification](#8-file-comparison-and-verification)
9. [Redirects, Pipes, and Special Files](#9-redirects-pipes-and-special-files)
10. [ACLs — Fine-Grained Access Control](#10-acls--fine-grained-access-control)
11. [Production File Management Patterns](#11-production-file-management-patterns)
12. [Quick Reference Card](#12-quick-reference-card)

---

## 1. Navigation and Directory Operations

### Basic Navigation

```bash
# Show current directory
pwd

# Change directory
cd /opt/app           # Absolute path
cd ..                 # One level up
cd -                  # Toggle between last two directories
cd ~                  # Go to home directory
cd ~username          # Go to another user's home

# List files
ls                    # Basic listing
ls -l                 # Long format (permissions, owner, size, date)
ls -a                 # Include hidden files (starting with .)
ls -lah               # Long format + hidden + human-readable sizes
ls -lS                # Sort by size (largest first)
ls -lt                # Sort by modification time (newest first)
ls -ltr               # Sort by time, oldest first (reversed)
ls -ld /opt/app       # List directory itself, not its contents
ls --color=auto       # Coloured output

# Tree view (install: sudo apt install tree)
tree /opt/app                    # Full tree
tree -L 2 /opt/app               # Limit to 2 levels deep
tree -a /opt/app                 # Include hidden files
tree -d /opt/app                 # Directories only
tree -sh /opt/app                # Show sizes in human-readable format
tree -f /opt/app                 # Show full paths
```

### Directory Operations

```bash
# Create directories
mkdir mydir
mkdir -p /opt/app/conf/ssl          # Create full path, no error if exists
mkdir -p /opt/app/{bin,conf,logs,data,tmp}  # Create multiple at once
mkdir -m 750 /opt/app/secure        # Create with specific permissions

# Remove directories
rmdir emptydir                      # Remove empty directory only
rm -rf /tmp/build-temp/             # Remove recursively (CAREFUL)
rm -ri /tmp/old-files/              # Interactive — prompts for each file

# Directory info
du -sh /opt/app/                    # Total size of directory
du -sh /var/log/* | sort -rh        # Sizes of subdirs, sorted largest first
du -sh --exclude=*.log /opt/app/    # Exclude log files from size count
```

---

## 2. File Operations — Create, Copy, Move, Delete

### Creating Files

```bash
# Create empty file or update timestamp
touch config.yaml
touch -t 202401151200 file.txt      # Set specific timestamp

# Create file with content
echo "server_name=prod-01" > /opt/app/conf/server.conf
cat > /opt/app/conf/app.conf << 'EOF'
[server]
host = 0.0.0.0
port = 8080
workers = 4
EOF

# Create file of specific size (for testing)
dd if=/dev/zero of=/tmp/test-1G.bin bs=1M count=1024
fallocate -l 1G /tmp/test-1G.bin    # Faster than dd
```

### Copying Files

```bash
# Basic copy
cp source.txt dest.txt

# Copy preserving permissions, timestamps, ownership
cp -p source.txt dest.txt
cp -a source/ dest/                 # Archive mode: -p + recursive + links

# Copy recursively
cp -r src-dir/ dest-dir/

# Copy with verbose output (shows each file)
cp -rv src/ dest/

# Production-safe copy — show progress for large files
rsync -av --progress source/ dest/

# Copy only if source is newer
cp -u source.txt dest.txt

# Copy multiple files to a directory
cp file1.txt file2.txt file3.txt /opt/app/conf/

# Copy and follow symbolic links
cp -L symlink dest/
```

### Moving and Renaming

```bash
# Rename a file
mv old-name.txt new-name.txt

# Move a file to a directory
mv config.txt /opt/app/conf/

# Move with backup (keeps original as file.txt~)
mv --backup=numbered file.txt /opt/app/conf/

# Move multiple files
mv *.conf /opt/app/conf/

# Interactive move (prompt before overwrite)
mv -i source.txt dest.txt

# Rename all .txt to .bak in current directory
for f in *.txt; do mv "$f" "${f%.txt}.bak"; done
```

### Deleting Files Safely

```bash
# Remove a file
rm file.txt

# Interactive removal (prompts)
rm -i file.txt

# Remove recursively (directories)
rm -rf old-directory/

# PRODUCTION SAFE: always test with find first
find /tmp -name "*.tmp" -mtime +7 -print       # Preview
find /tmp -name "*.tmp" -mtime +7 -delete      # Then delete

# Move to trash instead of permanent delete (requires trash-cli)
# sudo apt install trash-cli
trash-put file.txt
trash-list                         # See trashed files
trash-restore                      # Restore
trash-empty                        # Permanently delete trash

# Secure delete (overwrite before removing)
shred -u sensitive-data.txt
shred -n 3 -u sensitive.txt        # 3 overwrite passes
```

---

## 3. Permissions and Ownership

### Understanding Permissions

```
-rwxr-x---  1  appuser  appgroup  4096  Jan 15 09:00  script.sh
│├─┤├─┤├─┤     ├─────┤  ├──────┤
│ │  │  │       │        └─ Group
│ │  │  │       └─────── Owner (user)
│ │  │  └─────────────── Other permissions (---)
│ │  └────────────────── Group permissions (r-x)
│ └───────────────────── Owner permissions (rwx)
└─────────────────────── File type (- = file, d = dir, l = symlink)

r = read  (4)
w = write (2)
x = execute (1)
```

### chmod — Change Permissions

```bash
# Symbolic mode
chmod u+x script.sh          # Add execute for owner
chmod g-w file.txt           # Remove write from group
chmod o= file.txt            # Remove all permissions from others
chmod a+r file.txt           # Add read for all (a = all)
chmod ug+rw file.txt         # Add read+write for owner and group

# Octal mode (most common in production)
chmod 755 script.sh          # rwxr-xr-x  — public executable
chmod 750 script.sh          # rwxr-x---  — owner+group, not others
chmod 644 config.yaml        # rw-r--r--  — public readable config
chmod 640 config.yaml        # rw-r-----  — private config (group read)
chmod 600 private.key        # rw-------  — private key, owner only
chmod 700 /opt/app/data/     # rwx------  — private directory

# Recursive
chmod -R 750 /opt/app/bin/
chmod -R 640 /opt/app/conf/

# Common production permission table:
# 700 — private directories (service data, SSH keys)
# 750 — app bin/executable directories (owner+group access)
# 755 — public directories (web root, /usr/local/bin)
# 600 — secret files (private keys, credential files)
# 640 — app config files (owner writes, group reads)
# 644 — public config/data files
# 664 — shared files where group needs to write
```

### Special Permission Bits

```bash
# SUID (4) — execute as file owner (e.g., /usr/bin/passwd)
chmod 4755 executable         # rwsr-xr-x
chmod u+s  executable

# SGID (2) on file — execute as group owner
chmod 2755 executable         # rwxr-sr-x

# SGID (2) on directory — new files inherit directory group
chmod 2775 /opt/shared/       # rwxrwsr-x  ← all new files get shared group
mkdir -p /opt/releases && chmod 2775 /opt/releases

# Sticky bit (1) on directory — only owner can delete their files (/tmp)
chmod 1777 /tmp               # rwxrwxrwt
chmod +t /opt/shared/

# Find SUID files (security audit)
sudo find / -perm -4000 -type f 2>/dev/null
# Find SGID files
sudo find / -perm -2000 -type f 2>/dev/null
# Find world-writable files
sudo find / -perm -0002 -type f -not -path '/proc/*' 2>/dev/null
```

### chown and chgrp — Change Ownership

```bash
# Change owner
chown appuser file.txt
chown appuser:appgroup file.txt   # Change both owner and group
chown :appgroup file.txt          # Change only group

# Recursive
chown -R appuser:appgroup /opt/app/
chown -R www-data:www-data /var/www/

# Change only group
chgrp appgroup file.txt
chgrp -R appgroup /opt/app/

# Preserve ownership when copying (use -a or -p)
cp -a /opt/app/ /backup/app/

# Production pattern: set up app directory ownership
sudo useradd --system --no-create-home --shell /usr/sbin/nologin appuser
sudo mkdir -p /opt/app/{bin,conf,data,logs}
sudo chown -R appuser:appgroup /opt/app/data /opt/app/logs
sudo chown root:appgroup /opt/app/conf
sudo chmod 750 /opt/app/conf          # Group can read config, not write
```

### umask — Default Permission Mask

```bash
# View current umask
umask                 # Shows as e.g., 0022
umask -S              # Shows as symbolic: u=rwx,g=rx,o=rx

# How umask works:
# Files start at 666 (rw-rw-rw-), dirs at 777 (rwxrwxrwx)
# umask subtracts from those defaults
# umask 022 → files: 666-022=644, dirs: 777-022=755
# umask 027 → files: 666-027=640, dirs: 777-027=750 (production recommended)
# umask 077 → files: 666-077=600, dirs: 777-077=700 (maximum privacy)

# Set umask (current session)
umask 027

# Set permanently for a service account
echo "umask 027" >> /home/appuser/.bashrc
echo "umask 027" >> /etc/profile.d/production.sh

# Set umask in systemd service unit
# [Service]
# UMask=027
```

---

## 4. Searching — find, locate, grep

### find — The Production Workhorse

```bash
# Find by name
find /etc -name "nginx.conf"
find /var/log -name "*.log"
find /opt -name "*.conf" -o -name "*.yaml"   # OR condition

# Find by type
find /opt/app -type f          # Files only
find /opt/app -type d          # Directories only
find /opt/app -type l          # Symbolic links only

# Find by size
find / -size +100M -type f 2>/dev/null             # Larger than 100MB
find / -size +1G -type f 2>/dev/null               # Larger than 1GB
find /var/log -size +50M -name "*.log" 2>/dev/null

# Find by modification time
find /var/log -mtime +30           # Modified more than 30 days ago
find /var/log -mtime -1            # Modified in the last 24 hours
find /tmp -mmin +60                # Modified more than 60 minutes ago
find /opt -newer /opt/app/release  # Newer than a reference file

# Find by permissions
find / -perm 777 -type f 2>/dev/null         # Exactly 777
find / -perm -o+w -type f 2>/dev/null        # Has world-write bit
find / -perm /4000 -type f 2>/dev/null       # Has SUID bit

# Find by owner
find /opt -user appuser
find /opt -group appgroup
find / -nouser 2>/dev/null        # Files with no valid owner
find / -nogroup 2>/dev/null       # Files with no valid group

# Find and execute actions
find /var/log -name "*.log" -mtime +30 -delete              # Delete old logs
find /tmp -name "*.tmp" -mtime +7 -exec rm -f {} \;         # Execute rm
find /opt -name "*.conf" -exec grep -l "localhost" {} \;    # Find configs with localhost
find /opt -name "*.sh" -exec chmod +x {} \;                  # Make all .sh executable

# Find with exclusions
find /var -name "*.log" -not -path "*/nginx/*"
find / -name "*.conf" -not \( -path '/proc/*' -o -path '/sys/*' \)

# Find empty files and directories
find /opt -empty -type f          # Empty files
find /opt -empty -type d          # Empty directories

# Production: list files with their sizes and timestamps
find /var/log -type f -printf "%T+ %10s %p\n" 2>/dev/null | sort -r | head -20
```

### locate — Fast File Search

```bash
# Update database (run daily via cron)
sudo updatedb

# Search
locate nginx.conf
locate "*.conf" | grep /etc/

# Case-insensitive
locate -i nginxconf

# Count matches
locate -c nginx

# Show only existing files (database may be stale)
locate -e nginx.conf
```

### which, whereis, type

```bash
# Find executable in PATH
which python3
which -a python3          # Show all matches in PATH

# Find binary, source, and man page
whereis nginx
whereis -b nginx          # Binary only

# Shell built-in or external
type ls                   # ls is aliased to `ls --color=auto'
type cd                   # cd is a shell builtin
type -a python3           # Show all matches including aliases
```

---

## 5. Text Processing — grep, awk, sed, cut

### grep — Search Text

```bash
# Basic search
grep "error" /var/log/app.log
grep -i "ERROR" /var/log/app.log       # Case-insensitive
grep -n "error" app.log                # Show line numbers
grep -c "error" app.log                # Count matching lines
grep -l "error" /var/log/*.log         # List files with matches
grep -v "DEBUG" app.log                # Invert — show non-matching lines

# Extended regex
grep -E "error|fail|crit" app.log
grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2}" app.log    # Lines starting with date
grep -E "(GET|POST) /api/" access.log              # HTTP methods

# Recursive search
grep -r "database_password" /etc/          # Search all files
grep -rn "localhost" /etc/ --include="*.conf"  # Only .conf files
grep -rl "TODO" /opt/app/                  # List files only

# Context lines
grep -A 3 "error" app.log         # 3 lines After match
grep -B 3 "error" app.log         # 3 lines Before match
grep -C 3 "error" app.log         # 3 lines Context (before + after)

# Production: find errors in last hour's logs
grep "$(date '+%Y-%m-%d %H')" /var/log/app.log | grep -iE "error|fail"

# Count errors by type
grep -oE "(ERROR|WARN|CRIT)" /var/log/app.log | sort | uniq -c | sort -rn
```

### awk — Data Extraction and Reporting

```bash
# Print specific column (fields split by whitespace by default)
awk '{print $1}' access.log                # First column (IP)
awk '{print $1, $7}' access.log            # First and seventh column

# Field separator
awk -F: '{print $1}' /etc/passwd           # Username from /etc/passwd
awk -F, '{print $2}' data.csv              # Second column from CSV
awk -F'\t' '{print $3}' data.tsv           # Tab-separated

# Conditional printing
awk '$9 >= 500 {print $0}' access.log      # HTTP 5xx responses
awk '$NF > 1.0 {print $0}' access.log      # Response time > 1 second
awk 'NR > 10 && NR < 20 {print}' file      # Lines 11-19

# Calculations
awk '{sum += $10} END {print "Total bytes:", sum}' access.log
awk '{sum += $NF} END {print "Average:", sum/NR}' response-times.log

# Count occurrences
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10

# Production: top 10 IPs by request count
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -10

# Production: HTTP status code breakdown
awk '{print $9}' /var/log/nginx/access.log | sort | uniq -c | sort -rn

# Production: requests per minute
awk '{print $4}' access.log | cut -d: -f1-3 | sed 's/\[//' | \
  sort | uniq -c | tail -20

# Production: parse key=value config
awk -F= '/^[^#]/ {gsub(/[[:space:]]/, "", $1); gsub(/[[:space:]]/, "", $2); print $1, "=", $2}' \
  /opt/app/conf/app.conf
```

### sed — Stream Editor

```bash
# Print specific lines
sed -n '10,20p' large-file.log     # Lines 10-20
sed -n '$p' file.txt               # Last line

# Substitution
sed 's/old/new/' file.txt          # First occurrence per line
sed 's/old/new/g' file.txt         # All occurrences (global)
sed 's/old/new/gi' file.txt        # Case-insensitive
sed -i 's/localhost/10.0.1.5/g' config.conf   # In-place edit
sed -i.bak 's/old/new/g' config.conf           # In-place with backup

# Delete lines
sed '/^#/d' config.conf            # Delete comment lines
sed '/^$/d' config.conf            # Delete empty lines
sed '/^#/d; /^$/d' config.conf     # Delete both comments and empty lines
sed '5d' file.txt                  # Delete line 5
sed '5,10d' file.txt               # Delete lines 5-10

# Insert and append
sed '5i\New line before line 5' file.txt      # Insert before line 5
sed '5a\New line after line 5' file.txt       # Append after line 5
sed '$a\Last line of file' file.txt           # Append at end

# Extract section between markers
sed -n '/\[database\]/,/\[/p' config.ini | head -n -1

# Production: update config value
sed -i "s/^max_connections=.*/max_connections=200/" /etc/mysql/my.cnf
sed -i "s|^JAVA_OPTS=.*|JAVA_OPTS=\"-Xmx4g -Xms2g\"|" /etc/default/tomcat

# Production: add line after a match
sed -i '/^server_name/a \    return 301 https://$server_name$request_uri;' nginx.conf

# Production: replace entire line matching pattern
sed -i '/^database_host/c\database_host = 10.0.1.30' /opt/app/conf/db.conf
```

### cut, sort, uniq, tr — Text Utilities

```bash
# cut — extract fields
cut -d: -f1 /etc/passwd             # First field, colon delimiter
cut -d: -f1,3 /etc/passwd           # Fields 1 and 3
cut -c1-10 file.txt                 # Characters 1-10
cut -d, -f2- data.csv               # From field 2 onwards

# sort
sort file.txt                       # Alphabetical
sort -r file.txt                    # Reverse
sort -n numbers.txt                 # Numeric sort
sort -rn numbers.txt                # Reverse numeric
sort -t: -k3 -n /etc/passwd         # Sort by 3rd field (UID) numerically
sort -u file.txt                    # Sort and remove duplicates

# uniq — deduplicate (input must be sorted)
sort file.txt | uniq                # Remove duplicates
sort file.txt | uniq -c             # Count occurrences
sort file.txt | uniq -d             # Show only duplicates
sort file.txt | uniq -u             # Show only unique lines

# tr — translate or delete characters
tr 'a-z' 'A-Z' < file.txt          # Uppercase
tr -d '\r' < windows-file.txt       # Remove carriage returns (Windows→Unix)
tr -s ' ' < file.txt                # Squeeze multiple spaces to one
echo "hello world" | tr ' ' '_'    # Replace spaces with underscores

# xargs — build and execute from input
find /tmp -name "*.tmp" | xargs rm -f
cat file-list.txt | xargs -I{} cp {} /backup/
echo "file1 file2 file3" | xargs -n1 echo   # One arg per line
```

---

## 6. Archiving and Compression

### tar — The Standard Archive Tool

```bash
# Create archives
tar -czf archive.tar.gz directory/          # Create gzip-compressed
tar -cjf archive.tar.bz2 directory/         # Create bzip2-compressed
tar -cJf archive.tar.xz directory/          # Create xz-compressed (best compression)
tar -cf archive.tar directory/               # Create uncompressed

# Useful flags for production archives
tar -czf backup-$(date +%F).tar.gz \
  --exclude='*.log' \
  --exclude='.git' \
  --exclude='node_modules' \
  /opt/app/

# Create with verbose output
tar -czvf archive.tar.gz directory/

# List contents without extracting
tar -tvf archive.tar.gz
tar -tvf archive.tar.gz | grep conf/   # Filter listing

# Extract archives
tar -xzf archive.tar.gz                    # Extract in current directory
tar -xzf archive.tar.gz -C /restore/      # Extract to specific directory
tar -xzf archive.tar.gz conf/app.yaml     # Extract a specific file
tar -xzf archive.tar.gz --strip-components=1  # Remove top-level directory

# Verify archive integrity
tar -tzf archive.tar.gz > /dev/null && echo "OK" || echo "CORRUPT"

# Incremental backup with tar
tar -czf full-$(date +%F).tar.gz -g snapshot.snar /opt/app/     # Full
tar -czf incr-$(date +%F).tar.gz -g snapshot.snar /opt/app/     # Incremental

# Archive over SSH
tar -czf - /opt/app/ | ssh backup@server "cat > /backup/app.tar.gz"
```

### gzip, bzip2, xz — Compression Tools

```bash
# gzip
gzip file.txt                 # Compresses to file.txt.gz (replaces original)
gzip -k file.txt              # Keep original (-k = keep)
gzip -d file.txt.gz           # Decompress (same as gunzip)
gzip -9 file.txt              # Maximum compression
gzip -l file.txt.gz           # Show compression ratio

# bzip2 (better compression than gzip, slower)
bzip2 file.txt                # Compresses to file.txt.bz2
bzip2 -d file.txt.bz2         # Decompress (same as bunzip2)
bzip2 -k file.txt             # Keep original

# xz (best compression, slowest)
xz file.txt                   # Compresses to file.txt.xz
xz -d file.txt.xz             # Decompress
xz -k file.txt                # Keep original
xz -9 file.txt                # Maximum compression

# View compressed files without extracting
zcat file.txt.gz
zless file.txt.gz
zgrep "error" file.txt.gz
bzcat file.txt.bz2
xzcat file.txt.xz

# zip (compatible with Windows)
zip archive.zip file1 file2 file3
zip -r archive.zip directory/
unzip archive.zip
unzip archive.zip -d /dest/
unzip -l archive.zip             # List contents
```

---

## 7. Symbolic and Hard Links

### Symbolic Links (Soft Links)

```bash
# Create symbolic link
ln -s /opt/app/bin/myapp /usr/local/bin/myapp
ln -s /opt/nginx/conf/sites-available/mysite /opt/nginx/conf/sites-enabled/mysite

# Create with absolute path (preferred for system links)
ln -s /opt/app/current /opt/app/live

# Update existing symlink (replace atomically)
ln -sfn /opt/app/v2.1.0 /opt/app/current

# View symlink targets
ls -la /usr/local/bin/
readlink /usr/local/bin/myapp        # Show target of symlink
readlink -f /usr/local/bin/myapp     # Show fully resolved path

# Find all symlinks
find /opt -type l -ls
find /usr/local/bin -type l | while read l; do
  echo "$l -> $(readlink $l)"
done

# Find broken symlinks
find /opt -type l ! -e 2>/dev/null   # Symlinks pointing to non-existent targets

# Production pattern: blue-green deploy with symlinks
/opt/releases/
├── v1.2.3/
├── v1.2.4/
└── current -> v1.2.4/   ← symlink, updated atomically on deploy
```

### Hard Links

```bash
# Create hard link (same inode — two names for the same file)
ln original.txt hardlink.txt

# Hard links vs symlinks:
# Hard link: shares the same inode — file persists until ALL hard links removed
# Soft link: separate inode pointing to path — breaks if target is deleted
# Hard links cannot span filesystems or link to directories

# Find all hard links to a file (same inode)
find /opt -inum $(stat -c %i /opt/app/file.txt) 2>/dev/null

# Count hard links (second column in ls -l)
ls -la file.txt   # 2 = file has 2 hard links
```

---

## 8. File Comparison and Verification

### diff — Compare Files

```bash
# Basic diff
diff file1.txt file2.txt

# Side-by-side comparison
diff -y file1.txt file2.txt
diff -y --width=120 file1.txt file2.txt

# Unified format (most common — used by git)
diff -u file1.txt file2.txt
diff -u /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf

# Recursive directory diff
diff -r dir1/ dir2/
diff -rq dir1/ dir2/          # Brief — show only which files differ

# Ignore whitespace
diff -w file1.txt file2.txt    # Ignore all whitespace
diff -b file1.txt file2.txt    # Ignore changes in whitespace amount

# Apply a patch
diff -u original.conf new.conf > changes.patch
patch original.conf < changes.patch

# colordiff — diff with colour (install: sudo apt install colordiff)
colordiff file1.txt file2.txt
```

### Checksums — File Integrity

```bash
# MD5 (fast, not cryptographically secure — for integrity only)
md5sum file.txt
md5sum file.txt > file.txt.md5        # Save checksum
md5sum -c file.txt.md5                # Verify checksum

# SHA-256 (recommended for production integrity checks)
sha256sum file.txt
sha256sum /opt/app/binary > binary.sha256
sha256sum -c binary.sha256            # Verify

# SHA-512 (maximum security)
sha512sum file.txt

# Verify multiple files at once
find /opt/app/bin -type f -exec sha256sum {} \; > checksums.txt
sha256sum -c checksums.txt            # Verify all

# Production: verify downloaded package
wget https://example.com/package.tar.gz
wget https://example.com/package.tar.gz.sha256
sha256sum -c package.tar.gz.sha256

# Compare two files without diff (quick check)
cmp file1.txt file2.txt               # Silent if identical
cmp -l file1.txt file2.txt            # Show differing bytes
```

---

## 9. Redirects, Pipes, and Special Files

### Redirection

```bash
# Stdout redirection
command > output.txt           # Overwrite
command >> output.txt          # Append

# Stderr redirection
command 2> errors.txt          # Redirect stderr
command 2>> errors.txt         # Append stderr

# Both stdout and stderr
command > output.txt 2>&1      # Both to same file
command &> output.txt          # Shorthand
command >> output.txt 2>&1     # Append both

# Discard output
command > /dev/null            # Discard stdout
command 2> /dev/null           # Discard stderr
command &> /dev/null           # Discard both

# Input redirection
command < input.txt
command << 'EOF'               # Here-document (inline input)
line1
line2
EOF

# tee — write to file AND stdout simultaneously
command | tee output.txt       # Tee to file (overwrite)
command | tee -a output.txt    # Tee (append)
command | tee file1 file2      # Tee to multiple files

# Production: log output while also displaying it
./deploy.sh 2>&1 | tee /var/log/deploy-$(date +%F).log
```

### Pipes

```bash
# Chain commands
cat access.log | grep "POST" | awk '{print $1}' | sort | uniq -c | sort -rn

# Named pipes (FIFOs) — for inter-process communication
mkfifo /tmp/mypipe
cat /tmp/mypipe &       # Reader
echo "hello" > /tmp/mypipe  # Writer

# Process substitution
diff <(sort file1.txt) <(sort file2.txt)
diff <(ssh server1 "cat /etc/hosts") <(ssh server2 "cat /etc/hosts")
```

### /proc and /sys — Virtual Filesystems

```bash
# Process information
cat /proc/$$/status            # Current shell process status
cat /proc/1234/cmdline | tr '\0' ' '   # Full command line of PID 1234
ls /proc/1234/fd/              # Open file descriptors
cat /proc/1234/maps            # Memory map

# System information
cat /proc/cpuinfo              # CPU details
cat /proc/meminfo              # Memory details
cat /proc/loadavg              # Load averages
cat /proc/uptime               # System uptime
cat /proc/net/dev              # Network interface stats
cat /proc/diskstats            # Disk I/O stats

# Kernel parameters (read and write)
cat /proc/sys/net/ipv4/ip_forward
echo 1 > /proc/sys/net/ipv4/ip_forward   # Temporary change

# /sys — device and driver information
ls /sys/block/                 # Block devices
cat /sys/block/sda/queue/scheduler   # I/O scheduler for sda
cat /sys/class/net/eth0/speed        # Network interface speed
```

---

## 10. ACLs — Fine-Grained Access Control

```bash
# Install
sudo apt install acl     # Debian/Ubuntu
sudo yum install acl     # RHEL/CentOS

# View ACLs
getfacl /opt/app/data

# Set ACL for a user
sudo setfacl -m u:john:rw /opt/app/data/shared.txt

# Set ACL for a group
sudo setfacl -m g:devops:rx /opt/app/logs/

# Set default ACL (new files in directory inherit this)
sudo setfacl -d -m u:appuser:rw /opt/app/data/
sudo setfacl -d -m g:devteam:r /opt/app/logs/

# Recursive ACL
sudo setfacl -R -m u:monitoring:rx /var/log/app/

# Remove ACL for a user
sudo setfacl -x u:john /opt/app/data/shared.txt

# Remove all ACLs
sudo setfacl -b /opt/app/data/shared.txt

# Copy ACLs from one file to another
getfacl source.txt | setfacl --set-file=- dest.txt

# Real-world pattern: CI/CD user needs read-only log access
sudo setfacl -R -m u:ci-deploy:rx /var/log/app/
sudo setfacl -d -m u:ci-deploy:rx /var/log/app/    # Future files too
```

---

## 11. Production File Management Patterns

### Config File Deployment

```bash
# Safe config update pattern
CONF="/etc/nginx/nginx.conf"

# Step 1: Validate new config before deploying
nginx -t -c /tmp/nginx.conf.new && echo "Config valid"

# Step 2: Backup current config
cp "$CONF" "${CONF}.bak-$(date +%F-%H%M%S)"

# Step 3: Deploy new config
cp /tmp/nginx.conf.new "$CONF"

# Step 4: Reload without restart
systemctl reload nginx

# Step 5: Verify reload succeeded
systemctl is-active nginx && echo "Reload OK" || {
  echo "Reload failed — rolling back"
  cp "${CONF}.bak-$(date +%F-%H%M%S)" "$CONF"
  systemctl reload nginx
}
```

### Log Rotation Pattern

```bash
# Manual rotation (when logrotate isn't enough)
LOG="/opt/app/logs/app.log"
ARCHIVE_DIR="/opt/app/logs/archive"

mkdir -p "$ARCHIVE_DIR"
mv "$LOG" "${ARCHIVE_DIR}/app-$(date +%F-%H%M%S).log"
gzip "${ARCHIVE_DIR}/app-$(date +%F-%H%M%S).log"
touch "$LOG"
chown appuser:appgroup "$LOG"
chmod 640 "$LOG"
kill -USR1 $(cat /var/run/app.pid)    # Signal app to reopen log file

# Clean logs older than 30 days
find "$ARCHIVE_DIR" -name "*.log.gz" -mtime +30 -delete
```

### Deployment Artifact Management

```bash
RELEASES_DIR="/opt/releases"
CURRENT_LINK="/opt/app/current"
NEW_VERSION="v1.2.5"

# Step 1: Create release directory
mkdir -p "${RELEASES_DIR}/${NEW_VERSION}"

# Step 2: Extract release
tar -xzf "app-${NEW_VERSION}.tar.gz" -C "${RELEASES_DIR}/${NEW_VERSION}/"

# Step 3: Set ownership
chown -R appuser:appgroup "${RELEASES_DIR}/${NEW_VERSION}/"

# Step 4: Atomic symlink update (zero downtime)
ln -sfn "${RELEASES_DIR}/${NEW_VERSION}" "${CURRENT_LINK}"

# Step 5: Reload app (reads from symlinked current)
systemctl reload myapp

# Step 6: Keep only last 5 releases
ls -dt "${RELEASES_DIR}"/v* | tail -n +6 | xargs rm -rf
```

### File Permission Audit Script

```bash
#!/bin/bash
# Quick permission audit for a service directory

APP_DIR="/opt/app"
SERVICE_USER="appuser"

echo "=== World-writable files ==="
find "$APP_DIR" -perm -0002 -type f

echo "=== Files owned by root (should be owned by $SERVICE_USER) ==="
find "$APP_DIR" -user root -not -path "*/bin/*"

echo "=== Incorrect permissions on config files ==="
find "$APP_DIR/conf" -type f ! -perm 640

echo "=== Executable files in conf directory (suspicious) ==="
find "$APP_DIR/conf" -type f -perm /111

echo "=== Symlink audit ==="
find "$APP_DIR" -type l ! -e      # Broken symlinks
```

---

## 12. Quick Reference Card

```
# Navigation
ls -lah                List all with details and hidden files
ls -ltr                List by time, oldest first
cd -                   Go to previous directory
tree -L 2 /opt         Directory tree, 2 levels

# File Operations
cp -a src/ dest/       Copy with permissions and timestamps
cp -rp src/ dest/      Copy recursively, preserve attributes
mv -i old new          Move, prompt on overwrite
rm -rf dir/            Remove directory (careful!)
mkdir -p a/b/c         Create full path

# Permissions
chmod 750 file         rwxr-x--- (owner+group)
chmod -R 640 dir/      Recursive permission change
chown -R user:grp dir/ Change owner and group
umask 027              New files: 640, new dirs: 750

# Searching
find /var -name "*.log" -mtime +30   Files older than 30 days
find / -perm -4000 2>/dev/null       SUID files
grep -rn "pattern" /etc/             Recursive grep with line numbers
grep -v "^#\|^$" nginx.conf          Config without comments

# Text Processing
awk '{print $1}' log | sort | uniq -c | sort -rn   Top values
sed -i 's/old/new/g' config.conf      In-place substitution
cut -d: -f1 /etc/passwd               Extract field

# Archives
tar -czf backup.tar.gz dir/           Create archive
tar -tvf backup.tar.gz                List contents
tar -xzf backup.tar.gz -C /dest/      Extract to directory
sha256sum -c checksums.txt            Verify integrity

# Links
ln -s /opt/app/current /opt/app/live   Create symlink
ln -sfn /opt/app/v2 /opt/app/current   Update symlink atomically
readlink -f /opt/app/current           Resolve symlink target
find /opt -type l ! -e                 Find broken symlinks
```

---

*References: `man ls`, `man find`, `man chmod`, `man chown`, `man tar`, `man grep`, `man awk`, `man sed`, [GNU Coreutils](https://www.gnu.org/software/coreutils/manual/)*

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha Reddy Puli
> **Repository:** linux-for-devops / 01-file-management
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
