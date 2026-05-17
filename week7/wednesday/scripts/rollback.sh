#!/usr/bin/env bash
# scripts/rollback.sh
# Rolls back to the previous active environment.
# Called automatically by the pipeline when the switch fails (exit code 3),
# or manually by an engineer after a bad deployment.

set -euo pipefail

ACTIVE_ENV_STATE="/opt/kijanikiosk/.active-env"
PREVIOUS_ENV_STATE="/opt/kijanikiosk/.previous-env"

log() { echo "[$(date -u +%H:%M:%S)] [ROLLBACK] $*"; }
log_fail() { echo "[$(date -u +%H:%M:%S)] [ROLLBACK FAIL] $*" >&2; }

# Determine where to roll back to
if [ -f "${PREVIOUS_ENV_STATE}" ]; then
  ROLLBACK_TARGET=$(cat "${PREVIOUS_ENV_STATE}")
  log "Rolling back to previous environment: ${ROLLBACK_TARGET}"
elif [ -f "${ACTIVE_ENV_STATE}" ]; then
  # If there is no previous-env record, infer it from the current active env
  CURRENT=$(cat "${ACTIVE_ENV_STATE}")
  ROLLBACK_TARGET="blue"
  [ "${CURRENT}" = "blue" ] && ROLLBACK_TARGET="green"
  log "No previous-env record. Inferring rollback target: ${ROLLBACK_TARGET}"
else
  log_fail "Cannot determine rollback target: no state files found"
  exit 1
fi

# Call the switch script with the rollback target
log "Calling switch-env.sh ${ROLLBACK_TARGET}..."
bash "$(dirname "$0")/switch-env.sh" "${ROLLBACK_TARGET}"
SWITCH_EXIT=$?

case ${SWITCH_EXIT} in
  0) log "Rollback to ${ROLLBACK_TARGET} successful." ;;
  1) log_fail "Rollback failed: pre-condition check failed. Manual intervention required." ;;
  2) log_fail "Rollback failed: nginx configuration error. Manual intervention required." ;;
  3) log_fail "Rollback failed: switch completed but health check did not confirm. Check nginx and ${ROLLBACK_TARGET} service status." ;;
esac

exit ${SWITCH_EXIT}