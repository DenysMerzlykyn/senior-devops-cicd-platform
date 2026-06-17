# Operational Runbook

## Common Commands

```bash
# Check which slot is active
cat /opt/senior-devops-cicd/current_slot

# Check previous slot (available for rollback)
cat /opt/senior-devops-cicd/previous_slot

# View deployment history
cat /opt/senior-devops-cicd/deployments.log

# Check running containers
docker ps

# Tail logs for active slot
docker logs senior-cicd-blue --tail=100 -f
docker logs senior-cicd-green --tail=100 -f

# Check Nginx config validity
sudo nginx -t

# Reload Nginx without downtime
sudo systemctl reload nginx

# Check public health endpoint
curl http://127.0.0.1/health

# Check individual slot health (bypassing Nginx)
curl http://127.0.0.1:3001/health   # blue
curl http://127.0.0.1:3002/health   # green
```

## Rollback

```bash
cd /opt/senior-devops-cicd
sudo ./rollback.sh
```

Rollback switches Nginx back to the previous slot. It verifies the previous slot is healthy before switching. The operation completes in seconds because the container is already running.

## Incident Scenarios

### Scenario 1 — New container fails healthcheck before Nginx switch
`deploy.sh` exits with error code 1 before touching Nginx. Production traffic remains on the current active slot. Check container logs:
```bash
docker logs senior-cicd-<target-slot> --tail=100
```

### Scenario 2 — Nginx config or reload fails
`deploy.sh` runs `nginx -t` before reload. If the config is invalid, the script exits and does not reload Nginx. Production is unchanged. Fix the Nginx template and redeploy.

### Scenario 3 — Public smoke test fails after Nginx switch
The deploy job in GitHub Actions fails. The new slot is active in Nginx but the public endpoint is not responding. Check:
```bash
sudo systemctl status nginx
curl http://127.0.0.1/health
curl http://127.0.0.1:<target-port>/health
docker ps
```
If the issue is confirmed, run manual rollback.

### Scenario 4 — Bad release already in production
```bash
cd /opt/senior-devops-cicd
sudo ./rollback.sh
```
Then investigate the container logs of the broken slot before attempting another deployment.

### Scenario 5 — Both slots are down
```bash
# Pull and start blue manually
cd /opt/senior-devops-cicd
IMAGE_NAME=<last-known-good-image> APP_VERSION=manual APP_SLOT=blue APP_PORT=3001 \
  docker compose -f docker-compose.slot.yml up -d
curl http://127.0.0.1:3001/health
# Then switch Nginx manually
sed "s/{{APP_PORT}}/3001/g" nginx-template.conf | sudo tee /etc/nginx/sites-available/senior-devops-cicd
sudo nginx -t && sudo systemctl reload nginx
```
