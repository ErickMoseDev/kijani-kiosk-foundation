#!/bin/bash
# kijanikiosk-provision.sh — Friday Week 3 Production Foundation
# Idempotent 8-phase provisioning for KijaniKiosk application servers.
# Handles dirty-state VMs: partial installs, stale processes, misconfigured firewall.
# Usage: sudo bash kijanikiosk-provision.sh

set -euo pipefail

readonly NGINX_VERSION="1.24.0-2ubuntu7.6"
readonly NODE_MAJOR_VERSION="20"
readonly APP_GROUP="kijanikiosk"
readonly APP_BASE="/opt/kijanikiosk"
readonly MONITORING_SUBNET="10.0.1.0/24"

log()     { echo "[$(date +%FT%T)] INFO  $*"; }
success() { echo "[$(date +%FT%T)] OK    $*"; }
warn()    { echo "[$(date +%FT%T)] WARN  $*"; }
error()   { echo "[$(date +%FT%T)] ERROR $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] && error "Must run as root or with sudo"
grep -qi ubuntu /etc/os-release || error "Designed for Ubuntu only"

log "Starting KijaniKiosk provisioning (8 phases)..."

# ==========================================================================
# Phase 1: Packages
# ==========================================================================
provision_packages() {
  log "=== Phase 1: Packages ==="

  apt-get update -qq

  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl gnupg acl ufw sysstat

  # NodeSource GPG key
  if [[ ! -f /usr/share/keyrings/nodesource.gpg ]]; then
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |
      gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
    log "NodeSource GPG key added"
  else
    log "Already exists: NodeSource GPG key"
  fi

  # NodeSource repo
  if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR_VERSION}.x nodistro main" \
      >/etc/apt/sources.list.d/nodesource.list
    apt-get update -qq
    log "NodeSource repository added"
  else
    log "Already exists: NodeSource repository"
  fi

  # Check currently installed versions before attempting install
  local current_nginx current_node
  current_nginx=$(dpkg-query -W -f='${Version}' nginx 2>/dev/null || echo "not-installed")
  current_node=$(node --version 2>/dev/null || echo "not-installed")
  log "Current versions — nginx: ${current_nginx}, node: ${current_node}"

  # Unhold before install to allow version correction if needed
  apt-mark unhold nginx nodejs 2>/dev/null || true

  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    "nginx=${NGINX_VERSION}" nodejs

  apt-mark hold nginx nodejs

  log "nginx version: $(nginx -v 2>&1)"
  log "node version:  $(node --version)"
  success "Phase 1 complete — packages provisioned and held"
}

# ==========================================================================
# Phase 2: Service Accounts
# ==========================================================================
provision_users() {
  log "=== Phase 2: Service Accounts ==="

  if ! getent group "${APP_GROUP}" >/dev/null 2>&1; then
    groupadd "${APP_GROUP}"
    log "Created group: ${APP_GROUP}"
  else
    log "Already exists: group ${APP_GROUP}"
  fi

  declare -A svc_accounts=(
    [kk-api]="KijaniKiosk API Service"
    [kk-payments]="KijaniKiosk Payments Service"
    [kk-logs]="KijaniKiosk Logging Service"
  )

  for acct in "${!svc_accounts[@]}"; do
    if ! id "${acct}" >/dev/null 2>&1; then
      useradd --system --no-create-home --home-dir /nonexistent \
        --shell /usr/sbin/nologin --comment "${svc_accounts[$acct]}" "${acct}"
      log "Created: ${acct}"
    else
      log "Already exists: ${acct}"
    fi
    usermod -aG "${APP_GROUP}" "${acct}"
  done

  if id "amina" >/dev/null 2>&1; then
    usermod -aG "${APP_GROUP}" "amina"
    log "Added amina to ${APP_GROUP}"
  else
    log "User amina not found — skipping"
  fi

  success "Phase 2 complete — service accounts provisioned"
}

# ==========================================================================
# Phase 3: Directories, ACLs, and Config Files
# ==========================================================================
provision_dirs() {
  log "=== Phase 3: Directories ==="

  # --- Application directories ---
  mkdir -p "${APP_BASE}/api"
  chown kk-api:kk-api "${APP_BASE}/api"
  chmod 750 "${APP_BASE}/api"
  log "Directory ready: ${APP_BASE}/api (kk-api:kk-api 750)"

  mkdir -p "${APP_BASE}/payments"
  chown kk-payments:kk-payments "${APP_BASE}/payments"
  chmod 750 "${APP_BASE}/payments"
  log "Directory ready: ${APP_BASE}/payments (kk-payments:kk-payments 750)"

  mkdir -p "${APP_BASE}/config"
  chown root:"${APP_GROUP}" "${APP_BASE}/config"
  chmod 750 "${APP_BASE}/config"
  log "Directory ready: ${APP_BASE}/config (root:${APP_GROUP} 750)"

  mkdir -p "${APP_BASE}/shared/logs"
  chown kk-logs:kk-logs "${APP_BASE}/shared/logs"
  chmod 2770 "${APP_BASE}/shared/logs"
  log "Directory ready: ${APP_BASE}/shared/logs (kk-logs:kk-logs 2770)"

  mkdir -p "${APP_BASE}/scripts"
  chown root:root "${APP_BASE}/scripts"
  chmod 750 "${APP_BASE}/scripts"
  log "Directory ready: ${APP_BASE}/scripts (root:root 750)"

  # --- Health check directory (new for Phase 8) ---
  mkdir -p "${APP_BASE}/health"
  chown kk-logs:"${APP_GROUP}" "${APP_BASE}/health"
  chmod 750 "${APP_BASE}/health"
  log "Directory ready: ${APP_BASE}/health (kk-logs:${APP_GROUP} 750)"

  # --- ACLs on shared/logs ---
  setfacl -m u:kk-api:rwx "${APP_BASE}/shared/logs"
  setfacl -m u:kk-payments:rwx "${APP_BASE}/shared/logs"
  setfacl -d -m u:kk-api:rwx "${APP_BASE}/shared/logs"
  setfacl -d -m u:kk-payments:rwx "${APP_BASE}/shared/logs"
  log "ACLs set on ${APP_BASE}/shared/logs (kk-api, kk-payments: rwx + default)"

  # --- Environment files for all three services ---
  # These must exist and be readable by the respective service accounts.
  # Config dir is root:kijanikiosk 750, so group members can read.
  # Individual env files are 640 owned by root:kijanikiosk.

  if [[ ! -f "${APP_BASE}/config/kk-api.env" ]]; then
    cat >"${APP_BASE}/config/kk-api.env" <<'EOF'
NODE_ENV=production
PORT=3000
LOG_DIR=/opt/kijanikiosk/shared/logs
EOF
    log "Created: ${APP_BASE}/config/kk-api.env"
  else
    log "Already exists: ${APP_BASE}/config/kk-api.env"
  fi

  if [[ ! -f "${APP_BASE}/config/kk-payments.env" ]]; then
    cat >"${APP_BASE}/config/kk-payments.env" <<'EOF'
NODE_ENV=production
PORT=3001
LOG_DIR=/opt/kijanikiosk/shared/logs
PAYMENTS_API_KEY=placeholder-rotate-before-production
EOF
    log "Created: ${APP_BASE}/config/kk-payments.env"
  else
    log "Already exists: ${APP_BASE}/config/kk-payments.env"
  fi

  if [[ ! -f "${APP_BASE}/config/kk-logs.env" ]]; then
    cat >"${APP_BASE}/config/kk-logs.env" <<'EOF'
NODE_ENV=production
PORT=3002
LOG_DIR=/opt/kijanikiosk/shared/logs
EOF
    log "Created: ${APP_BASE}/config/kk-logs.env"
  else
    log "Already exists: ${APP_BASE}/config/kk-logs.env"
  fi

  # Enforce ownership/perms on all env files (idempotent)
  chown root:"${APP_GROUP}" "${APP_BASE}/config/"*.env
  chmod 640 "${APP_BASE}/config/"*.env
  log "Env files permissions set: root:${APP_GROUP} 640"

  success "Phase 3 complete — directories, ACLs, and config files provisioned"
}

# ==========================================================================
# Phase 4: systemd Units (all three services, hardened)
# ==========================================================================
provision_services() {
  log "=== Phase 4: systemd Units ==="

  # --- Kill any rogue process on service ports (dirty-VM cleanup) ---
  for port in 3000 3001 3002; do
    local rogue_pid
    rogue_pid=$(ss -tlnp | grep ":${port}" | grep -oP 'pid=\K[0-9]+' || true)
    if [[ -n "${rogue_pid}" ]]; then
      warn "Dirty state: rogue process PID ${rogue_pid} on port ${port} — killing"
      kill -15 "${rogue_pid}" 2>/dev/null || true
      sleep 2
      kill -9 "${rogue_pid}" 2>/dev/null || true
      log "Rogue process on port ${port} terminated"
    fi
  done

  # --- Clean up stale rogue artifacts from /tmp ---
  rm -f /tmp/rogue-server.js /tmp/rogue-server.log 2>/dev/null || true

  # --- Reset any failed systemd states from previous runs ---
  for svc in kk-api kk-payments kk-logs; do
    systemctl reset-failed "${svc}.service" 2>/dev/null || true
  done

  # =========================================
  # kk-api.service — target: < 3.5 security score
  # =========================================
  cat >/etc/systemd/system/kk-api.service <<'UNIT'
[Unit]
Description=KijaniKiosk API Service
Documentation=https://github.com/kijanikiosk/api
After=network.target
Wants=network.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=kk-api
Group=kk-api
WorkingDirectory=/opt/kijanikiosk/api
EnvironmentFile=/opt/kijanikiosk/config/kk-api.env
ExecStart=/usr/bin/node /opt/kijanikiosk/api/server.js
Restart=on-failure
RestartSec=5

# --- Security hardening (target: < 3.5) ---
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
MemoryDenyWriteExecute=true
RemoveIPC=true
CapabilityBoundingSet=
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources

# Filesystem access
ReadWritePaths=/opt/kijanikiosk/shared/logs
ReadOnlyPaths=/opt/kijanikiosk/config

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-api

[Install]
WantedBy=multi-user.target
UNIT
  log "Unit file written: kk-api.service"

  # =========================================
  # kk-payments.service — target: < 2.5 security score
  # Handles financial data. Most restrictive.
  # =========================================
  cat >/etc/systemd/system/kk-payments.service <<'UNIT'
[Unit]
Description=KijaniKiosk Payments Service
Documentation=https://github.com/kijanikiosk/payments
After=network.target kk-api.service
Wants=network.target kk-api.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=kk-payments
Group=kk-payments
WorkingDirectory=/opt/kijanikiosk/payments
EnvironmentFile=/opt/kijanikiosk/config/kk-payments.env
ExecStart=/usr/bin/node /opt/kijanikiosk/payments/server.js
Restart=on-failure
RestartSec=5

# --- Security hardening (target: < 2.5) ---
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
PrivateUsers=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
ProtectProc=invisible
ProcSubset=pid
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
LockPersonality=true
MemoryDenyWriteExecute=true
RemoveIPC=true
CapabilityBoundingSet=
AmbientCapabilities=
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources @mount @clock @debug @obsolete @raw-io @reboot @swap @cpu-emulation @module
UMask=0077
IPAddressAllow=localhost
IPAddressDeny=any

# Filesystem access
ReadWritePaths=/opt/kijanikiosk/shared/logs
ReadOnlyPaths=/opt/kijanikiosk/config
InaccessiblePaths=/opt/kijanikiosk/api
TemporaryFileSystem=/var:ro

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-payments

[Install]
WantedBy=multi-user.target
UNIT
  log "Unit file written: kk-payments.service"

  # =========================================
  # kk-logs.service — target: < 3.5 security score
  # Log aggregation service.
  # =========================================
  cat >/etc/systemd/system/kk-logs.service <<'UNIT'
[Unit]
Description=KijaniKiosk Logging Service
Documentation=https://github.com/kijanikiosk/logs
After=network.target
Wants=network.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=kk-logs
Group=kk-logs
WorkingDirectory=/opt/kijanikiosk/shared/logs
EnvironmentFile=/opt/kijanikiosk/config/kk-logs.env
ExecStart=/usr/bin/node /opt/kijanikiosk/shared/logs/aggregator.js
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5

# --- Security hardening (target: < 3.5) ---
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
MemoryDenyWriteExecute=true
RemoveIPC=true
CapabilityBoundingSet=
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources

# Filesystem access — kk-logs needs write access to the log directory
ReadWritePaths=/opt/kijanikiosk/shared/logs
ReadOnlyPaths=/opt/kijanikiosk/config

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-logs

[Install]
WantedBy=multi-user.target
UNIT
  log "Unit file written: kk-logs.service"

  # Reload systemd and enable all three services
  systemctl daemon-reload
  log "systemd daemon reloaded"

  for svc in kk-api kk-payments kk-logs; do
    systemctl enable "${svc}.service"
    log "${svc}.service enabled (not started — no app code deployed)"
  done

  success "Phase 4 complete — three systemd units provisioned"
}

# ==========================================================================
# Phase 5: Firewall (intent-based, with comments)
# ==========================================================================
provision_firewall() {
  log "=== Phase 5: Firewall ==="

  # Reset to clean baseline — removes ALL previous rules including dirty-state deny rules
  ufw --force reset
  log "Firewall reset to baseline"

  ufw default deny incoming
  ufw default allow outgoing

  # Rule order matters: allow rules must come before deny rules for the same port.
  # ufw evaluates rules in numbered order; first match wins.

  # 1. SSH — must be first to prevent lockout
  ufw allow in 22/tcp comment 'Allow SSH remote administration'
  log "Allowed: 22/tcp (SSH)"

  # 2. HTTP — public web traffic via nginx reverse proxy
  ufw allow in 80/tcp comment 'Allow HTTP via nginx reverse proxy'
  log "Allowed: 80/tcp (HTTP)"

  # 3. Health check from monitoring subnet on kk-payments port
  ufw allow from "${MONITORING_SUBNET}" to any port 3001 proto tcp \
    comment 'Allow kk-payments health check from monitoring subnet'
  log "Allowed: 3001/tcp from ${MONITORING_SUBNET} (health check)"

  # 4. Allow loopback on 3001 for nginx proxying
  ufw allow in on lo to any port 3001 proto tcp \
    comment 'Allow loopback for nginx to kk-payments proxy'
  log "Allowed: 3001/tcp on loopback (nginx proxy)"

  # 5. Deny 3001 from all other external sources (must come after allow rules)
  ufw deny in 3001/tcp comment 'Deny kk-payments from external — internal only'
  log "Denied: 3001/tcp from external"

  ufw --force enable
  log "Firewall enabled"

  ufw status verbose | while IFS= read -r line; do log "  $line"; done

  success "Phase 5 complete — firewall configured with comments"
}

# ==========================================================================
# Phase 6: Dirty-State Cleanup
# ==========================================================================
provision_cleanup() {
  log "=== Phase 6: Dirty-State Cleanup ==="

  # --- Remove oversized fake binary logs from Thursday incident ---
  local cleaned=0
  for f in "${APP_BASE}/shared/logs/"*.log; do
    [[ ! -f "$f" ]] && continue
    local fsize
    fsize=$(stat -c%s "$f" 2>/dev/null || echo 0)
    # Files > 100MB are likely fake binary data from incident injection
    if (( fsize > 104857600 )); then
      local ftype
      ftype=$(file -b "$f" | head -1)
      if [[ "$ftype" == "data" ]]; then
        warn "Dirty state: removing oversized fake log ($(( fsize / 1048576 ))MB): $f"
        rm -f "$f"
        ((cleaned++))
      fi
    fi
  done
  [[ $cleaned -gt 0 ]] && log "Removed ${cleaned} oversized fake log file(s)" \
                        || log "No oversized fake logs found"

  # --- Stop apache2 if it holds port 80 (nginx should own it) ---
  if systemctl is-active apache2 >/dev/null 2>&1; then
    warn "Dirty state: apache2 is running — stopping to free port 80 for nginx"
    systemctl stop apache2
    systemctl disable apache2
    log "apache2 stopped and disabled"
  else
    log "apache2 not running — no conflict"
  fi

  # --- Ensure nginx can start on port 80 ---
  if ! systemctl is-active nginx >/dev/null 2>&1; then
    systemctl reset-failed nginx 2>/dev/null || true
    systemctl start nginx 2>/dev/null && log "nginx started on port 80" \
      || warn "nginx failed to start (may need config fix)"
  else
    log "nginx already running"
  fi

  success "Phase 6 complete — dirty-state cleanup"
}

# ==========================================================================
# Phase 7: Journal Persistence and Log Rotation
# ==========================================================================
provision_journal_and_logrotate() {
  log "=== Phase 7: Journal Persistence and Log Rotation ==="

  # --- Persistent journal storage capped at 500MB ---
  mkdir -p /var/log/journal
  systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null || true

  # Write journald config
  mkdir -p /etc/systemd/journald.conf.d
  cat >/etc/systemd/journald.conf.d/kijanikiosk.conf <<'JCONF'
[Journal]
Storage=persistent
SystemMaxUse=500M
SystemKeepFree=1G
SystemMaxFileSize=50M
MaxRetentionSec=30day
JCONF
  log "Journal persistence configured: /var/log/journal (max 500MB)"

  systemctl restart systemd-journald
  log "systemd-journald restarted with persistent storage"

  # --- Logrotate config for all three services ---
  # su directive required because shared/logs is SGID 2770 (group-writable)
  # create 0660 kk-logs kijanikiosk: sets base perms; directory default ACLs
  # propagate kk-api:rwx and kk-payments:rwx to new files automatically.
  # postrotate uses kill -HUP because kk-logs defines ExecReload=/bin/kill -HUP.
  # For kk-api and kk-payments (no ExecReload), SIGHUP to the main PID triggers
  # Node.js default behavior (ignored or handled by app). This is safe because
  # these services write to journal, not directly to the rotated files.
  cat >/etc/logrotate.d/kijanikiosk <<'LOGROTATE'
/opt/kijanikiosk/shared/logs/*.log {
    su kk-logs kijanikiosk
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0660 kk-logs kijanikiosk
    sharedscripts
    postrotate
        # kk-logs supports reload via ExecReload; others use journal output
        /bin/systemctl reload kk-logs.service 2>/dev/null || true
    endscript
}
LOGROTATE
  log "Logrotate config written: /etc/logrotate.d/kijanikiosk"
  log "  Rotation: daily | Retention: 14 days | Compression: enabled"

  # Validate logrotate config
  if logrotate --debug /etc/logrotate.d/kijanikiosk >/dev/null 2>&1; then
    success "Logrotate config validated (debug dry-run passed)"
  else
    warn "Logrotate debug had warnings — check /etc/logrotate.d/kijanikiosk"
  fi

  # Verify journal persistence
  if [[ -d /var/log/journal ]]; then
    success "Phase 7 complete — journal persistent, logrotate configured"
  else
    error "Journal persistence directory /var/log/journal not created"
  fi
}

# ==========================================================================
# Phase 8: Monitoring Health Checks
# ==========================================================================
provision_health_checks() {
  log "=== Phase 8: Monitoring Health Checks ==="

  # Check each service port
  local api_status payments_status logs_status
  api_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3000" 2>/dev/null && echo '"ok"' || echo '"down"')
  payments_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3001" 2>/dev/null && echo '"ok"' || echo '"down"')
  logs_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3002" 2>/dev/null && echo '"ok"' || echo '"down"')

  log "Health check results — kk-api: ${api_status}, kk-payments: ${payments_status}, kk-logs: ${logs_status}"

  # Write structured JSON
  mkdir -p "${APP_BASE}/health"
  printf '{"timestamp":"%s","kk-api":%s,"kk-payments":%s,"kk-logs":%s}\n' \
    "$(date -Is)" "$api_status" "$payments_status" "$logs_status" \
    > "${APP_BASE}/health/last-provision.json"

  chown kk-logs:"${APP_GROUP}" "${APP_BASE}/health/last-provision.json"
  chmod 640 "${APP_BASE}/health/last-provision.json"

  log "Health check JSON: ${APP_BASE}/health/last-provision.json"
  cat "${APP_BASE}/health/last-provision.json"

  success "Phase 8 complete — health check written"
}

# ==========================================================================
# Final Verification (covers all 8 phases)
# ==========================================================================
verify_state() {
  log "=== Final Verification ==="
  local failed=0

  # --- Phase 1: Packages ---
  local held
  held=$(apt-mark showhold)
  for pkg in nginx nodejs; do
    if echo "${held}" | grep -q "^${pkg}$"; then
      success "PASS: Package held: ${pkg} ($(dpkg-query -W -f='${Version}' "${pkg}"))"
    else
      log "FAIL: Package not held: ${pkg}"
      ((failed++))
    fi
  done

  # --- Phase 2: Service accounts ---
  for acct in kk-api kk-payments kk-logs; do
    if id "${acct}" >/dev/null 2>&1; then
      success "PASS: Account exists: ${acct}"
    else
      log "FAIL: Account missing: ${acct}"
      ((failed++))
    fi
  done

  # --- Phase 3: Directories ---
  for dir in api payments config shared/logs scripts health; do
    if [[ -d "${APP_BASE}/${dir}" ]]; then
      success "PASS: Directory exists: ${APP_BASE}/${dir}"
    else
      log "FAIL: Directory missing: ${APP_BASE}/${dir}"
      ((failed++))
    fi
  done

  # --- Phase 3: Environment files readable by service accounts ---
  for pair in "kk-api:kk-api.env" "kk-payments:kk-payments.env" "kk-logs:kk-logs.env"; do
    local user="${pair%%:*}"
    local envfile="${pair##*:}"
    if sudo -u "${user}" cat "${APP_BASE}/config/${envfile}" >/dev/null 2>&1; then
      success "PASS: ${envfile} readable by ${user}"
    else
      log "FAIL: ${envfile} NOT readable by ${user}"
      ((failed++))
    fi
  done

  # --- Phase 3: SUID scan ---
  local suid_files
  suid_files=$(find "${APP_BASE}" -perm /4000 2>/dev/null || true)
  if [[ -z "${suid_files}" ]]; then
    success "PASS: No SUID binaries under ${APP_BASE}"
  else
    log "FAIL: SUID binaries found: ${suid_files}"
    ((failed++))
  fi

  # --- Phase 4: systemd units enabled ---
  for svc in kk-api kk-payments kk-logs; do
    if systemctl is-enabled "${svc}.service" >/dev/null 2>&1; then
      success "PASS: ${svc}.service is enabled"
    else
      log "FAIL: ${svc}.service is not enabled"
      ((failed++))
    fi
  done

  # --- Phase 5: Firewall rules (programmatic per-rule check) ---
  local fw_status
  fw_status=$(ufw status)

  if echo "$fw_status" | grep -q "22/tcp.*ALLOW"; then
    success "PASS: Firewall — SSH (22/tcp) allowed"
  else
    log "FAIL: Firewall — SSH rule missing"
    ((failed++))
  fi

  if echo "$fw_status" | grep -q "80/tcp.*ALLOW"; then
    success "PASS: Firewall — HTTP (80/tcp) allowed"
  else
    log "FAIL: Firewall — HTTP rule missing"
    ((failed++))
  fi

  if echo "$fw_status" | grep -q "3001.*ALLOW.*${MONITORING_SUBNET}"; then
    success "PASS: Firewall — 3001/tcp allowed from ${MONITORING_SUBNET}"
  else
    log "FAIL: Firewall — 3001 monitoring subnet rule missing"
    ((failed++))
  fi

  if echo "$fw_status" | grep -q "3001.*DENY"; then
    success "PASS: Firewall — 3001/tcp external deny present"
  else
    log "FAIL: Firewall — 3001 deny rule missing"
    ((failed++))
  fi

  # Check that all rules have comments
  local uncommented
  uncommented=$(ufw status | grep -E "^[0-9]|ALLOW|DENY" | grep -v "#" | grep -cv "^Status\|^$\|^To\|^--\|^Default\|^New\|^Logging" || true)
  if [[ "$uncommented" -eq 0 ]]; then
    success "PASS: Firewall — all rules have comments"
  else
    warn "WARN: ${uncommented} firewall rule(s) may lack comments"
  fi

  # --- Phase 7: Journal + logrotate ---
  if [[ -d /var/log/journal ]]; then
    success "PASS: Journal persistence directory exists"
  else
    log "FAIL: /var/log/journal missing"
    ((failed++))
  fi

  if [[ -f /etc/logrotate.d/kijanikiosk ]]; then
    success "PASS: Logrotate config exists"
  else
    log "FAIL: Logrotate config missing"
    ((failed++))
  fi

  if logrotate --debug /etc/logrotate.d/kijanikiosk >/dev/null 2>&1; then
    success "PASS: Logrotate config validates (debug)"
  else
    log "FAIL: Logrotate config validation failed"
    ((failed++))
  fi

  # --- Phase 8: Health check JSON ---
  if [[ -f "${APP_BASE}/health/last-provision.json" ]]; then
    success "PASS: Health check JSON exists"
    # Verify readability by kijanikiosk group
    if sudo -u kk-logs cat "${APP_BASE}/health/last-provision.json" >/dev/null 2>&1; then
      success "PASS: Health check JSON readable by kk-logs"
    else
      log "FAIL: Health check JSON not readable by kk-logs"
      ((failed++))
    fi
  else
    log "FAIL: Health check JSON missing"
    ((failed++))
  fi

  # --- Access model integration: logrotate creates files kk-api can write ---
  # Force rotation and test
  logrotate --force /etc/logrotate.d/kijanikiosk 2>/dev/null || true
  if sudo -u kk-api touch "${APP_BASE}/shared/logs/test-write.tmp" 2>/dev/null; then
    success "PASS: kk-api can write to shared/logs after logrotate"
    rm -f "${APP_BASE}/shared/logs/test-write.tmp"
  else
    log "FAIL: kk-api cannot write to shared/logs after logrotate"
    ((failed++))
  fi

  # --- Final verdict ---
  echo ""
  if [[ ${failed} -eq 0 ]]; then
    success "ALL VERIFICATION CHECKS PASSED"
  else
    log "FAIL: ${failed} verification check(s) failed — review output above"
    exit 1
  fi
}

# ==========================================================================
# Main
# ==========================================================================
main() {
  provision_packages
  provision_users
  provision_dirs
  provision_services
  provision_firewall
  provision_cleanup
  provision_journal_and_logrotate
  provision_health_checks
  verify_state
  success "Provisioning complete. Server is in known state."
}

main "$@"
