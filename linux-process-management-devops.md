# Linux Process Management for DevOps / SRE / Platform Engineers 

Process management is a **critical Linux skill for DevOps, SRE, and Platform Engineers**.  Applications, containers, services, and system tasks all run as processes. Understanding how to inspect, control, and debug processes is essential for operating production systems.

This guide covers **essential Linux process management commands and concepts**. 

---

# 1. What is a Process? 

A **process** is a running instance of a program.

Example:

```
nginx
docker
java
node
python
```

Each process has:

- **PID (Process ID)**
- **Parent Process**
- **CPU usage**
- **Memory usage**
- **Execution state**

---

# 2. Viewing Running Processes

## List processes

```bash
ps
```

Common usage:

```bash
ps aux
```

| Option | Meaning |
|------|------|
| `a` | Show processes for all users |
| `u` | User-oriented format |
| `x` | Include background processes |

Example output:

```
USER   PID  %CPU %MEM COMMAND
root   101   0.1  0.2 nginx
```

---

# 3. Real-Time Process Monitoring

## Top

```bash
top
```

Shows:

- CPU usage
- Memory usage
- Running processes
- System load

Useful keys in `top`:

| Key | Action |
|---|---|
| `q` | Quit |
| `k` | Kill process |
| `M` | Sort by memory |
| `P` | Sort by CPU |

---

## Htop (Better alternative)

```bash
htop
```

Features:

- Interactive interface
- Color-coded metrics
- Easier process management

Install:

```bash
sudo apt install htop
```

---

# 4. Finding Processes

## Using grep

```bash
ps aux | grep nginx
```

Example:

```bash
ps aux | grep docker
```

---

## Using pgrep

```bash
pgrep nginx
```

Find process IDs directly.

Example:

```bash
pgrep -l nginx
```

---

# 5. Process States

Linux processes have different states.

| State | Meaning |
|---|---|
| `R` | Running |
| `S` | Sleeping |
| `D` | Uninterruptible sleep |
| `T` | Stopped |
| `Z` | Zombie |

Example:

```
STAT
S
R
```

---

# 6. Killing Processes

Sometimes processes become **unresponsive** and must be terminated.

## Kill by PID

```bash
kill 1234
```

---

## Force kill

```bash
kill -9 1234
```

⚠️ Force kill should be used carefully.

---

## Kill by name

```bash
pkill nginx
```

Example:

```bash
pkill node
```

---

## Kill all processes with same name

```bash
killall nginx
```

---

# 7. Background Processes

## Run process in background

```bash
command &
```

Example:

```bash
python app.py &
```

---

## View background jobs

```bash
jobs
```

Example output:

```
[1]+ Running python app.py &
```

---

## Bring job to foreground

```bash
fg %1
```

---

## Send job to background

```bash
bg %1
```

---

# 8. Process Priority

Linux allows control of **CPU scheduling priority**.

Priority levels:

- **-20 (highest priority)**
- **19 (lowest priority)**

---

## Start process with priority

```bash
nice -n 10 command
```

Example:

```bash
nice -n 10 python script.py
```

---

## Change priority of running process

```bash
renice 10 -p 1234
```

---

# 9. Process Tree

Shows parent-child relationships between processes.

```bash
pstree
```

Example:

```
systemd
 ├─nginx
 ├─docker
 │   └─containerd
```

Useful for **debugging service dependencies**.

---

# 10. System Load

Check system load averages.

```bash
uptime
```

Example output:

```
load average: 0.30, 0.40, 0.45
```

Load averages represent system load for:

- 1 minute
- 5 minutes
- 15 minutes

---

# 11. Checking Process Resource Usage

## CPU usage

```bash
top
```

---

## Memory usage

```bash
free -h
```

---

## Process-specific memory

```bash
ps aux --sort=-%mem
```

Shows processes using most memory.

---

# 12. Monitoring Specific Process

Example: monitor nginx process

```bash
watch -n 1 "ps aux | grep nginx"
```

Runs every second.

---

# 13. System Services (Systemd)

Most Linux services run through **systemd**.

## Check service status

```bash
systemctl status nginx
```

---

## Start service

```bash
sudo systemctl start nginx
```

---

## Stop service

```bash
sudo systemctl stop nginx
```

---

## Restart service

```bash
sudo systemctl restart nginx
```

---

## Enable service at boot

```bash
sudo systemctl enable nginx
```

---

# 14. Real DevOps Use Cases

## Find high CPU process

```bash
top
```

---

## Kill stuck process

```bash
kill -9 PID
```

---

## Check running application

```bash
ps aux | grep node
```

---

## Debug service crash

```bash
systemctl status service-name
journalctl -u service-name
```

---

# 15. Useful Commands Summary

| Command | Purpose |
|---|---|
| `ps aux` | List processes |
| `top` | Real-time monitoring |
| `htop` | Interactive monitoring |
| `kill` | Terminate process |
| `pkill` | Kill by name |
| `jobs` | Show background jobs |
| `nice` | Set process priority |
| `renice` | Change priority |
| `systemctl` | Manage services |

---

# Conclusion

Process management helps DevOps engineers:

- Monitor system performance
- Debug application issues
- Control services and workloads
- Optimize system resource usage
- Maintain system stability

Mastering process management is essential for **Operating Linux production environments**. 

--- 

⭐ If you found this useful, consider **starring the repository**. 
