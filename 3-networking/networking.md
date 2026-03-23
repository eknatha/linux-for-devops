# Linux Networking — Production Reference Guide

> Comprehensive reference for IP configuration, routing, DNS, firewall, diagnostics, performance tuning, load balancing, TLS, and network security on production Linux servers.

---

![Eknatha](https://img.shields.io/badge/Eknatha-4EAA25?style=flat&logo=gnu-bash&logoColor=white)



## Table of Contents

1. [Network Interface Configuration](#1-network-interface-configuration)
2. [IP Routing](#2-ip-routing)
3. [DNS Configuration and Troubleshooting](#3-dns-configuration-and-troubleshooting)
4. [Firewall — iptables, nftables, ufw](#4-firewall--iptables-nftables-ufw)
5. [Network Diagnostics and Troubleshooting](#5-network-diagnostics-and-troubleshooting)
6. [Bandwidth and Performance Monitoring](#6-bandwidth-and-performance-monitoring)
7. [Kernel Network Tuning — sysctl](#7-kernel-network-tuning--sysctl)
8. [Load Balancing — HAProxy and Nginx](#8-load-balancing--haproxy-and-nginx)
9. [TLS/SSL — Certificates and Verification](#9-tlsssl--certificates-and-verification)
10. [VPN and Tunnels](#10-vpn-and-tunnels)
11. [Network Security Hardening](#11-network-security-hardening)
12. [Production Networking Runbook](#12-production-networking-runbook)

---

## 1. Network Interface Configuration

### View Interface Status

```bash
# All interfaces with IPs, state, and MAC
ip addr show
ip a           # shorthand

# Single interface
ip addr show eth0

# Link state, speed, duplex, MTU
ip link show
ip -s link show eth0    # with packet counters

# Legacy tools (still widely used)
ifconfig -a
ifconfig eth0

# Physical NIC info (speed, duplex, auto-negotiation)
sudo ethtool eth0
sudo ethtool -S eth0    # NIC statistics
```

### Temporary IP Configuration (Lost on Reboot)

```bash
# Add an IP address
sudo ip addr add 10.0.1.10/24 dev eth0

# Remove an IP address
sudo ip addr del 10.0.1.10/24 dev eth0

# Bring interface up/down
sudo ip link set eth0 up
sudo ip link set eth0 down

# Set MTU (1500 = standard Ethernet, 9000 = jumbo frames)
sudo ip link set eth0 mtu 9000

# Add a VLAN interface
sudo ip link add link eth0 name eth0.100 type vlan id 100
sudo ip link set eth0.100 up
```

### Persistent Configuration — Netplan (Ubuntu 18.04+)

```yaml
# /etc/netplan/00-production.yaml

network:
  version: 2
  renderer: networkd   # or: NetworkManager

  ethernets:

    # Primary NIC — static IP
    eth0:
      dhcp4: false
      dhcp6: false
      addresses:
        - 10.0.1.10/24
        - 10.0.1.11/24    # Secondary IP (VIP, virtual interface)
      routes:
        - to: default
          via: 10.0.1.1
          metric: 100
      nameservers:
        addresses: [10.0.0.53, 8.8.8.8]
        search: [prod.example.com, example.com]
      mtu: 1500

    # Secondary NIC — DHCP (management network)
    eth1:
      dhcp4: true
      dhcp4-overrides:
        use-routes: false   # Don't replace default route with DHCP route

  # NIC Bonding / Teaming for redundancy
  bonds:
    bond0:
      interfaces: [eth2, eth3]
      addresses: [10.0.2.10/24]
      parameters:
        mode: active-backup     # Options: active-backup, balance-rr, balance-xor, 802.3ad
        primary: eth2
        mii-monitor-interval: 100
      routes:
        - to: 10.0.2.0/24
          via: 10.0.2.1
```

```bash
# Validate without applying
sudo netplan generate
sudo netplan try      # Apply with 120s auto-rollback timeout
sudo netplan apply    # Apply permanently
```

### Persistent Configuration — nmcli (RHEL/CentOS)

```bash
# Show all connections
nmcli connection show

# Create a static IP connection
nmcli connection add \
  type ethernet \
  con-name "prod-eth0" \
  ifname eth0 \
  ipv4.method manual \
  ipv4.addresses "10.0.1.10/24" \
  ipv4.gateway "10.0.1.1" \
  ipv4.dns "10.0.0.53,8.8.8.8" \
  ipv4.dns-search "prod.example.com" \
  connection.autoconnect yes

# Activate the connection
nmcli connection up prod-eth0

# Modify an existing connection
nmcli connection modify prod-eth0 ipv4.addresses "10.0.1.10/24,10.0.1.11/24"

# Add a secondary IP
nmcli connection modify prod-eth0 +ipv4.addresses "10.0.1.12/24"
```

### Network Interface Bonding

```bash
# Load bonding kernel module
sudo modprobe bonding

# Create bond interface
sudo ip link add bond0 type bond
sudo ip link set bond0 type bond mode active-backup miimon 100

# Enslave physical interfaces
sudo ip link set eth0 master bond0
sudo ip link set eth1 master bond0

# Bring up
sudo ip link set bond0 up
sudo ip addr add 10.0.2.10/24 dev bond0

# View bond status
cat /proc/net/bonding/bond0
```

---

## 2. IP Routing

### View and Manage Routes

```bash
# Show routing table
ip route show
ip route show table all    # All routing tables

# Show route for a specific destination
ip route get 8.8.8.8
ip route get 10.0.1.50

# Add a static route (temporary)
sudo ip route add 192.168.10.0/24 via 10.0.1.1
sudo ip route add 192.168.10.0/24 dev eth0 src 10.0.1.10

# Add default gateway
sudo ip route add default via 10.0.1.1

# Delete a route
sudo ip route del 192.168.10.0/24

# Change a route
sudo ip route change default via 10.0.1.2 metric 50
```

### Persistent Static Routes

```bash
# Ubuntu — in netplan (see section 1)
# RHEL/CentOS — /etc/sysconfig/network-scripts/route-eth0
10.10.0.0/16 via 10.0.1.254
172.16.0.0/12 via 10.0.1.254
```

### Policy-Based Routing (Multiple Default Gateways)

```bash
# Use Case: Server with two ISPs — route traffic from eth0 IP via ISP1,
# traffic from eth1 IP via ISP2

# 1. Add routing tables
echo "100 isp1" | sudo tee -a /etc/iproute2/rt_tables
echo "200 isp2" | sudo tee -a /etc/iproute2/rt_tables

# 2. Add routes to each table
sudo ip route add default via 10.0.1.1 table isp1
sudo ip route add default via 10.0.2.1 table isp2

# 3. Rules: route based on source IP
sudo ip rule add from 10.0.1.10 table isp1 priority 100
sudo ip rule add from 10.0.2.10 table isp2 priority 200

# 4. Verify
ip rule show
ip route show table isp1
ip route show table isp2
```

### Enabling IP Forwarding (Router / NAT)

```bash
# Temporary
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# Persistent
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/99-forwarding.conf
sudo sysctl -p /etc/sysctl.d/99-forwarding.conf

# NAT masquerading (outbound traffic from 10.0.1.0/24 via eth0)
sudo iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

---

## 3. DNS Configuration and Troubleshooting

### /etc/resolv.conf

```bash
# /etc/resolv.conf — Production config
nameserver 10.0.0.53         # Primary — internal DNS (knows internal hostnames)
nameserver 8.8.8.8           # Secondary — Google (public fallback)
nameserver 1.1.1.1           # Tertiary — Cloudflare
search prod.example.com example.com   # Domain search suffixes
options timeout:2 attempts:3 rotate   # 2s timeout, 3 attempts, rotate resolvers
```

### systemd-resolved (Ubuntu 18.04+)

```bash
# Status and current resolvers
resolvectl status
resolvectl statistics

# Query via systemd-resolved
resolvectl query api.example.com
resolvectl query --type=MX example.com

# DNS query with specific interface
resolvectl query --interface eth0 internal.example.com

# Flush DNS cache
sudo resolvectl flush-caches

# Config file
sudo vi /etc/systemd/resolved.conf
```

```ini
# /etc/systemd/resolved.conf
[Resolve]
DNS=10.0.0.53 8.8.8.8 1.1.1.1
FallbackDNS=9.9.9.9 208.67.222.222
Domains=prod.example.com example.com
DNSSEC=allow-downgrade
DNSOverTLS=opportunistic
Cache=yes
DNSStubListener=yes
```

### dig — DNS Diagnostics

```bash
# Basic lookup
dig api.example.com

# Short answer only
dig +short api.example.com

# Query specific record type
dig api.example.com A
dig api.example.com AAAA
dig api.example.com MX
dig api.example.com TXT
dig api.example.com NS
dig api.example.com CNAME

# Query specific DNS server
dig @8.8.8.8 api.example.com
dig @10.0.0.53 internal-host.prod.example.com

# Trace DNS delegation path
dig +trace api.example.com

# Reverse DNS lookup (PTR)
dig -x 8.8.8.8
dig -x 10.0.1.10

# Check all nameservers for a domain
for ns in $(dig +short NS example.com); do
  echo "=== $ns ==="
  dig @$ns example.com A +short
done

# Check DNS propagation across resolvers
for resolver in 8.8.8.8 1.1.1.1 9.9.9.9 208.67.222.222; do
  result=$(dig @$resolver +short api.example.com)
  echo "$resolver → ${result:-NXDOMAIN}"
done
```

### Common DNS Issues

```bash
# Issue: DNS resolution slow
# Diagnose
time dig api.example.com
dig +stats api.example.com   # Shows query time

# Fix: Check resolv.conf order, test each resolver
dig @10.0.0.53 api.example.com | grep "Query time"

# Issue: NXDOMAIN for internal hostname
dig internal-svc.prod.example.com          # No search suffix
dig internal-svc                           # Uses search suffix

# Issue: Stale TTL — get actual TTL
dig api.example.com | grep -A1 '^;; ANSWER'

# Issue: Split-horizon DNS (different internal vs external answer)
dig @10.0.0.53 api.example.com    # Internal answer
dig @8.8.8.8 api.example.com      # External answer
```

---

## 4. Firewall — iptables, nftables, ufw

### iptables — Core Concepts

```
Tables:  filter (default) | nat | mangle | raw | security
Chains:  INPUT | OUTPUT | FORWARD | PREROUTING | POSTROUTING
Actions: ACCEPT | DROP | REJECT | LOG | DNAT | SNAT | MASQUERADE
```

### iptables — Production Ruleset

```bash
# ============================================================
# Production iptables hardening — applied in order
# ============================================================

# Flush all existing rules
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t mangle -F

# Default policies: DROP everything, allow only what's needed
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT    # Allow all outbound

# Allow loopback (always required)
sudo iptables -A INPUT -i lo -j ACCEPT

# Allow established and related connections (return traffic)
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow ICMP (ping) — required for network diagnostics
sudo iptables -A INPUT -p icmp --icmp-type echo-request -m limit \
  --limit 10/second --limit-burst 20 -j ACCEPT

# Allow SSH — restrict to management IP ranges only
sudo iptables -A INPUT -p tcp --dport 22 -s 10.0.0.0/8 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -s 172.16.0.0/12 -j ACCEPT

# Allow HTTP and HTTPS from anywhere
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow application port from internal network only
sudo iptables -A INPUT -p tcp --dport 8080 -s 10.0.1.0/24 -j ACCEPT

# Rate limit new connections (anti-DoS)
sudo iptables -A INPUT -p tcp --dport 80 -m state --state NEW \
  -m limit --limit 100/second --limit-burst 200 -j ACCEPT

# SYN flood protection
sudo iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
sudo iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
sudo iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

# Log and drop everything else
sudo iptables -A INPUT -m limit --limit 5/min -j LOG \
  --log-prefix "iptables-DROP: " --log-level 7
sudo iptables -A INPUT -j DROP

# Save rules (persistent across reboots)
sudo iptables-save | sudo tee /etc/iptables/rules.v4
# Debian/Ubuntu:
sudo apt install iptables-persistent
sudo netfilter-persistent save
```

### iptables — Common Patterns

```bash
# Block a specific IP
sudo iptables -I INPUT -s 185.224.128.17 -j DROP

# Block a range (CIDR)
sudo iptables -I INPUT -s 192.168.100.0/24 -j DROP

# Allow a port only from specific subnet
sudo iptables -A INPUT -p tcp --dport 5432 -s 10.0.1.0/24 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 5432 -j DROP

# Port forwarding (DNAT): traffic to :8080 → internal :80
sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 \
  -j DNAT --to-destination 10.0.1.20:80

# Limit SSH connections (10 new per minute per IP)
sudo iptables -A INPUT -p tcp --dport 22 -m state --state NEW \
  -m recent --set --name SSH
sudo iptables -A INPUT -p tcp --dport 22 -m state --state NEW \
  -m recent --update --seconds 60 --hitcount 10 --name SSH -j DROP

# View rules with counters and line numbers
sudo iptables -L INPUT -n -v --line-numbers

# Delete a specific rule by line number
sudo iptables -D INPUT 5

# Insert a rule at position 2
sudo iptables -I INPUT 2 -p tcp --dport 9200 -s 10.0.1.0/24 -j ACCEPT
```

### ufw — Simplified Firewall (Ubuntu)

```bash
# Enable and set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable

# Allow services
sudo ufw allow ssh
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow from specific IP/range
sudo ufw allow from 10.0.1.0/24 to any port 22
sudo ufw allow from 10.0.0.0/8

# Allow port range
sudo ufw allow 8000:9000/tcp

# Deny specific IP
sudo ufw deny from 185.224.128.17

# Rate limit SSH (6 connections in 30 seconds → block)
sudo ufw limit ssh

# View rules with numbers
sudo ufw status numbered

# Delete rule by number
sudo ufw delete 5

# Reload without disabling
sudo ufw reload
```

### nftables (Modern Replacement for iptables)

```bash
# Check ruleset
sudo nft list ruleset

# Production nftables config
sudo tee /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        iif "lo" accept
        ct state established,related accept
        ct state invalid drop

        # ICMP
        ip protocol icmp icmp type echo-request limit rate 10/second accept
        ip6 nexthdr icmpv6 accept

        # SSH — management network only
        tcp dport 22 ip saddr 10.0.0.0/8 accept

        # Web
        tcp dport { 80, 443 } accept

        # App port — internal only
        tcp dport 8080 ip saddr 10.0.1.0/24 accept

        # Log and drop rest
        log prefix "nft-drop: " drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

sudo systemctl enable --now nftables
sudo nft -f /etc/nftables.conf
```

---

## 5. Network Diagnostics and Troubleshooting

### ping — ICMP Reachability

```bash
# Basic ping
ping -c4 8.8.8.8

# Ping via specific interface
ping -c4 -I eth0 8.8.8.8

# Flood ping (requires root — use carefully)
sudo ping -f -c1000 10.0.1.5 | tail -5

# Large packet ping (test fragmentation / MTU)
ping -c4 -s 1472 10.0.1.5    # 1472 + 28 byte header = 1500 MTU
ping -c4 -M do -s 1472 10.0.1.5   # Don't Fragment bit

# Ping all hosts in a subnet (quick scan)
for i in $(seq 1 254); do
  ping -c1 -W1 10.0.1.$i &>/dev/null && echo "10.0.1.$i is up" &
done; wait
```

### traceroute / mtr — Path Analysis

```bash
# Standard traceroute (UDP probes)
traceroute 8.8.8.8

# TCP traceroute (better through firewalls)
sudo traceroute -T -p 443 api.example.com

# No DNS resolution (faster)
traceroute -n 8.8.8.8

# mtr — real-time combined ping + traceroute
mtr --report --no-dns 8.8.8.8     # Non-interactive report (10 pings)
mtr --report -c 100 --no-dns 8.8.8.8   # 100 cycles for accurate stats
mtr -n 8.8.8.8                    # Interactive mode (no DNS)

# mtr output to review:
# Loss% — packet loss per hop (>1% = investigate)
# Avg   — average RTT per hop
# StDev — jitter (high = unstable link)
```

### ss — Socket Statistics

```bash
# All listening TCP and UDP
sudo ss -tulnp

# Active TCP connections with process
sudo ss -tnp state established

# Connections to a specific port
ss -tnp dst :443
ss -tnp src :8080

# Count connections per state
ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn

# Connections from a specific IP
ss -tnp src 10.0.1.5

# All sockets for a specific process
ss -tulnp | grep nginx

# Socket statistics summary
ss -s

# TIME_WAIT count (high value = connection reuse issue)
ss -tan state time-wait | wc -l
```

### tcpdump — Packet Capture

```bash
# Capture all traffic on eth0 (limited output)
sudo tcpdump -i eth0 -n -c 100

# Capture specific port
sudo tcpdump -i eth0 -n port 80
sudo tcpdump -i eth0 -n port 443

# Capture traffic to/from specific host
sudo tcpdump -i eth0 host 10.0.1.5

# Capture HTTP request lines only
sudo tcpdump -i eth0 -A -s 0 port 80 | grep -E 'GET|POST|HTTP|Host:'

# Capture and save for Wireshark
sudo tcpdump -i eth0 -w /tmp/capture-$(date +%F-%H%M).pcap -s 0

# Capture with filter: host AND port
sudo tcpdump -i eth0 host 10.0.1.5 and port 5432

# Read a saved capture
tcpdump -r /tmp/capture.pcap -n | head -30

# Capture DNS queries
sudo tcpdump -i eth0 -n port 53

# Capture by network (CIDR)
sudo tcpdump -i eth0 net 10.0.1.0/24
```

### nc (netcat) — TCP/UDP Testing

```bash
# Test TCP port reachability
nc -zv 10.0.1.5 443
nc -zv api.example.com 443

# Test multiple ports
nc -zv 10.0.1.5 80 443 8080 2>&1

# Scan a port range
nc -zv 10.0.1.5 20-25 2>&1 | grep succeeded

# Simple TCP server for testing (listen on port 9999)
nc -l -p 9999

# Send data to a TCP server
echo "test message" | nc 10.0.1.5 9999

# UDP test
nc -zu 10.0.1.5 53
```

### curl — HTTP/HTTPS Diagnostics

```bash
# Check HTTP response code
curl -sIo /dev/null -w "%{http_code}\n" https://api.example.com/health

# Full timing breakdown
curl -w "\n\
  DNS lookup:       %{time_namelookup}s\n\
  TCP connect:      %{time_connect}s\n\
  TLS handshake:    %{time_appconnect}s\n\
  Time to first byte: %{time_starttransfer}s\n\
  Total:            %{time_total}s\n\
  HTTP code:        %{http_code}\n" \
  -sIo /dev/null https://api.example.com

# Follow redirects
curl -L -sIo /dev/null -w "%{http_code}" https://example.com

# Test with specific IP (bypass DNS)
curl -sI --resolve api.example.com:443:10.0.1.20 https://api.example.com

# Test certificate
curl -v https://api.example.com 2>&1 | grep -E 'SSL|certificate|expire'

# Test with SNI
curl -sI --header "Host: api.example.com" https://10.0.1.20

# Send headers and body
curl -X POST https://api.example.com/v1/data \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"key":"value"}' \
  -w "\nStatus: %{http_code}\n"
```

---

## 6. Bandwidth and Performance Monitoring

### iftop — Bandwidth by Connection

```bash
sudo apt install iftop
sudo iftop -i eth0 -n      # No DNS
sudo iftop -i eth0 -P      # Show ports
sudo iftop -i eth0 -B      # Show bytes instead of bits

# Interactive keys:
# n → toggle hostname/IP
# p → toggle ports
# s/d → toggle source/destination totals
# 1/2/3 → sort by 2s/10s/40s average
# P → pause
# q → quit
```

### nethogs — Bandwidth by Process

```bash
sudo apt install nethogs
sudo nethogs eth0
sudo nethogs -d 2 eth0      # Refresh every 2 seconds
sudo nethogs -b eth0        # No ncurses, output to stdout

# Show all interfaces
sudo nethogs
```

### iperf3 — Throughput Testing

```bash
# On server (receiver)
iperf3 -s -p 5201

# On client (sender) — TCP throughput
iperf3 -c 10.0.1.5 -t 30        # 30 second test
iperf3 -c 10.0.1.5 -P 4         # 4 parallel streams
iperf3 -c 10.0.1.5 -R           # Reverse (test download speed)
iperf3 -c 10.0.1.5 -u -b 100M   # UDP at 100 Mbps

# Bidirectional test
iperf3 -c 10.0.1.5 --bidir
```

### Kernel Network Stats

```bash
# Interface receive/transmit counters
cat /proc/net/dev

# TCP statistics (retransmits, resets)
cat /proc/net/snmp | grep Tcp
ss -s

# Dropped packets
netstat -i

# Current connections
cat /proc/net/sockstat

# TCP retransmission rate (should be near zero)
watch -n5 'cat /proc/net/snmp | grep -i "retrans\|inerr\|outtcp"'

# Network error counters per interface
ip -s link show eth0 | grep -A4 "RX:\|TX:"
```

---

## 7. Kernel Network Tuning — sysctl

### Production sysctl Network Settings

```bash
# /etc/sysctl.d/99-network-tuning.conf
# Apply with: sudo sysctl -p /etc/sysctl.d/99-network-tuning.conf

# ── TCP Buffer Sizes ─────────────────────────────────────────────────────────
# Increase TCP read/write buffer sizes (for high-throughput servers)
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# ── Connection Handling ──────────────────────────────────────────────────────
# Increase backlog for high-traffic servers
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535

# ── TIME_WAIT Optimisation ───────────────────────────────────────────────────
# Recycle and reuse TIME_WAIT sockets faster
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 1440000

# ── Keepalive ────────────────────────────────────────────────────────────────
net.ipv4.tcp_keepalive_time = 300       # Start keepalive after 5 min idle
net.ipv4.tcp_keepalive_intvl = 30       # Retry every 30 seconds
net.ipv4.tcp_keepalive_probes = 5       # Drop after 5 failed probes

# ── Security ─────────────────────────────────────────────────────────────────
# SYN flood protection
net.ipv4.tcp_syncookies = 1

# Disable IP source routing (prevents spoofing)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Disable ICMP redirects (prevent MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Enable reverse path filtering (drop spoofed packets)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Log martian packets (spoofed source IPs)
net.ipv4.conf.all.log_martians = 1

# Ignore broadcast pings (prevent Smurf attacks)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# ── File Descriptor Limits ───────────────────────────────────────────────────
# Allow more open sockets/files (for high-connection servers)
fs.file-max = 2097152
net.ipv4.ip_local_port_range = 1024 65535
```

```bash
# Apply immediately
sudo sysctl -p /etc/sysctl.d/99-network-tuning.conf

# Verify a specific setting
sysctl net.ipv4.tcp_syncookies
sysctl -a | grep somaxconn
```

---

## 8. Load Balancing — HAProxy and Nginx

### HAProxy — TCP and HTTP Load Balancing

```ini
# /etc/haproxy/haproxy.cfg — Production config

global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 50000

    # TLS settings
    ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-sslv3 no-tlsv10 no-tlsv11
    tune.ssl.default-dh-param 2048

defaults
    log global
    mode http
    option httplog
    option dontlognull
    option forwardfor        # X-Forwarded-For header
    option http-server-close
    timeout connect 5s
    timeout client  30s
    timeout server  30s
    timeout http-request 10s
    timeout http-keep-alive 10s
    timeout check 5s
    retries 3
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 503 /etc/haproxy/errors/503.http

# ── Stats Dashboard ────────────────────────────────────────────────────────
frontend stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s
    stats auth admin:StrongPassword123
    stats show-legends
    stats show-node

# ── HTTP → HTTPS Redirect ─────────────────────────────────────────────────
frontend http-in
    bind *:80
    http-request redirect scheme https unless { ssl_fc }

# ── HTTPS Frontend ─────────────────────────────────────────────────────────
frontend https-in
    bind *:443 ssl crt /etc/ssl/certs/example.com.pem
    http-request set-header X-Forwarded-Proto https

    # Rate limiting: 100 req/10s per IP
    stick-table type ip size 100k expire 30s store http_req_rate(10s)
    http-request track-sc0 src
    http-request deny if { sc_http_req_rate(0) gt 100 }

    # ACL-based routing
    acl api-path path_beg /api/
    acl static-path path_beg /static/ /media/

    use_backend api-servers if api-path
    use_backend static-servers if static-path
    default_backend web-servers

# ── Backend: Web Servers ──────────────────────────────────────────────────
backend web-servers
    balance roundrobin
    option httpchk GET /health HTTP/1.1\r\nHost:\ health-check
    http-check expect status 200

    server web1 10.0.1.10:8080 check inter 5s fall 3 rise 2 weight 1
    server web2 10.0.1.11:8080 check inter 5s fall 3 rise 2 weight 1
    server web3 10.0.1.12:8080 check inter 5s fall 3 rise 2 weight 1 backup

# ── Backend: API Servers ──────────────────────────────────────────────────
backend api-servers
    balance leastconn
    option httpchk GET /api/health
    http-check expect status 200
    cookie SERVERID insert indirect nocache   # Session stickiness

    server api1 10.0.1.20:8080 check cookie api1
    server api2 10.0.1.21:8080 check cookie api2

# ── Backend: Database (TCP mode) ─────────────────────────────────────────
backend postgres-primary
    mode tcp
    option tcp-check
    server db-primary 10.0.1.30:5432 check
    server db-standby 10.0.1.31:5432 check backup
```

```bash
# Validate config
haproxy -c -f /etc/haproxy/haproxy.cfg

# Reload without dropping connections
sudo systemctl reload haproxy

# Live stats via socket
echo "show stat" | sudo socat stdio /run/haproxy/admin.sock | cut -d',' -f1,2,18,19
echo "show info" | sudo socat stdio /run/haproxy/admin.sock | grep -E 'Uptime|MaxConn|CurrConns'
```

### Nginx — Upstream Load Balancing

```nginx
# /etc/nginx/conf.d/upstream.conf

upstream web_backend {
    least_conn;                    # Algorithm: round_robin | least_conn | ip_hash

    server 10.0.1.10:8080 weight=3 max_fails=3 fail_timeout=30s;
    server 10.0.1.11:8080 weight=3 max_fails=3 fail_timeout=30s;
    server 10.0.1.12:8080 weight=1 backup;      # Backup — used only when others fail

    keepalive 32;                  # Reuse connections to backends
}

upstream api_backend {
    ip_hash;                       # Sticky sessions by client IP

    server 10.0.1.20:8080;
    server 10.0.1.21:8080;

    keepalive 16;
}

server {
    listen 443 ssl http2;
    server_name api.example.com;

    # Health check (nginx plus or use proxy_next_upstream)
    location /api/ {
        proxy_pass         http://api_backend;
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;

        # Retry on upstream failure
        proxy_next_upstream error timeout http_500 http_502 http_503;
        proxy_next_upstream_tries 3;

        # Timeouts
        proxy_connect_timeout 5s;
        proxy_send_timeout    30s;
        proxy_read_timeout    30s;
    }
}
```

---

## 9. TLS/SSL — Certificates and Verification

### openssl — Certificate Inspection

```bash
# Check certificate on a live server
echo | openssl s_client -connect api.example.com:443 -servername api.example.com 2>/dev/null \
  | openssl x509 -noout -text | grep -E 'Subject:|Issuer:|Not After|DNS:'

# Check expiry date
echo | openssl s_client -connect api.example.com:443 2>/dev/null \
  | openssl x509 -noout -dates

# Days until expiry
EXPIRY=$(echo | openssl s_client -connect api.example.com:443 2>/dev/null \
  | openssl x509 -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
DAYS=$(( (EXPIRY_EPOCH - $(date +%s)) / 86400 ))
echo "Certificate expires in: $DAYS days"

# Check certificate file directly
openssl x509 -in /etc/ssl/certs/example.com.crt -noout -text
openssl x509 -in /etc/ssl/certs/example.com.crt -noout -dates
openssl x509 -in /etc/ssl/certs/example.com.crt -noout -subject -issuer

# Verify certificate chain
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/example.com.crt

# Check TLS supported protocols and ciphers
nmap --script ssl-enum-ciphers -p 443 api.example.com
openssl s_client -connect api.example.com:443 -tls1_2
openssl s_client -connect api.example.com:443 -tls1_3

# Test specific cipher
openssl s_client -connect api.example.com:443 -cipher 'ECDHE-RSA-AES256-GCM-SHA384'

# Generate self-signed certificate (for testing)
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
  -keyout /etc/ssl/private/test.key \
  -out /etc/ssl/certs/test.crt \
  -subj "/C=US/ST=CA/O=MyOrg/CN=api.example.com"
```

### Certificate Expiry Monitoring Script

```bash
#!/bin/bash
# Check certificate expiry for multiple domains
WARN_DAYS=30
DOMAINS=("api.example.com" "www.example.com" "auth.example.com")

for domain in "${DOMAINS[@]}"; do
  EXPIRY=$(echo | openssl s_client -connect "${domain}:443" -servername "$domain" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

  if [[ -z "$EXPIRY" ]]; then
    echo "UNREACHABLE: $domain"
    continue
  fi

  DAYS=$(( ($(date -d "$EXPIRY" +%s) - $(date +%s)) / 86400 ))
  if [[ $DAYS -lt $WARN_DAYS ]]; then
    echo "WARNING: $domain expires in $DAYS days ($EXPIRY)"
  else
    echo "OK: $domain — $DAYS days remaining"
  fi
done
```

---

## 10. VPN and Tunnels

### WireGuard — Modern VPN

```bash
# Install
sudo apt install wireguard

# Generate key pair
wg genkey | sudo tee /etc/wireguard/private.key | wg pubkey | sudo tee /etc/wireguard/public.key
sudo chmod 600 /etc/wireguard/private.key
```

```ini
# /etc/wireguard/wg0.conf — Server config
[Interface]
Address = 10.10.0.1/24
ListenPort = 51820
PrivateKey = <server-private-key>
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
# DevOps engineer workstation
PublicKey = <client-public-key>
AllowedIPs = 10.10.0.2/32

[Peer]
# CI/CD runner
PublicKey = <runner-public-key>
AllowedIPs = 10.10.0.3/32
```

```bash
# Enable and start
sudo systemctl enable --now wg-quick@wg0

# View status
sudo wg show
sudo wg show wg0 latest-handshakes

# Add a peer dynamically (without restart)
sudo wg set wg0 peer <pubkey> allowed-ips 10.10.0.4/32
```

### SSH Tunnels

```bash
# Local port forward: access remote DB locally
# Connect to prod-db:5432 via bastion, available at localhost:5433
ssh -L 5433:prod-db.internal:5432 bastion.example.com -N -f

# Remote port forward: expose local port on remote server
# Someone on bastion can reach your localhost:3000 via bastion:8080
ssh -R 8080:localhost:3000 bastion.example.com -N -f

# Dynamic SOCKS proxy (use as a proxy for any TCP traffic)
ssh -D 1080 bastion.example.com -N -f
# Then configure browser/app to use SOCKS5 proxy localhost:1080

# Persistent SSH tunnel with autossh
sudo apt install autossh
autossh -M 20000 -f -N \
  -L 5433:prod-db.internal:5432 \
  -o "ServerAliveInterval 30" \
  -o "ServerAliveCountMax 3" \
  bastion.example.com
```

---

## 11. Network Security Hardening

### fail2ban — Brute Force Protection

```bash
sudo apt install fail2ban

# /etc/fail2ban/jail.d/production.conf
```

```ini
[DEFAULT]
bantime  = 3600       # Ban for 1 hour
findtime = 600        # Within 10 minutes
maxretry = 5          # After 5 failures
banaction = iptables-multiport

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 86400      # 24 hours for SSH

[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log

[nginx-limit-req]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 10
```

```bash
sudo systemctl enable --now fail2ban

# View banned IPs
sudo fail2ban-client status sshd

# Unban an IP
sudo fail2ban-client set sshd unbanip 1.2.3.4

# View all jails
sudo fail2ban-client status
```

### Port Scan Detection with iptables

```bash
# Log and block port scans (NULL, XMAS, FIN scans)
sudo iptables -A INPUT -p tcp --tcp-flags ALL NONE -m limit \
  --limit 3/min -j LOG --log-prefix "NULL-SCAN: "
sudo iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP

sudo iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -m limit \
  --limit 3/min -j LOG --log-prefix "XMAS-SCAN: "
sudo iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP

sudo iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
sudo iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
```

### Disable Unused Network Services

```bash
# Find all listening services
sudo ss -tulnp

# Disable services you don't need
sudo systemctl disable --now avahi-daemon
sudo systemctl disable --now cups
sudo systemctl disable --now bluetooth
sudo systemctl disable --now rpcbind

# Prevent IPv6 if not needed
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.d/99-network-tuning.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.d/99-network-tuning.conf
sudo sysctl -p /etc/sysctl.d/99-network-tuning.conf
```

---

## 12. Production Networking Runbook

### Incident: No Network Connectivity

```bash
# Step 1: Is the interface up?
ip link show | grep -E 'eth0|ens|eno'
sudo ip link set eth0 up

# Step 2: Do we have an IP?
ip addr show eth0

# Step 3: Can we reach the gateway?
GW=$(ip route show default | awk '{print $3}')
ping -c4 $GW

# Step 4: Can we reach DNS?
ping -c2 8.8.8.8

# Step 5: Does DNS resolve?
dig +short api.example.com @8.8.8.8

# Step 6: Check for firewall blocking
sudo iptables -L INPUT -n -v | head -20
```

### Incident: High Network Latency

```bash
# Step 1: Is it our server or the path?
mtr --report -c 20 --no-dns 8.8.8.8

# Step 2: Check interface errors
ip -s link show eth0 | grep -A3 "RX:\|TX:"

# Step 3: Is the NIC saturated?
sudo iftop -i eth0 -n -t -s 5    # 5-second sample

# Step 4: Check TCP retransmissions
cat /proc/net/snmp | grep Tcp | awk '{print $13, $14, $15}'

# Step 5: Check for connection queue saturation
ss -s | grep TCP
cat /proc/sys/net/core/somaxconn
```

### Incident: Port Not Reachable from External

```bash
# Step 1: Is the service listening?
sudo ss -tulnp | grep :443

# Step 2: Is the service up?
systemctl status nginx

# Step 3: Firewall blocking?
sudo iptables -L INPUT -n -v | grep 443

# Step 4: Test locally
curl -v https://localhost/health

# Step 5: Test from another internal server
ssh 10.0.1.5 "nc -zv 10.0.1.10 443"

# Step 6: Is there a cloud security group / ACL?
# Check AWS/GCP/Azure console for inbound rules
```

---

## Quick Reference Card

```
# Interface
ip addr show                     All IPs
ip link show                     Interface state
ip -s link show eth0             Stats (errors, drops)

# Routing
ip route show                    Routing table
ip route get 8.8.8.8            Route for destination
ip route add/del                 Add/remove route

# DNS
dig +short hostname              DNS lookup
dig +trace hostname              Full delegation trace
resolvectl status                systemd-resolved status

# Ports
ss -tulnp                        Listening ports
ss -tnp state established        Active connections
ss -s                            Socket summary

# Firewall
iptables -L -n -v               View rules with counters
ufw status verbose               UFW rules
nft list ruleset                 nftables rules

# Capture
tcpdump -i eth0 port 80         Capture HTTP
tcpdump -i eth0 -w file.pcap   Save capture

# Performance
iftop -i eth0 -n                Bandwidth by connection
nethogs eth0                    Bandwidth by process
iperf3 -c server -t 30         Throughput test
```

---

*References: `man ip`, `man ss`, `man tcpdump`, `man iptables`, `man ufw`, `man dig`, `man nft`, `man haproxy`, [iproute2 docs](https://baturin.org/docs/iproute2/)*

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 03-networking
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
