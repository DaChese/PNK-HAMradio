#!/usr/bin/env bash
# PNK Dashboard startup script (Docker services only)
# - Starts Etherpad, FileBrowser, Kolibri, UniFi
# - Leaves HackChat to systemd (bare-metal)
# - Optional readiness checks

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# -------- Settings (override via env) --------
PNK_WAIT="${PNK_WAIT:-true}"        # set to "false" to skip readiness checks
ETHERPAD_URL="${ETHERPAD_URL:-http://127.0.0.1:9001/}"
FILEBROWSER_URL="${FILEBROWSER_URL:-http://127.0.0.1:8081/}"
KOLIBRI_URL="${KOLIBRI_URL:-http://127.0.0.1:8082/}"
UNIFI_URL="${UNIFI_URL:-https://127.0.0.1:8443/}"   # UniFi UI is on 8443

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
  local t=0
  printf "Waiting for %-16s" "$name"
  while (( t < timeout )); do
    code="$(curl "${flags[@]}" "$url" || true)"
    if [[ "$code" =~ ^2|3 ]]; then
      printf "\r"; ok "$name is up ($url)"
      return 0
    fi
    printf "\rWaiting for %-16s (%02ds)..." "$name" "$((timeout - t))"
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

# -------- Clean up legacy containers that we no longer use --------
# (Matrix/Element were replaced by HackChat bare-metal)
for stale in dendrite element; do
  docker rm -f "$stale" >/dev/null 2>&1 || true
done

# -------- Bring up the stack --------
log "Stopping any existing stack (removing orphans)..."
$COMPOSE down --remove-orphans || true

log "Pulling latest images..."
$COMPOSE pull

log "Starting PNK services (detached)..."
$COMPOSE up -d --remove-orphans

# -------- Readiness checks (optional) --------
wait_http "$ETHERPAD_URL"    "Etherpad"       40 || true
wait_http "$FILEBROWSER_URL" "FileBrowser"    40 || true
wait_http "$KOLIBRI_URL"     "Kolibri"        60 || true
wait_http "$UNIFI_URL"       "UniFi UI"       60 true || true  # allow self-signed

# -------- Show what's running --------
log "Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# -------- HackChat (systemd) quick status --------
if systemctl list-unit-files | grep -q '^hackchat\.service'; then
  if systemctl is-active --quiet hackchat; then
    ok "HackChat (systemd) is active.   View logs: sudo journalctl -u hackchat -f"
  else
    err "HackChat (systemd) is not active. Start it: sudo systemctl start hackchat"
  fi
else
  echo "ℹ HackChat systemd unit not found (expected if not installed yet)."
fi

echo
ok "PNK startup complete."
