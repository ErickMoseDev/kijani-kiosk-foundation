#!/usr/bin/env bash
# scripts/switch-env.sh
# Switches the nginx active environment between blue and green.
# Performs a pre-flight check, atomic switch, and post-switch validation.
#
# Usage: sudo bash switch-env.sh <blue|green>
# Exit codes:
#   0 - Switch successful and confirmed
#   1 - Invalid argument or pre-condition failure (no switch attempted)
#   2 - nginx validation or reload failed (no switch completed)
#   3 - Post-switch health check failed (switch completed but not verified)

set -euo pipefail

TARGET_ENV="${1:?Usage: switch-env.sh <blue|green>}"
ACTIVE_ENV_CONF="/etc/nginx/kijanikiosk-active-env.conf"
ACTIVE_ENV_STATE="/opt/kijanikiosk/.active-env"
NGINX_CONF_DIR="/etc/nginx"
BLUE_PORT=4000
GREEN_PORT=3000

LOCK_FILE="/tmp/kijanikiosk-switch.lock"
exec 9>"${LOCK_FILE}"
flock -n 9 || { log "ERROR" "Switch already in progress — exiting"; exit 2; }

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
log_fail() { echo "[$(date -u +%H:%M:%S)] [FAIL] $*" >&2; }

# Validate argument
case "${TARGET_ENV}" in
  blue|green) ;;
  *) log_fail "TARGET_ENV must be 'blue' or 'green', got '${TARGET_ENV}'"; exit 1 ;;
esac

# Determine current state
CURRENT_ENV="unknown"
if [ -f "${ACTIVE_ENV_STATE}" ]; then
  CURRENT_ENV=$(cat "${ACTIVE_ENV_STATE}")
fi

log "Current environment: ${CURRENT_ENV}"
log "Target environment:  ${TARGET_ENV}"

# Idempotency: already on the target environment
if [ "${CURRENT_ENV}" = "${TARGET_ENV}" ]; then
  log "Already on ${TARGET_ENV}. No switch needed."
  exit 0
fi

# Step 1: Verify the target environment is healthy before switching to it
TARGET_PORT="${BLUE_PORT}"
[ "${TARGET_ENV}" = "green" ] && TARGET_PORT="${GREEN_PORT}"

log "Step 1: Verifying ${TARGET_ENV} is healthy on port ${TARGET_PORT}..."
TARGET_HEALTH_RESPONSE=$(curl -sf --max-time 5 "http://127.0.0.1:${TARGET_PORT}/health" 2>/dev/null) || {
  log_fail "Pre-switch health check FAILED: ${TARGET_ENV} (port ${TARGET_PORT}) is not responding"
  log_fail "Refusing to switch. Run the deployment script first."
  exit 1
}
# Capture a version fingerprint from the direct response to confirm routing in Step 5
TARGET_VERSION=$(echo "${TARGET_HEALTH_RESPONSE}" | grep -oE '"version":"[^"]+"' | head -1)
log "Pre-switch health check passed: ${TARGET_ENV} is healthy${TARGET_VERSION:+ (${TARGET_VERSION})}"

# Step 2: Write the new active-env configuration
log "Step 2: Writing new nginx active-env configuration..."
cat > "${ACTIVE_ENV_CONF}.new" << EOF
location / {
    proxy_pass         http://kk-api-${TARGET_ENV};
    proxy_http_version 1.1;
    proxy_set_header   Host \$host;
    proxy_cache_bypass \$http_upgrade;
}
location /health {
    proxy_pass http://kk-api-${TARGET_ENV};
}
EOF

# Step 3: Validate the full nginx configuration with the new include file
log "Step 3: Validating nginx configuration..."
# Temporarily replace the active-env file to validate
cp "${ACTIVE_ENV_CONF}" "${ACTIVE_ENV_CONF}.bak"
mv "${ACTIVE_ENV_CONF}.new" "${ACTIVE_ENV_CONF}"

if ! nginx -t 2>&1; then
  log_fail "nginx configuration validation FAILED"
  # Restore the backup (no switch has occurred)
  mv "${ACTIVE_ENV_CONF}.bak" "${ACTIVE_ENV_CONF}"
  exit 2
fi

# TODO: write previous environment state file here (see Page 4)
echo "${CURRENT_ENV}" > /opt/kijanikiosk/.previous-env

# Step 4: Reload nginx (the actual switch)
log "Step 4: Reloading nginx..."
if ! nginx -s reload; then
  log_fail "nginx reload FAILED"
  mv "${ACTIVE_ENV_CONF}.bak" "${ACTIVE_ENV_CONF}"
  nginx -s reload  # Try to restore old config
  exit 2
fi

# Record the new active environment state
echo "${TARGET_ENV}" > "${ACTIVE_ENV_STATE}"
rm -f "${ACTIVE_ENV_CONF}.bak"
log "nginx reloaded. Traffic now routing to ${TARGET_ENV}."

# Step 5: Post-switch health check through the proxy
log "Step 5: Confirming switch via proxy health check..."
sleep 2  # Brief wait for reload to propagate
retries=0
while [ ${retries} -lt 5 ]; do
  response=$(curl -sf --max-time 5 "http://127.0.0.1:80/health" 2>/dev/null) && {
    # If we captured a version fingerprint in Step 1, match it through the proxy.
    # Fallback: any 200 response through the proxy confirms routing is live.
    if [ -n "${TARGET_VERSION}" ]; then
      if echo "${response}" | grep -q "${TARGET_VERSION}"; then
        log "Post-switch confirmation passed: proxy is routing to ${TARGET_ENV} (${TARGET_VERSION})"
        log "=== Switch to ${TARGET_ENV} complete ==="
        exit 0
      fi
      log "Proxy responded but version not yet matching ${TARGET_VERSION}: ${response}"
    else
      log "Post-switch confirmation passed: proxy is live for ${TARGET_ENV}"
      log "=== Switch to ${TARGET_ENV} complete ==="
      exit 0
    fi
  }
  sleep 2
  retries=$((retries + 1))
done

log_fail "Post-switch health check FAILED: proxy did not confirm ${TARGET_ENV} within 12 seconds"
log_fail "nginx was reloaded but the switch may not have taken effect. Check nginx status."
exit 3