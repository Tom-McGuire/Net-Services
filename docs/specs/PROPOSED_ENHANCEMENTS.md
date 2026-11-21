# Network Services (Net-Services) — Proposed Enhancements & Suite Integrations

---

## Issue 1: Passive mDNS / Bonjour Service Discovery Tab

### Summary
Add a lightweight **mDNS / Zeroconf Browser** tab alongside DHCP, NTP, DNS, and Wake-on-LAN to passively listen on `224.0.0.251:5353` and list advertised local network services and `.local` hostnames.

### Motivation
Field engineers and IoT/AV technicians frequently troubleshoot devices that rely on zero-configuration networking (`_sacn._udp`, `_artnet._udp`, `_dante._udp`, `_http._tcp`, `_smb._tcp`) rather than static DNS records. A passive mDNS monitor complements the built-in DNS server with zero external dependencies.

### Proposed Implementation
- Bind a multicast UDP listener to `224.0.0.251:5353` on the selected network interface.
- Decode DNS-SD `PTR`, `SRV`, `TXT`, and `A` resource records.
- Display a searchable table of discovered `.local` hostnames, IPv4 addresses, service types, ports, and `TXT` key-value metadata, with a 1-click **"Import to DNS Server"** action to pin discovered hosts into the local DNS table.

### Acceptance Criteria
- [ ] Starts/stops cleanly with the selected network interface and releases the multicast socket on exit.
- [ ] Displays live mDNS service announcements and allows one-click promotion to a static DNS record.
