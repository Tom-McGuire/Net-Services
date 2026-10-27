# Network Services (Net-Services)

A portable, cross-platform local network services utility desktop application built with **Flutter Desktop** (Linux, Windows, macOS).

Part of the **Network Services Family** alongside [Syslog Server](https://github.com/Tom-McGuire/Syslog-Server) and [Packet Inspector](https://github.com/Tom-McGuire/Packet-Inspector).

Designed for network engineers, embedded/IoT developers, system administrators, and testers who need to quickly spin up, configure, and monitor essential network services (**DHCP Server**, **Network Time / NTP Server**, **DNS Server**, and **Wake-on-LAN**) on demand with zero external dependencies.

---

## ✨ Features

### 🔀 Independent Service Controls
- Run **DHCP**, **NTP**, and **DNS** servers individually or all together with independent Start/Stop toggles.
- Standard privileged ports (DHCP `67`, NTP `123`, DNS `53`) alongside quick unprivileged test presets (`6767`, `1123`, `5353`).
- Clean application lifecycle: all sockets, leases, and timers are gracefully stopped and freed on window exit.

### 🌐 DHCP Server (RFC 2131 & RFC 2132)
- **Intelligent Auto-Configuration**:
  - **Starting IP (First Address)** defaults automatically to **Host IP + 1** (e.g. `10.101.1.51`), fully editable.
  - **Subnet Mask** auto-detected from active network interface CIDR prefix (e.g. `/24` &rarr; `255.255.255.0`), fully editable.
  - **Router / Default Gateway & DNS Server** pre-populated with host IP address.
  - **Local DNS Advertising**: Option to hand out host machine's IP as DNS server to resolve local hostnames.
  - **Range Size** input with real-time dynamic calculation of the **Last Address**.
- **Active Leases Table**:
  - Real-time tracking of assigned IP addresses, client MAC addresses, client hostnames, expiration countdowns, and active status.
- **Protocol Handshake**:
  - Complete `DISCOVER` &rarr; `OFFER`, `REQUEST` &rarr; `ACK`, and `RELEASE` support.

### ⏰ Network Time / NTP Server (RFC 5905)
- **Local Time Source**: Serves the host machine's local clock directly to clients.
- **RFC 5905 Compliance**: 48-byte Mode 4 server replies for client Mode 3 requests with Stratum 10 reference ID (`LOCL`).
- **Live Digital Clock Hero**:
  - High-precision display of Local Time, UTC Time, Timezone, and NTP Epoch seconds (since January 1, 1900).
- **Time Sync Audit Log**: Real-time log of client sync requests with IP, port, and response timestamps.

### 🔎 DNS Server (RFC 1035)
- **Interactive Mapping Management**:
  - Easily add, edit, and delete custom Domain/Hostname &rarr; Target IP address records (e.g. `router.local` &rarr; `192.168.1.1`).
  - Wildcard match fallback support.
- **Live Query Resolution Feed**:
  - Real-time logging of incoming DNS queries with resolution status (`RESOLVED` vs `NXDOMAIN`), transaction IDs, and client IP addresses.

### ⚡ Wake-on-LAN (WOL)
- **Magic Packet Generator**: Broadcast standard 102-byte Magic Packets (UDP port 9 or 7) to wake remote network devices.
- **ARP IP-to-MAC Resolver**: Enter the IP address of any online host on the local subnet to automatically query the system ARP cache and resolve its hardware MAC address.
- **Persistent Device Profiles**: Label and save machines with persistent local JSON storage (`wol_devices.json`) and instant one-click wake triggers.

### 📊 Unified Activity Log & Event Inspector
- Unified chronological log stream across all services with search and filtering (`ALL`, `DHCP`, `NTP`, `DNS`, `WOL`).
- **Resizable Event Inspector Panel**: Vertically resizable bottom inspector with drag handle, maximize/restore toggle, and persistent height. Click any log entry or lease to inspect raw packet fields, timestamps, client addresses, and transaction details.
- **Export**: One-click export of captured logs to **CSV** or **JSON**.

### 🎨 Family Design System Alignment
- Matches the Dark Material 3 theme (`#141414` canvas, `#1E1E1E` panels, `#007ACC` accent, `#3E3E42` borders) of **Syslog Server** and **Packet Inspector**.
- Monospace formatting for IPs, MACs, ports, and timestamps.
- **Top Control Bar**: Network interface selector dropdown, elevated root privilege badge, Start All / Stop All buttons, and clear logs confirmation modal.
- **Global Error Banner**: Surfaces socket exceptions and permission requirements with instant troubleshooting tips.

---

## 🚀 Getting Started

### 🛡️ Note on Windows / macOS Security Prompts

These tools are free and independent projects and are not yet code-signed with expensive commercial certificates:

- **Windows**: If SmartScreen appears, click "More info" &rarr; "Run anyway".
- **macOS**: Right-click the `.app` file, select **Open**, and confirm the prompt (or run `xattr -c NetServices.app` in Terminal).

### Prerequisites
- [Flutter SDK](https://flutter.dev) (version 3.13+ or higher)
- C/C++ build tools for your platform (e.g., `build-essential`, `clang`, `cmake`, `ninja-build` on Linux)

### Installation & Run

```bash
# Clone the repository
git clone https://github.com/Tom-McGuire/Net-Services.git
cd Net-Services

# Get dependencies
flutter pub get

# Run on Linux Desktop
flutter run -d linux

# Run on Windows Desktop
flutter run -d windows

# Run on macOS Desktop
flutter run -d macos
```

### Running with Privileged Ports (< 1024)
Binding standard ports (**53**, **67**, **123**) requires elevated privileges on Linux and macOS:

1. **Option A (Recommended for production/root)**:
   ```bash
   sudo ./build/linux/x64/release/bundle/net_services
   ```
2. **Option B (Linux capability without root)**:
   ```bash
   sudo setcap 'cap_net_bind_service=+ep' build/linux/x64/release/bundle/net_services
   ```
3. **Option C (Unprivileged testing)**:
   Use the built-in preset dropdown in each service to select unprivileged test ports:
   - DNS: `5353`
   - NTP: `1123`
   - DHCP: `6767`

---

## 🧪 Testing

Run the full automated test suite:

```bash
flutter test
```

Includes unit tests for DNS RFC 1035 packet encoding/decoding, NTP RFC 5905 48-byte responses, DHCP lease allocation/range calculations, DHCP handshake packet serialization, Wake-on-LAN Magic Packet generation and MAC parsing, and widget smoke tests.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
