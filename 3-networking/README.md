# 03 - Linux Networking for DevOps

> **Production-grade Linux networking** — covering IP configuration, routing, DNS, firewall, load balancing, network diagnostics, performance tuning, and security hardening for real-world DevOps environments.

---

## 📁 Module Structure

```
03-networking/
├── README.md                          ← You are here
├── networking.md                      ← Deep-dive reference guide
├── scripts/
    ├── network-diagnostics.sh         ← Full network health check
    ├── firewall-setup.sh              ← iptables/ufw production ruleset
    ├── bandwidth-monitor.sh           ← Real-time bandwidth usage per interface/process
    └── dns-check.sh                   ← DNS resolution and propagation tester

```

---

## 🚀 Quick Start

### View current network configuration

```bash
# IP addresses on all interfaces
ip addr show

# Routing table
ip route show

# DNS resolver config
cat /etc/resolv.conf

# Listening ports and services
sudo ss -tulnp
```

### Test connectivity fast

```bash
# Layer 3: ICMP reachability
ping -c4 8.8.8.8

# Layer 4: TCP port check
nc -zv 10.0.1.5 443

# DNS resolution
dig +short api.example.com

# HTTP response code
curl -sIo /dev/null -w "%{http_code}\n" https://api.example.com/health
```

### Capture traffic on a port

```bash
sudo tcpdump -i eth0 -n port 443 -c 50
```

---

## 📚 Topics Covered

| Topic | Description |
|---|---|
| [IP & Interface Config](#) | ip addr, ip link, netplan, static/dynamic IP |
| [Routing](#) | ip route, policy routing, static routes |
| [DNS](#) | resolv.conf, systemd-resolved, dig, nslookup |
| [Firewall](#) | iptables, nftables, ufw — rules and hardening |
| [Network Diagnostics](#) | ping, traceroute, mtr, ss, netstat, tcpdump |
| [Bandwidth & Performance](#) | iftop, nethogs, iperf3, sysctl tuning |
| [Load Balancing](#) | HAProxy, nginx upstream, keepalived |
| [TLS/SSL](#) | openssl, certificate verification, SNI |
| [VPN & Tunnels](#) | WireGuard, SSH tunnels, port forwarding |
| [Network Security](#) | fail2ban, port knocking, connection limiting |

---

## ⚡ Production Networking Checklist

- [ ] Assign static IPs to all production servers via netplan/nmcli
- [ ] Configure DNS with primary + fallback resolvers
- [ ] Enable and harden firewall — default deny inbound, allow only required ports
- [ ] Disable unused network services and protocols
- [ ] Set up NTP synchronisation (`timedatectl`, `chrony`)
- [ ] Configure network interface bonding/teaming for redundancy
- [ ] Tune kernel network parameters (`sysctl`) for throughput and security
- [ ] Enable TCP SYN cookies to prevent SYN flood attacks
- [ ] Monitor open ports — alert on unexpected listeners
- [ ] Set up fail2ban for SSH and web services
- [ ] Document all firewall rules in version control

---

## 🛠️ Essential Networking Commands — Quick Reference

```bash
# Interface management
ip addr show                        # All IPs on all interfaces
ip link show                        # Link state (UP/DOWN/speed)
ip addr add 10.0.1.5/24 dev eth0   # Add IP (temporary)
ip link set eth0 up/down            # Bring interface up/down

# Routing
ip route show                       # Routing table
ip route add default via 10.0.1.1  # Add default gateway
ip route get 8.8.8.8               # Which interface/gateway for a destination

# DNS
dig api.example.com                 # DNS lookup
dig +short @8.8.8.8 example.com    # Query specific DNS server
resolvectl query example.com        # Via systemd-resolved
nslookup -type=MX example.com      # MX record lookup

# Ports and connections
ss -tulnp                           # Listening ports with process names
ss -tnp state established           # Active TCP connections
ss -s                               # Socket statistics summary

# Firewall
sudo ufw status verbose             # UFW rules
sudo iptables -L -n -v              # iptables rules with counters
sudo nft list ruleset               # nftables rules

# Diagnostics
ping -c4 -I eth0 8.8.8.8           # ICMP via specific interface
traceroute -n 8.8.8.8              # Hop-by-hop path
mtr --report --no-dns 8.8.8.8      # Combined ping + traceroute report
nc -zv host 443                    # TCP port check
curl -v --resolve host:443:IP URL  # Force IP for hostname

# Traffic capture
sudo tcpdump -i eth0 -n port 80    # Capture HTTP traffic
sudo tcpdump -i eth0 -w dump.pcap  # Save capture for Wireshark

# Bandwidth
sudo iftop -i eth0 -n              # Bandwidth by connection
sudo nethogs eth0                  # Bandwidth by process
iperf3 -c 10.0.1.5 -t 10          # Throughput test to a server
```

---

## 🔗 See Also

- [networking.md] — full reference with all commands and production examples
- [Linux Networking Internals](https://www.kernel.org/doc/html/latest/networking/)
- [Netfilter / iptables](https://www.netfilter.org/documentation/)
- [HAProxy Documentation](https://www.haproxy.org/download/2.8/doc/configuration.txt)
- [WireGuard](https://www.wireguard.com/quickstart/)
- [iproute2 Cheat Sheet](https://baturin.org/docs/iproute2/)

---

<!-- IMMUTABLE SIGNATURE — DO NOT EDIT OR REMOVE -->
> **Author:** Eknatha
> **Repository:** linux-for-devops / 03-networking
> *This document is authored and maintained by Eknatha. Unauthorized modification of this signature is prohibited.*
<!-- END SIGNATURE -->
