#!/bin/bash
# kijanikiosk-provision.sh
# Idempotent provisioning for KijaniKiosk application servers.
# Usage: sudo bash kijanikiosk-provision.sh

set -euo pipefail
# -e   exit on any command failure
# -u   unset variables are errors (catches typos like $NIGNX_VERSION)
# -o pipefail   failures inside pipes are visible (not just the last command)

readonly NGINX_VERSION="1.24.0-2ubuntu7.6"
readonly NODE_MAJOR_VERSION="20"
readonly APP_GROUP="kijanikiosk"
readonly APP_BASE="/opt/kijanikiosk"

log() { echo "[$(date +%FT%T)] INFO  $*"; }
success() { echo "[$(date +%FT%T)] OK    $*"; }
error() {
  echo "[$(date +%FT%T)] ERROR $*" >&2
  exit 1
}

[[ $EUID -ne 0 ]] && error "Must run as root or with sudo"
grep -qi ubuntu /etc/os-release || error "Designed for Ubuntu only"

log "Starting KijaniKiosk provisioning..."

# Phase function stubs - you will implement these in the lab
provision_packages() {
  log "=== Phase 1: Packages ==="

  # Refresh package index quietly
  apt-get update -qq

  # Base dependencies (idempotent: already-installed packages are skipped)
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl gnupg acl ufw

  # NodeSource GPG key + repo (signed-by pattern)
  if [[ ! -f /usr/share/keyrings/nodesource.gpg ]]; then
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |
      gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
    log "NodeSource GPG key added"
  else
    log "NodeSource GPG key already present"
  fi

  if [[ ! -f /etc/apt/sources.list.d/nodesource.list ]]; then
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR_VERSION}.x nodistro main" \
      >/etc/apt/sources.list.d/nodesource.list
    apt-get update -qq
    log "NodeSource repository added"
  else
    log "NodeSource repository already present"
  fi

  # Install nginx at pinned version and nodejs (idempotent: apt skips if already at target version)
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    "nginx=${NGINX_VERSION}" nodejs

  # Hold both packages to prevent unplanned upgrades
  apt-mark hold nginx nodejs

  # Confirm installed versions
  log "nginx version: $(nginx -v 2>&1)"
  log "node version:  $(node --version)"
  success "Phase 1 complete — packages provisioned and held"
}

provision_users() {
  log "=== Phase 2: Service Accounts ==="

  # Create application group if it does not exist
  if ! getent group "${APP_GROUP}" >/dev/null 2>&1; then
    groupadd "${APP_GROUP}"
    log "Created group: ${APP_GROUP}"
  else
    log "Already exists group: ${APP_GROUP}"
  fi

  # Service accounts: name -> GECOS description
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

    # Add to application group (usermod -aG is idempotent — no error if already a member)
    usermod -aG "${APP_GROUP}" "${acct}"
  done

  # Add amina to the group if she exists (do not fail if she does not)
  if id "amina" >/dev/null 2>&1; then
    usermod -aG "${APP_GROUP}" "amina"
    log "Added amina to ${APP_GROUP}"
  else
    log "User amina not found — skipping"
  fi

  success "Phase 2 complete — service accounts provisioned"
}
provision_dirs() {
  log "=== Phase 3: Directories ==="

  # --- /opt/kijanikiosk/api/ — owned by kk-api, isolated at 750 ---
  mkdir -p "${APP_BASE}/api"
  chown kk-api:kk-api "${APP_BASE}/api"
  chmod 750 "${APP_BASE}/api"
  log "Directory ready: ${APP_BASE}/api (kk-api:kk-api 750)"

  # --- /opt/kijanikiosk/payments/ — owned by kk-payments, PCI-siloed at 750 ---
  mkdir -p "${APP_BASE}/payments"
  chown kk-payments:kk-payments "${APP_BASE}/payments"
  chmod 750 "${APP_BASE}/payments"
  log "Directory ready: ${APP_BASE}/payments (kk-payments:kk-payments 750)"

  # --- /opt/kijanikiosk/config/ — root-owned, group-readable by kijanikiosk at 750 ---
  mkdir -p "${APP_BASE}/config"
  chown root:"${APP_GROUP}" "${APP_BASE}/config"
  chmod 750 "${APP_BASE}/config"
  log "Directory ready: ${APP_BASE}/config (root:${APP_GROUP} 750)"

  # --- /opt/kijanikiosk/shared/logs/ — SGID 2770, owned by kk-logs ---
  mkdir -p "${APP_BASE}/shared/logs"
  chown kk-logs:kk-logs "${APP_BASE}/shared/logs"
  chmod 2770 "${APP_BASE}/shared/logs"
  log "Directory ready: ${APP_BASE}/shared/logs (kk-logs:kk-logs 2770)"

  # --- /opt/kijanikiosk/scripts/ — root-owned deployment directory ---
  mkdir -p "${APP_BASE}/scripts"
  chown root:root "${APP_BASE}/scripts"
  chmod 750 "${APP_BASE}/scripts"
  log "Directory ready: ${APP_BASE}/scripts (root:root 750)"

  # --- ACLs on shared/logs: let kk-api and kk-payments write logs ---
  # Access ACLs (apply to existing entries in the directory itself)
  setfacl -m u:kk-api:rwx "${APP_BASE}/shared/logs"
  setfacl -m u:kk-payments:rwx "${APP_BASE}/shared/logs"
  # Default ACLs (new files/dirs created inside inherit these permissions)
  setfacl -d -m u:kk-api:rwx "${APP_BASE}/shared/logs"
  setfacl -d -m u:kk-payments:rwx "${APP_BASE}/shared/logs"
  log "ACLs set on ${APP_BASE}/shared/logs (kk-api, kk-payments: rwx + default)"

  success "Phase 3 complete — directory tree provisioned"
}
provision_services() {
  log "=== Phase 4: systemd Units ==="

  # Write the kk-api unit file using a quoted heredoc to prevent variable expansion
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

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadOnlyPaths=/opt/kijanikiosk/config

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-api

[Install]
WantedBy=multi-user.target
UNIT

  log "Unit file written: /etc/systemd/system/kk-api.service"

  # Reload systemd to pick up the new/updated unit file
  systemctl daemon-reload
  log "systemd daemon reloaded"

  # Enable the service (idempotent: no error if already enabled)
  # Do NOT start — application code may not be deployed yet
  systemctl enable kk-api.service
  log "kk-api.service enabled (not started)"

  success "Phase 4 complete — systemd units provisioned"
}

provision_firewall() {
  log "=== Phase 5: Firewall ==="

  # Reset ufw to a clean state (--force prevents interactive prompt)
  # Idempotent: safe whether ufw was previously configured or never touched
  ufw --force reset

  # Default policies: deny all inbound, allow all outbound
  ufw default deny incoming
  ufw default allow outgoing

  # CRITICAL: Allow SSH *before* enabling the firewall.
  # Running 'ufw enable' without an SSH rule on a remote server immediately
  # drops your session. There is no recovery without physical/console access.
  ufw allow 22/tcp
  log "Allowed SSH (22/tcp) — safe to enable firewall"

  ufw allow 80/tcp
  log "Allowed HTTP (80/tcp)"

  # Enable ufw non-interactively (--force suppresses the y/n confirmation)
  # Idempotent: if already active, it stays active without error
  ufw --force enable
  log "ufw enabled"

  # Verify the resulting ruleset
  log "Firewall rules:"
  ufw status verbose | while IFS= read -r line; do log "  $line"; done

  success "Phase 5 complete — firewall configured"
}
verify_state() {
  log "=== Phase 6: Verification ==="
  local failed=0

  # --- Service accounts ---
  for acct in kk-api kk-payments kk-logs; do
    if id "${acct}" >/dev/null 2>&1; then
      success "Account exists: ${acct}"
    else
      log "FAIL: Account missing: ${acct}"
      ((failed++))
    fi
  done

  # --- Required directories ---
  for dir in api payments config shared/logs scripts; do
    if [[ -d "${APP_BASE}/${dir}" ]]; then
      success "Directory exists: ${APP_BASE}/${dir}"
    else
      log "FAIL: Directory missing: ${APP_BASE}/${dir}"
      ((failed++))
    fi
  done

  # --- SUID scan on the application tree (none should exist) ---
  local suid_files
  suid_files=$(find "${APP_BASE}" -perm /4000 2>/dev/null || true)
  if [[ -z "${suid_files}" ]]; then
    success "No SUID binaries found under ${APP_BASE}"
  else
    log "FAIL: SUID binaries found under ${APP_BASE}:"
    echo "${suid_files}" | while IFS= read -r f; do log "  ${f}"; done
    ((failed++))
  fi

  # --- Package holds ---
  local held
  held=$(apt-mark showhold)
  for pkg in nginx nodejs; do
    if echo "${held}" | grep -q "^${pkg}$"; then
      success "Package held: ${pkg} ($(dpkg-query -W -f='${Version}' "${pkg}"))"
    else
      log "FAIL: Package not held: ${pkg}"
      ((failed++))
    fi
  done

  # --- systemd unit ---
  if systemctl is-enabled kk-api.service >/dev/null 2>&1; then
    success "kk-api.service is enabled"
  else
    log "FAIL: kk-api.service is not enabled"
    ((failed++))
  fi

  # --- Final verdict ---
  [[ ${failed} -eq 0 ]] &&
    success "All verification checks passed" ||
    error "${failed} verification check(s) failed — review output above"
}

main() {
  provision_packages
  provision_users
  provision_dirs
  provision_services
  provision_firewall
  verify_state
  success "Provisioning complete. Server is in known state."
}

main "$@"
