: NOTE THIS IS STILL A WORK-IN-PROGRESS!

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

    Clone or update PNK‑HAMradio under cd PNK-HAMradio

    Deploy your static dashboard to /var/www/html/index.html

    Launch all PNK services:

        Etherpad

        FileBrowser

        Kolibri

        UniFi Controller (keep port 8080 opened and unobstructed so the controller can adopt an AC Mesh) 

        Hack-Chat (Local Chat room)

2. Start & Access

If you need to restart or bring up the stack manually:

cd PNK-HAMradio
docker compose up -d or sudo docker compose restart

Then point your browser at:
Service	URL / local host or IP given by router or switch.
Etherpad	http://<YOUR_PI_IP>/
FileBrowser	http://<YOUR_PI_IP>:8081
Kolibri	http://<YOUR_PI_IP>:8082
UniFi Controller	https://<YOUR_PI_IP>:8443
Hack-Chat	http://<YOUR_PI_IP>:8083

    If you chose the Lighttpd reverse‑proxy setup, Etherpad will live at /pad instead of root.
    Also Pat-Winlink uses the port 8080 which conflicts with the adoption process for the Unifi Controller for AC Meshes (bunny ears). So be mindful about it, I havent figured out how to change the port for Pat-Winlink. Although if you dont install 73Linux or dont choose the option to install Pat-Winlink through the installer ( be careful of what you install from 73Linux some of it could override some of the PNK stuff) for 73Linux then there should be no errors or issues for adopting Unifi devices.

3. Credits & Related Projects

This project wouldn’t be possible without some awesome open‑source work:

    73Linux by km4ack (https://github.com/km4ack/73Linux)
(YouTube channel https://youtube.com/@km4ack)
    A lightweight installer for HAM‑radio toolchains on Debian‑based systems.

    SDR++ via TekMaker/sdrplus (https://github.com/TekMaker/SDRplus)
    A modern, Qt‑based SDR client for various radio front‑ends.
    Tested here with an RTL‑SDR USB dongle for receiving HF/VHF/UHF.

Feel free to explore those repos if you just want the radio‑specific bits.

Also Features Added

Hack.Chat: A secure, minimal chatroom interface for local/offline messaging.

modBot: A customizable moderation bot that can issue bans, respond to commands, and filter users.

Potential Plans for adding AI-powered chatbots for offline use.

Hack.Chat

GitHub: https://github.com/hack-chat/main

Lightweight self-hosted chat platform using WebSocket + static frontend

modBot by ToastyStoemp

GitHub: https://github.com/ToastyStoemp/modBot

A moderation and command bot built for Hack.Chat

WebFreak001's API Tools

Used by modBot for various web utilities and URL parsing

This project is part of an ongoing effort to build offline-ready, resilient community internet infrastructure using the Raspberry Pi. Contributions welcome!
