#!/usr/bin/env bash
# PNK Dashboard startup script (Docker services only)
# - Starts Etherpad, FileBrowser, Kolibri, UniFi (docker compose)
# - Leaves HackChat + OpenWebRX to systemd (bare-metal)
# - Optional readiness checks incl. /radio Lighttpd proxy

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# -------- Settings (override via env) --------
PNK_WAIT="${PNK_WAIT:-true}"        # set to "false" to skip readiness checks

ETHERPAD_URL="${ETHERPAD_URL:-http://127.0.0.1:9001/}"
FILEBROWSER_URL="${FILEBROWSER_URL:-http://127.0.0.1:8081/}"
KOLIBRI_URL="${KOLIBRI_URL:-http://127.0.0.1:8082/}"
UNIFI_URL="${UNIFI_URL:-https://127.0.0.1:8443/}"         # UniFi UI is on 8443

# OpenWebRX (bare-metal) health checks
WAIT_OWRX="${WAIT_OWRX:-true}"
OWRX_BACKEND_URL="${OWRX_BACKEND_URL:-http://127.0.0.1:8073/sdr/}"   # was http://127.0.0.1:8073/
OWRX_PROXY_URL="${OWRX_PROXY_URL:-http://127.0.0.1/radio/}"

STATUS_URL="${STATUS_URL:-http://127.0.0.1/status}"              # Logs API (optional)

# -------- Helpers --------
log() { echo -e "\e[1;36m==>\e[0m $*"; }
ok()  { echo -e "\e[1;32m✔\e[0m $*"; }
err() { echo -e "\e[1;31m✘\e[0m $*" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

wait_http() {
  local url="$1" name="$2" timeout="${3:-30}" insecure="${4:-false}"
  [[ "$PNK_WAIT" != "true" ]] && { echo "skip wait: $name"; return 0; }
  local flags=(-sS -o /dev/null -w "%{http_code}")
  [[ "$insecure" == "true" ]] && flags=(-k "${flags[@]}")
  local t=0 code
  printf "Waiting for %-20s" "$name"
  while (( t < timeout )); do
    code="$(curl "${flags[@]}" "$url" || true)"
    if [[ "$code" =~ ^2|^3 ]]; then
      printf "\r"; ok "$name is up ($url)"
      return 0
    fi
    printf "\rWaiting for %-20s (%02ds)..." "$name" "$((timeout - t))"
    sleep 1; ((t++))
  done
  printf "\r"; err "$name not responding at $url (timeout ${timeout}s)"
  return 1
}

# -------- Pre-flight --------
if ! have docker; then
  err "Docker is not installed or not in PATH."
  exit 1
fi
# Prefer plugin syntax; fallback to docker-compose if needed
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif have docker-compose; then
  COMPOSE="docker-compose"
else
  err "Neither 'docker compose' nor 'docker-compose' is available."
  exit 1
fi

# -------- Clean up legacy containers we no longer use --------
for stale in dendrite element openwebrx; do
  docker rm -f "$stale" >/dev/null 2>&1 || true
done

# -------- Bring up the stack --------
log "Stopping any existing stack (removing orphans)…"
$COMPOSE down --remove-orphans || true

log "Pulling latest images…"
$COMPOSE pull

log "Starting PNK services (detached)…"
$COMPOSE up -d --remove-orphans

# -------- Readiness checks (optional) --------
wait_http "$ETHERPAD_URL"    "Etherpad"          40 || true
wait_http "$FILEBROWSER_URL" "FileBrowser"       40 || true
wait_http "$KOLIBRI_URL"     "Kolibri"           60 || true
wait_http "$UNIFI_URL"       "UniFi UI"          60 true || true  # allow self-signed

if [[ "$WAIT_OWRX" == "true" ]]; then
  # OpenWebRX is bare-metal; check both backend port and the Lighttpd proxy
  if systemctl list-unit-files | grep -q '^openwebrx\.service'; then
    wait_http "$OWRX_BACKEND_URL" "OpenWebRX backend" 60 || true
  fi
  wait_http "$OWRX_PROXY_URL"   "OpenWebRX /radio"    60 || true
fi

# Optional: Logs API status endpoint
if curl -fsS "$STATUS_URL" >/dev/null 2>&1; then
  ok "Status API reachable at $STATUS_URL"
fi

# -------- Show what's running --------
log "Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# -------- HackChat (systemd) quick status --------
if systemctl list-unit-files | grep -q '^hackchat\.service'; then
  if systemctl is-active --quiet hackchat; then
    ok "HackChat (systemd) is active.   Logs: sudo journalctl -u hackchat -f"
  else
    err "HackChat (systemd) is not active. Start it: sudo systemctl start hackchat"
  fi
else
  echo "ℹ HackChat systemd unit not found (expected if not installed yet)."
fi

# -------- OpenWebRX (systemd) quick status --------
if systemctl list-unit-files | grep -q '^openwebrx\.service'; then
  if systemctl is-active --quiet openwebrx; then
    ok "OpenWebRX (systemd) is active on :8073.  Logs: sudo journalctl -u openwebrx -f"
  else
    err "OpenWebRX (systemd) is not active. Start it: sudo systemctl start openwebrx"
  fi
else
  echo "ℹ OpenWebRX systemd unit not found (install with --openwebrx)."
fi

echo
ok "PNK startup complete."
