#!/bin/bash
# kijanikiosk-incident-setup.sh
# Injects three production-realistic faults into the staging server.
# Run as: sudo bash kijanikiosk-incident-setup.sh

set -euo pipefail
echo "[setup] Injecting faults into staging server..."

# --- FAULT 1: Disk I/O saturation via log accumulation ---
echo "[fault-1] Generating log accumulation to saturate write I/O..."
mkdir -p /opt/kijanikiosk/shared/logs
# Write 1.5GB of data to simulate weeks of unrotated logs
dd if=/dev/urandom bs=1M count=512 \
  of=/opt/kijanikiosk/shared/logs/payments-2024-03-10.log status=progress
dd if=/dev/urandom bs=1M count=512 \
  of=/opt/kijanikiosk/shared/logs/payments-2024-03-14.log status=progress
dd if=/dev/urandom bs=1M count=512 \
  of=/opt/kijanikiosk/shared/logs/payments-2024-03-17.log status=progress
chown kk-logs:kijanikiosk /opt/kijanikiosk/shared/logs/*.log

echo "[fault-1] Log accumulation: $(du -sh /opt/kijanikiosk/shared/logs/ | cut -f1)"

# --- FAULT 2: Port conflict via rogue process ---
echo "[fault-2] Starting a rogue process on port 3001..."
cat > /tmp/rogue-server.js << 'NODEOF'
const http = require('http');
const server = http.createServer((req, res) => {
  res.writeHead(500, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Internal Server Error', service: 'unknown' }));
});
server.listen(3001, '127.0.0.1', () => {
  console.log('Rogue server listening on 127.0.0.1:3001');
});
NODEOF

nohup node /tmp/rogue-server.js >/tmp/rogue-server.log 2>&1 &
echo "[fault-2] Rogue server PID: $!"

# --- FAULT 3: Firewall misconfiguration ---
echo "[fault-3] Adding erroneous deny rule for port 3001..."
ufw deny 3001/tcp comment 'MISCONFIGURED: blocks health checks'
ufw reload
echo "[fault-3] ufw rule injected"

# --- Install required monitoring tools if not present ---
apt-get install -y sysstat htop iotop >/dev/null 2>&1
systemctl enable --now sysstat 2>/dev/null || true

echo ""
echo "[setup complete] Three faults are now active."
echo "Set your 90-minute investigation timer NOW."