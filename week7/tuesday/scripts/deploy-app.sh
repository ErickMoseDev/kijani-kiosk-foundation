#!/usr/bin/env bash
# scripts/deploy-app.sh
# Deploys a versioned kk-api artifact to the blue or green environment.
# 
# Required environment variables:
#   APP_VERSION      - The version to deploy, e.g. "v1.4.0"
#   DEPLOY_ENV       - Target environment: "blue" or "green"
#   ARTIFACT_BASE_URL - Base URL for artifact downloads
#
# Optional:
#   BLUE_PORT        - Port for the blue service (default: 4000)
#   GREEN_PORT       - Port for the green service (default: 3000)

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
APP_VERSION="${APP_VERSION:?APP_VERSION environment variable is required}"
DEPLOY_ENV="${DEPLOY_ENV:?DEPLOY_ENV must be 'blue' or 'green'}"
ARTIFACT_BASE_URL="${ARTIFACT_BASE_URL:?ARTIFACT_BASE_URL is required}"
BLUE_PORT="${BLUE_PORT:-4000}"
GREEN_PORT="${GREEN_PORT:-3000}"

# Validate DEPLOY_ENV is a known value
case "${DEPLOY_ENV}" in
  blue|green) ;;
  *) echo "ERROR: DEPLOY_ENV must be 'blue' or 'green', got '${DEPLOY_ENV}'"; exit 1 ;;
esac




# ── Logging ──────────────────────────────────────────────────────────────────
SCRIPT_START=$(date +%s)

log() {
  local elapsed=$(( $(date +%s) - SCRIPT_START ))
  echo "[$(date -u +%H:%M:%S)] [+${elapsed}s] $*"
}

log_fail() {
  echo "[$(date -u +%H:%M:%S)] [FAIL] $*" >&2
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  log "=== kk-api Deployment Script ==="
  log "Version: ${APP_VERSION}"
  log "Target:  ${DEPLOY_ENV} (port: $([ "${DEPLOY_ENV}" = "blue" ] && echo "${BLUE_PORT}" || echo "${GREEN_PORT}"))"
  log "Artifact: ${ARTIFACT_BASE_URL}/kk-api-${APP_VERSION}.tar.gz"
  echo ""

  fetch_artifact
  validate_artifact
  deploy_artifact
  restart_service
  verify_service

  echo ""
  log "=== Deployment complete: kk-api ${APP_VERSION} on ${DEPLOY_ENV} ==="
  exit 0
}


# Phase 1
fetch_artifact() {
  log "=== Phase 1: Fetch artifact ==="
  local artifact_url="${ARTIFACT_BASE_URL}/kk-api-${APP_VERSION}.tar.gz"
  local dest="/opt/kijanikiosk/releases/kk-api-${APP_VERSION}.tar.gz"

  if [ -f "${dest}" ]; then
    log "Artifact already downloaded: ${dest}"
    return 0
  fi

  mkdir -p /opt/kijanikiosk/releases
  curl -fsSL --max-time 60 "${artifact_url}" -o "${dest}" || {
    log_fail "Phase 1 FAILED: Could not fetch ${artifact_url}"
    exit 1
  }
  log "Fetched: ${dest}"
}

# Phase 2

validate_artifact() {
  log "=== Phase 2: Validate artifact ==="
  local dest="/opt/kijanikiosk/releases/kk-api-${APP_VERSION}.tar.gz"

  # Check the file exists and is non-empty
  [ -s "${dest}" ] || { log_fail "Phase 2 FAILED: Artifact file is missing or empty"; exit 1; }

  # Verify checksum if a checksum file is available
  if [ -f "${dest}.sha256" ]; then
    ( cd "$(dirname "${dest}")" && sha256sum -c "${dest}.sha256" ) || {
      log_fail "Phase 2 FAILED: Checksum mismatch on ${dest}"
      exit 1
    }
  fi

  # Extract to a staging area and check for the expected entry point
  local staging="/opt/kijanikiosk/releases/staging-${APP_VERSION}"
  rm -rf "${staging}"
  mkdir -p "${staging}"
  tar xzf "${dest}" -C "${staging}" || {
    log_fail "Phase 2 FAILED: Could not extract artifact"
    exit 1
  }

  find "${staging}" -name "server.js" -type f | grep -q . || {
    log_fail "Phase 2 FAILED: server.js not found in artifact"
    exit 1
  }

  log "Artifact valid: server.js present, extraction successful"
}

# Phase 3
deploy_artifact() {
  log "=== Phase 3: Deploy to ${DEPLOY_ENV} environment ==="
  # DEPLOY_ENV is either "blue" (port 4000) or "green" (port 3000)
  local target_dir="/opt/kijanikiosk/${DEPLOY_ENV}"
  local staging="/opt/kijanikiosk/releases/staging-${APP_VERSION}"
  local current_version_file="${target_dir}/.version"

  # Idempotency: check if this version is already deployed to this environment
  if [ -f "${current_version_file}" ] && [ "$(cat ${current_version_file})" = "${APP_VERSION}" ]; then
    log "Version ${APP_VERSION} already deployed to ${DEPLOY_ENV}. Skipping copy."
    return 0
  fi

  # Create the target directory structure owned by the service account
  mkdir -p "${target_dir}"
  chown kk-api:kk-api "${target_dir}"

  # Copy the new version (atomic: copy then move, not overwrite directly)
  cp -r "${staging}/." "${target_dir}/new_version/"
  mv "${target_dir}/new_version" "${target_dir}/app"
  chown -R kk-api:kk-api "${target_dir}/app"

  # Record the deployed version
  echo "${APP_VERSION}" > "${current_version_file}"
  log "Deployed version ${APP_VERSION} to ${target_dir}"
}

# Phase 4
restart_service() {
  log "=== Phase 4: Restart ${DEPLOY_ENV} service ==="
  local service_name="kk-api-${DEPLOY_ENV}.service"

  systemctl daemon-reload
  systemctl restart "${service_name}" || {
    log_fail "Phase 4 FAILED: Could not restart ${service_name}"
    journalctl -u "${service_name}" --since "1 minute ago" --no-pager | tail -20
    exit 1
  }

  # Wait for the service to report active(running) - up to 30 seconds
  local retries=0
  while [ ${retries} -lt 30 ]; do
    if systemctl is-active --quiet "${service_name}"; then
      log "Service ${service_name} is active"
      return 0
    fi
    sleep 1
    retries=$((retries + 1))
  done

  log_fail "Phase 4 FAILED: ${service_name} did not become active within 30 seconds"
  journalctl -u "${service_name}" --since "1 minute ago" --no-pager | tail -20
  exit 1
}

# Phase 5

verify_service() {
  log "=== Phase 5: Verify ${DEPLOY_ENV} service health ==="
  local port="${BLUE_PORT}"
  [ "${DEPLOY_ENV}" = "green" ] && port="${GREEN_PORT}"
  local health_url="http://127.0.0.1:${port}/health"
  local retries=0

  while [ ${retries} -lt 10 ]; do
    response=$(curl -sf --max-time 5 "${health_url}" 2>/dev/null) && {
      # Check the response contains the expected version
      echo "${response}" | grep -q "\"version\":\"${APP_VERSION}\"" && {
        log "Health check passed: ${health_url} returned version ${APP_VERSION}"
        return 0
      }
      log "Health check responded but version mismatch: ${response}"
    }
    sleep 3
    retries=$((retries + 1))
  done

  log_fail "Phase 5 FAILED: Health check did not pass after $((retries * 3)) seconds"
  log_fail "URL: ${health_url}"
  journalctl -u "kk-api-${DEPLOY_ENV}.service" --since "1 minute ago" --no-pager | tail -20
  exit 1
}

main "$@"