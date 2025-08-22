# PNK-HAMradio

> **Status:** Work-in-progress. Expect rough edges

Turn a Raspberry Pi into a Portable Network Kit (PNK) **and** HAM-radio platform.  
Ships with a lightweight web dashboard plus offline-friendly services (Etherpad, FileBrowser, Kolibri, UniFi Controller) and a minimal local chat (HackChat).

---

**Quick nav**
- [Prerequisites](#0-prerequisites)
- [Quick Start](#1-quick-start)
- [Install Modes](#2-install-modes)
- [Services & URLs](#3-services--urls)
- [Helpful Commands](#4-helpful-commands)
- [Updating](#5-updating)
- [Troubleshooting](#6-troubleshooting)
- [Credits & Related Projects](#7-credits--related-projects)

---

## 0. Prerequisites

- **Hardware/OS:** Raspberry Pi (64-bit) on **Raspberry Pi OS Lite** or any Debian-based Linux.
- **Network:** Basic LAN access. If adopting UniFi devices, keep **TCP 8080** unobstructed.
- **Docker:** Optional — installer can set this up for you (omit with `--no-docker`).

---

## 1. Quick Start

```bash
git clone https://github.com/DaChese/PNK-HAMradio.git
cd PNK-HAMradio

# Full stack (Docker apps + HackChat + dashboard)
sudo bash pnk-ham-install.sh --install

# Include Status/Logs API (adds /status and /logs/)
sudo bash pnk-ham-install.sh --install --logs-api

What the installer does:

    Installs base packages (Git, Lighttpd, etc.)

    Installs Docker (unless you pass --no-docker)

    Clones/updates the repo into ~/PNK-HAMradio

    Deploys the dashboard to /var/www/html/index.html

    Sets up HackChat bare-metal under systemd and proxies WS at /chat-ws

    (Optional) Installs the PNK Logs API and proxies /status + /logs/

    Starts Docker services (Etherpad, FileBrowser, Kolibri, UniFi)

Browse to: http://<pi-ip>/
2. Install Modes

# Standard (Docker apps + HackChat + dashboard)
sudo bash pnk-ham-install.sh --install

# Add Status/Logs API (exposes /status + /logs/)
sudo bash pnk-ham-install.sh --install --logs-api

# Bare-metal only (no Docker compose)
sudo bash pnk-ham-install.sh --install --logs-api --no-docker

# Patch only the dashboard HTML (no services touched)
sudo bash pnk-ham-install.sh --update --patch-dashboard-only

# Update everything in place
sudo bash pnk-ham-install.sh --update

# Uninstall HackChat and Logs API (proxies remain)
sudo bash pnk-ham-install.sh --uninstall

3. Services & URLs
Service	Default URL	Notes
Dashboard	http://<pi-ip>/	Static HTML via Lighttpd
Etherpad	http://<pi-ip>:9001/	Collaborative notes
FileBrowser	http://<pi-ip>:8081/	File manager
Kolibri	http://<pi-ip>:8082/	Offline learning
UniFi UI	https://<pi-ip>:8443/	UI is 8443; adoption/inform uses port 8080
HackChat (client)	https://hack.chat/?pnk&ws=wss://<pi-host>/chat-ws	Dashboard “Open Chat” points here
HackChat (WS)	ws(s)://<pi-host>/chat-ws → pi-ipaddress:6060	Proxied by Lighttpd
Status JSON opt.	http://<pi-ip>/status	Aggregated systemd + HTTP/TCP checks
Logs API opt.	http://<pi-ip>/logs/<service>?lines=200	Live tail via SSE at /logs/<service>/stream

    ⚠️ UniFi vs. Pat-Winlink: UniFi adoption needs TCP 8080 free. If Pat-Winlink claims 8080, stop it during adoption or change its port.

4. Helpful Commands
Installer & Dashboard

# Full install (+ Logs API)
sudo bash pnk-ham-install.sh --install --logs-api

# Patch only the dashboard HTML (safe anytime)
sudo bash pnk-ham-install.sh --update --patch-dashboard-only

Docker Apps (Etherpad, FileBrowser, Kolibri, UniFi)

cd ~/PNK-HAMradio

# Start/Update stack (pull latest images)
docker compose up -d --remove-orphans

# Restart a single container
docker compose restart etherpad

# View container logs
docker logs -f etherpad

HackChat (bare-metal via systemd)

# Status / live logs / restart
systemctl status hackchat --no-pager
journalctl -u hackchat -f
sudo systemctl restart hackchat

Logs API & Status (if enabled)

# Service status
systemctl status pnk-logs-api --no-pager
journalctl -u pnk-logs-api -n 200 --no-pager
sudo systemctl restart pnk-logs-api

# API checks (local)
curl -s http://127.0.0.1:6061/healthz
curl -s http://127.0.0.1:6061/status | jq | head
curl -s "http://127.0.0.1:6061/logs/hackchat-websocket?lines=50"

# Via Lighttpd (LAN clients)
curl -s http://<pi-ip>/status | jq | head
curl -s "http://<pi-ip>/logs/hackchat-websocket?lines=50"

# Live log tail (SSE) from a browser:
# new EventSource('/logs/hackchat-websocket/stream?since=1m')

Lighttpd (web/proxy)

# Test config and reload
sudo lighttpd -tt -f /etc/lighttpd/lighttpd.conf
sudo systemctl reload lighttpd

Paths

/var/www/html/index.html        # Dashboard
/opt/hackchat                   # HackChat checkout + .hcserver.json
/opt/pnk-logs-api               # Logs API (server.js + config.json)
/home/<user>/PNK-HAMradio       # Repo & docker compose

5. Updating

    Re-run the installer with --update (idempotent).

    Docker services only:

cd ~/PNK-HAMradio
docker compose pull && docker compose up -d --remove-orphans

HackChat only:

    sudo systemctl restart hackchat

6. Troubleshooting

    Dashboard not updating: hard refresh (Ctrl+F5) after running the installer.

    HackChat not connecting: ensure hackchat systemd service is active and /chat-ws proxy is present.

    UniFi adoption failing: make sure TCP 8080 is free (stop Pat-Winlink temporarily if needed).

    CORS issues: use same-origin paths /status and /logs/ (Lighttpd proxies to 127.0.0.1:6061).

7. Credits & Related Projects

Hack.Chat — https://github.com/hack-chat/main
    Minimal WebSocket chat server + static client.

73Linux (km4ack) — https://github.com/km4ack/73Linux
    HAM-radio toolchain installer for Debian-based systems.

SDR++ (TekMaker/SDRplus) — https://github.com/TekMaker/SDRplus
    Modern SDR client; tested with RTL-SDR.

This project supports offline-ready, resilient community networking with Raspberry Pi. Contributions are welcomed!
