#!/usr/bin/env bash
# PNK Dashboard startup script
# Bring up all services in detached mode

for svc in etherpad filebrowser kolibri unifi-controller dendrite element; do
  docker rm -f $svc 2>/dev/null || true
done

echo "Starting PNK services..."
docker compose down
docker compose pull
docker compose up -d

echo "Here are the running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"