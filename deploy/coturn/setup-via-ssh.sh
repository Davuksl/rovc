#!/usr/bin/env bash
# RovC TURN Server — remote deploy via SSH
# Usage:
#   export TURN_SERVER_IP=123.456.789.0
#   export TURN_PASSWORD="your-secret"
#   bash deploy/coturn/setup-via-ssh.sh

set -euo pipefail

IP="${TURN_SERVER_IP:?Set TURN_SERVER_IP}"
PASS="${TURN_PASSWORD:?Set TURN_PASSWORD}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "→ Deploying coturn to $IP ..."

ssh "root@$IP" bash <<ENDSSH
set -e

# Install docker if missing
if ! command -v docker &>/dev/null; then
  apt-get update -qq
  apt-get install -y -qq docker.io docker-compose-v2
fi

mkdir -p /opt/rovc-turn

# Copy config files
cat > /opt/rovc-turn/turnserver.conf <<'CONF'
listening-port = 3478
listening-ip = 0.0.0.0
relay-ip = 0.0.0.0
external-ip = $IP
fingerprint
lt-cred-mech
user = rovc:$PASS
realm = rovc.voice
total-quota = 100
min-port = 49152
max-port = 65535
no-loopback-peers
no-multicast-peers
mobility
CONF

cat > /opt/rovc-turn/docker-compose.yml <<'COMPOSE'
services:
  coturn:
    image: instrumentisto/coturn:latest
    container_name: rovc-turn
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./turnserver.conf:/etc/coturn/turnserver.conf:ro
COMPOSE

cd /opt/rovc-turn
docker compose pull
docker compose up -d

echo "✓ TURN running on $IP:3478"
ENDSSH

echo ""
echo "=== Done ==="
echo "WebRTC ICE config for mesh-voice.js:"
echo ""
echo "turnUrl:      turn:$IP:3478"
echo "turnUsername: rovc"
echo "turnCredential: $PASS"
echo ""
echo "Make sure UDP ports 3478, 49152-65535 are open in the VPS firewall."
