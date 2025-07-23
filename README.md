
## 1. Prerequisites

- **OS**: Raspberry Pi OS Lite (64-bit ARM) or any Debian-based Linux  
- **Docker** & **Docker Compose** (or the Docker plugin) installed  
- *Optional:* your user in the `docker` group so you can run containers without `sudo`

---

# PNK‑HAMradio

Turn a Raspberry Pi into a Portable Network Kit **and** HAM‑radio platform.

---

## 1. Quick Install

```bash
git clone https://github.com/DaChese/PNK-HAMradio.git
cd PNK-HAMradio

chmod +x install.sh
sudo ./install.sh

The installer will:

    Install system packages (Git, Lighttpd, etc.)

    Install Docker via the official script

    Clone or update PNK‑HAMradio under /opt/pnk-hamradio

    Generate a Dendrite (Matrix) server key if needed

    Deploy your static dashboard to /var/www/html/index.html

    Launch all PNK services:

        Etherpad

        FileBrowser

        Kolibri

        UniFi Controller

        Matrix (Dendrite)

        Element (Web Chat)

2. Start & Access

If you need to restart or bring up the stack manually:

cd PNK-HAMradio
docker compose up -d

Then point your browser at:
Service	URL
Etherpad	http://<YOUR_PI_IP>/
FileBrowser	http://<YOUR_PI_IP>:8081
Kolibri	http://<YOUR_PI_IP>:8082
UniFi Controller	https://<YOUR_PI_IP>:8443
Matrix (Dendrite)	http://<YOUR_PI_IP>:8008
Element (Web Chat)	http://<YOUR_PI_IP>:8083

    If you chose the Lighttpd reverse‑proxy setup, Etherpad will live at /pad instead of root.

3. Credits & Related Projects

This project wouldn’t be possible without some awesome open‑source work:

    73Linux by km4ack
    A lightweight installer for HAM‑radio toolchains on Debian‑based systems.

    SDR++ via TekMaker/sdrplus
    A modern, Qt‑based SDR client for various radio front‑ends.
    Tested here with an RTL‑SDR USB dongle for receiving HF/VHF/UHF.

Feel free to explore those repos if you just want the radio‑specific bits.
