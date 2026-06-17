#!/usr/bin/env bash
# Instant rollback: switches Nginx back to the previous healthy slot.
# Previous slot must still be running (deploy.sh keeps it alive).
set -euo pipefail

APP_DIR="/opt/senior-devops-cicd"
NGINX_TEMPLATE="${APP_DIR}/nginx-template.conf"
NGINX_SITE="/etc/nginx/sites-available/senior-devops-cicd"
NGINX_ENABLED="/etc/nginx/sites-enabled/senior-devops-cicd"
CURRENT_SLOT_FILE="${APP_DIR}/current_slot"
PREVIOUS_SLOT_FILE="${APP_DIR}/previous_slot"
DEPLOYMENT_LOG="${APP_DIR}/deployments.log"

cd "${APP_DIR}"

if [ ! -f "${PREVIOUS_SLOT_FILE}" ]; then
  echo "ERROR: No previous slot recorded. Cannot rollback."
  exit 1
fi

PREVIOUS_SLOT="$(cat "${PREVIOUS_SLOT_FILE}")"
CURRENT_SLOT="$(cat "${CURRENT_SLOT_FILE}" 2>/dev/null || echo none)"

if [ "${PREVIOUS_SLOT}" = "blue" ]; then
  TARGET_PORT="3001"
elif [ "${PREVIOUS_SLOT}" = "green" ]; then
  TARGET_PORT="3002"
else
  echo "ERROR: Invalid previous slot value: ${PREVIOUS_SLOT}"
  exit 1
fi

echo "==> Rolling back: ${CURRENT_SLOT} -> ${PREVIOUS_SLOT} (port ${TARGET_PORT})"

echo "==> Verifying previous slot is still healthy..."
curl -fsS "http://127.0.0.1:${TARGET_PORT}/health"
echo

echo "==> Switching Nginx to previous slot..."
sed "s/{{APP_PORT}}/${TARGET_PORT}/g" "${NGINX_TEMPLATE}" | sudo tee "${NGINX_SITE}" >/dev/null
sudo ln -sf "${NGINX_SITE}" "${NGINX_ENABLED}"
sudo nginx -t
sudo systemctl reload nginx

echo "==> Verifying public endpoint after rollback..."
curl -fsS "http://127.0.0.1/health"
echo

# Swap slot files
echo "${PREVIOUS_SLOT}" > "${CURRENT_SLOT_FILE}"
echo "${CURRENT_SLOT}" > "${PREVIOUS_SLOT_FILE}"
echo "$(date -Is) rollback active=${PREVIOUS_SLOT} reverted_from=${CURRENT_SLOT}" >> "${DEPLOYMENT_LOG}"

echo ""
echo "==> Rollback complete. Active slot: ${PREVIOUS_SLOT}"
