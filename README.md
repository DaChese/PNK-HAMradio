# PNK-HAMradio

Turn your Raspberry Pi into a Portable Network Kit and HAM-radio hub.

---

## 1. Prerequisites

- **OS**: Raspberry Pi OS Lite (64-bit ARM) or any Debian-based Linux  
- **Docker** & **Docker Compose** (or the Docker plugin) installed  
- *Optional:* your user in the `docker` group so you can run containers without `sudo`

---

## 2. Clone & Install

```bash
git clone https://github.com/DaChese/PNK-HAMradio.git
cd PNK-HAMradio

chmod +x install.sh
sudo ./install.sh

    The installer will:

        Install system packages (Git, Lighttpd, etc.)

        Install Docker via the official script

        Clone or update PNK-HAMradio under /opt/pnk-hamradio

        Generate a Dendrite (Matrix) server key if needed

        Deploy your static dashboard to /var/www/html/index.html

        Launch all PNK services (Etherpad, FileBrowser, Kolibri, UniFi, Matrix, Element)

3. Start & Access

Bring up your stack (if you ever need to restart):

cd PNK-HAMradio
docker compose up -d

Then point your browser at:

    Etherpad (dashboard root) http://<YOUR_PI_IP>/

    FileBrowser http://<YOUR_PI_IP>:8081

    Kolibri http://<YOUR_PI_IP>:8082

    UniFi Controller https://<YOUR_PI_IP>:8443

    Matrix (Dendrite) http://<YOUR_PI_IP>:8008

    Element (web chat) http://<YOUR_PI_IP>:8083

(If you chose the reverse-proxy setup in Lighttpd, Etherpad will live at /pad instead of root.)

4. Credits & Related Projects

This project wouldn’t be possible without some awesome open-source work:

    73Linux by km4ack
    A lightweight installer for HAM-radio toolchains on Debian-based systems.

    SDR++ via TekMaker/sdrplus
    A modern, Qt-based SDR client for various radio front-ends.

Feel free to explore those repos if you just want the radio-specific bits.
