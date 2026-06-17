#!/usr/bin/env bash
# Idempotent bootstrap for a fresh Ubuntu VPS.
# Run once as root: sudo ./bootstrap-server.sh
set -euo pipefail

APP_DIR="/opt/senior-devops-cicd"

if [ "${EUID}" -ne 0 ]; then
  echo "Run as root: sudo ./bootstrap-server.sh"
  exit 1
fi

echo "==> Updating packages..."
apt-get update -y
apt-get upgrade -y

echo "==> Installing dependencies..."
apt-get install -y ca-certificates curl gnupg nginx ufw

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker..."
  curl -fsSL https://get.docker.com | sh
else
  echo "==> Docker already installed: $(docker --version)"
fi

echo "==> Creating app directory..."
mkdir -p "${APP_DIR}"

echo "==> Enabling services..."
systemctl enable docker
systemctl enable nginx
systemctl restart nginx

echo "==> Configuring firewall..."
ufw allow OpenSSH
ufw allow "Nginx Full"
ufw --force enable

echo ""
echo "Bootstrap complete."
echo "  Docker:  $(docker --version)"
echo "  Compose: $(docker compose version)"
echo "  Nginx:   $(nginx -v 2>&1)"
echo "  UFW:     $(ufw status | head -1)"
echo ""
echo "Next: add GitHub Secrets SERVER_HOST, SERVER_USER, SERVER_SSH_KEY"
echo "      set repo variable DEPLOY_ENABLED=true"
echo "      push to main to trigger first deployment"
