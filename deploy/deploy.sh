#!/usr/bin/env bash
# Blue/green deployment script.
# Deploys IMAGE_NAME to the inactive slot, healthchecks it, then switches Nginx.
# Old slot stays running for instant rollback.
set -euo pipefail

APP_DIR="/opt/senior-devops-cicd"
COMPOSE_FILE="${APP_DIR}/docker-compose.slot.yml"
NGINX_TEMPLATE="${APP_DIR}/nginx-template.conf"
NGINX_SITE="/etc/nginx/sites-available/senior-devops-cicd"
NGINX_ENABLED="/etc/nginx/sites-enabled/senior-devops-cicd"
CURRENT_SLOT_FILE="${APP_DIR}/current_slot"
PREVIOUS_SLOT_FILE="${APP_DIR}/previous_slot"
DEPLOYMENT_LOG="${APP_DIR}/deployments.log"

: "${IMAGE_NAME:?IMAGE_NAME is required}"
: "${APP_VERSION:?APP_VERSION is required}"

mkdir -p "${APP_DIR}"
cd "${APP_DIR}"

# Determine which slot is active and which to deploy to
if [ -f "${CURRENT_SLOT_FILE}" ]; then
  CURRENT_SLOT="$(cat "${CURRENT_SLOT_FILE}")"
else
  CURRENT_SLOT="none"
fi

if [ "${CURRENT_SLOT}" = "blue" ]; then
  TARGET_SLOT="green"
  TARGET_PORT="3002"
elif [ "${CURRENT_SLOT}" = "green" ]; then
  TARGET_SLOT="blue"
  TARGET_PORT="3001"
else
  TARGET_SLOT="blue"
  TARGET_PORT="3001"
fi

echo "==> Current slot : ${CURRENT_SLOT}"
echo "==> Target slot  : ${TARGET_SLOT} on port ${TARGET_PORT}"
echo "==> Image        : ${IMAGE_NAME}"
echo "==> Version      : ${APP_VERSION}"

# Write env file for this slot
cat > ".env.${TARGET_SLOT}" <<ENVEOF
IMAGE_NAME=${IMAGE_NAME}
APP_VERSION=${APP_VERSION}
APP_SLOT=${TARGET_SLOT}
APP_PORT=${TARGET_PORT}
ENVEOF

echo "==> Pulling image and starting target slot..."
docker compose --env-file ".env.${TARGET_SLOT}" -f "${COMPOSE_FILE}" pull
docker compose --env-file ".env.${TARGET_SLOT}" -f "${COMPOSE_FILE}" up -d

# Healthcheck the new slot before touching Nginx
echo "==> Healthchecking target slot (up to 2 minutes)..."
for i in $(seq 1 24); do
  if curl -fsS "http://127.0.0.1:${TARGET_PORT}/health" > /tmp/senior-cicd-health.json 2>/dev/null; then
    echo "==> Target slot healthy:"
    cat /tmp/senior-cicd-health.json
    echo
    break
  fi
  if [ "${i}" -eq 24 ]; then
    echo "ERROR: Target slot failed healthcheck after 2 minutes. Production traffic unchanged."
    docker logs "senior-cicd-${TARGET_SLOT}" --tail=50 || true
    exit 1
  fi
  echo "    Attempt ${i}/24 — waiting 5s..."
  sleep 5
done

# Switch Nginx to the new slot
echo "==> Switching Nginx to port ${TARGET_PORT}..."
sed "s/{{APP_PORT}}/${TARGET_PORT}/g" "${NGINX_TEMPLATE}" | sudo tee "${NGINX_SITE}" >/dev/null
sudo ln -sf "${NGINX_SITE}" "${NGINX_ENABLED}"
sudo nginx -t
sudo systemctl reload nginx

# Public smoke test through Nginx
echo "==> Running public smoke test through Nginx..."
for i in $(seq 1 12); do
  if curl -fsS "http://127.0.0.1/health" > /tmp/senior-cicd-public-health.json 2>/dev/null; then
    echo "==> Public smoke test passed:"
    cat /tmp/senior-cicd-public-health.json
    echo
    break
  fi
  if [ "${i}" -eq 12 ]; then
    echo "ERROR: Public smoke test failed after Nginx switch."
    exit 1
  fi
  echo "    Attempt ${i}/12 — waiting 5s..."
  sleep 5
done

# Record state
[ "${CURRENT_SLOT}" != "none" ] && echo "${CURRENT_SLOT}" > "${PREVIOUS_SLOT_FILE}"
echo "${TARGET_SLOT}" > "${CURRENT_SLOT_FILE}"
echo "$(date -Is) image=${IMAGE_NAME} version=${APP_VERSION} slot=${TARGET_SLOT} port=${TARGET_PORT} previous=${CURRENT_SLOT}" >> "${DEPLOYMENT_LOG}"

echo ""
echo "==> Deployment complete"
echo "    Active slot   : ${TARGET_SLOT} (port ${TARGET_PORT})"
echo "    Previous slot : ${CURRENT_SLOT} (kept running for rollback)"
