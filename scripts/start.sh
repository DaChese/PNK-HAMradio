#!/usr/bin/env bash
# PNK Dashboard startup script
# Bring up all services in detached mode

echo "Starting PNK services..."
docker compose up -d

echo "Here are the running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"