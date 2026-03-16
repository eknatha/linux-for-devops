# Linux Networking for DevOps / SRE / Platform Engineers 

Networking is a **critical skill for DevOps, SRE, and Platform Engineers**.   
Modern applications run as distributed systems where services communicate across networks. Understanding how to inspect, debug, and troubleshoot networking issues is essential for maintaining reliable infrastructure.

This guide covers **essential Linux networking commands and troubleshooting techniques** used in production environments. 

---

# 1. Check Network Interfaces 

Network interfaces allow a system to communicate with other systems on the network.

## List network interfaces 

```bash
ip link
```

Example output:

```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>
```

---

## Show IP addresses

```bash
ip addr
```

Example:

```
inet 192.168.1.25/24 brd 192.168.1.255 scope global eth0
```

---

# 2. Check System IP Address

Quick way to display assigned IP addresses:

```bash
hostname -I
```

Or view detailed interface information:

```bash
ip addr show
```

---

# 3. Network Connection Status

View network devices and connection states.

```bash
nmcli device status
```

Example output:

```
DEVICE  TYPE      STATE      CONNECTION
eth0    ethernet  connected  Wired connection
```

---

## Show available connections

```bash
nmcli connection show
```

---

## Restart a network connection

```bash
nmcli connection down "Wired connection"
nmcli connection up "Wired connection"
```

---

# 4. Test Network Connectivity

## Ping a host

```bash
ping google.com
```

Example output:

```
64 bytes from 142.250.183.14: icmp_seq=1 ttl=115 time=20 ms
```

Stop ping using:

```
Ctrl + C
```

---

# 5. Check DNS Resolution

DNS converts domain names into IP addresses.

## Using dig

```bash
dig google.com
```

Example:

```
ANSWER SECTION:
google.com. 300 IN A 142.250.183.14
```

---

## Using nslookup

```bash
nslookup google.com
```

---

# 6. Check Open Ports

Applications communicate through network ports.

```bash
ss -tuln
```

Example output:

```
tcp   LISTEN  0  128  0.0.0.0:22
```

Explanation:

| Flag | Meaning |
|-----|------|
| `t` | TCP |
| `u` | UDP |
| `l` | Listening |
| `n` | Numeric output |

---

# 7. Check Which Process is Using a Port 

Example: check process using port **8080**

```bash
lsof -i :8080
```

Example output:

```
java  1342 user  TCP *:8080 (LISTEN)
```

---

# 8. View Routing Table 

Routing determines where network packets are sent.

```bash
ip route
```

Example output:

```
default via 192.168.1.1 dev eth0
```

---

# 9. Trace Network Path 

Shows the path packets take to reach a destination.

```bash
traceroute google.com
```

Example output:

```
1 192.168.1.1
2 10.10.0.1
3 72.14.220.1
```

---

# 10. Test Port Connectivity

Useful for debugging application connectivity.

## Using netcat

```bash
nc -zv example.com 443
```

Example output:

```
Connection to example.com 443 port [tcp/https] succeeded!
```

---

# 11. Transfer Data Over Network

These tools are widely used in automation scripts and debugging APIs.

## Using curl

```bash
curl https://example.com
```

Download a file:

```bash
curl -O https://example.com/file.zip
```

---

## Using wget

```bash
wget https://example.com/file.zip
```

---

# 12. Monitor Network Traffic

## Monitor bandwidth usage

```bash
iftop
```

---

## View network traffic graph

```bash
nload
```

These tools help identify:

- bandwidth usage
- high traffic connections
- network bottlenecks

---

# 13. Firewall Management 

Many Linux systems use a firewall to control network access.

## Check firewall rules 

```bash
firewall-cmd --list-all
```

---

## Allow a port 

```bash
firewall-cmd --add-port=80/tcp --permanent
```

Reload firewall rules:

```bash
firewall-cmd --reload
```

---

# 14. Network Troubleshooting Examples

## Check if application port is open 

```bash
ss -tuln | grep 8080
```

---

## Verify DNS resolution 

```bash
dig api.example.com
```

---

## Check route to a host 

```bash
ip route get 8.8.8.8
```

---

## Identify process using port 

```bash
lsof -i :3000
```

---

# 15. Essential Networking Commands Summary 

| Command | Purpose |
|------|------|
| `ip addr` | Show IP addresses |
| `ip link` | Show network interfaces |
| `ip route` | Show routing table |
| `ping` | Test connectivity |
| `dig` | DNS lookup |
| `ss` | Show open ports |
| `lsof` | Process using port |
| `traceroute` | Trace network path |
| `curl` | HTTP requests |
| `wget` | Download files |

---

# Conclusion

Networking knowledge helps DevOps engineers:

- Diagnose connectivity issues
- Debug service communication failures
- Inspect open ports and running services
- Verify DNS resolution
- Monitor network performance

Mastering these Linux networking tools improves **production troubleshooting, incident response, and infrastructure reliability**. 

---

⭐ If you found this useful, consider **starring the repository**. 
