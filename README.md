# Production-Style CI/CD Platform

![CI](https://github.com/DenysMerzlykyn/senior-devops-cicd-platform/actions/workflows/ci-cd.yml/badge.svg)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?style=flat&logo=node.js&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-009639?style=flat&logo=nginx&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=github-actions&logoColor=white)

---

## Executive Summary

This project demonstrates a production-style delivery platform for a containerised web application. It implements automated testing, Docker image publishing to GitHub Container Registry, security scanning, deployment to an Ubuntu server, Nginx reverse proxying, blue/green release strategy, post-deployment validation, and rollback automation.

The application itself is intentionally simple. The DevOps platform around it is the main value.

---

## Architecture

```
+------------------+       +--------------------+       +----------------------+
| Developer Laptop | ----> | GitHub Repository  | ----> |   GitHub Actions     |
+------------------+       +--------------------+       +----------------------+
                                                           |
                                              +-----------+------------+
                                              |           |            |
                                              v           v            v
                                          +-------+  +--------+  +----------+
                                          |  CI   |  | Docker |  | Security |
                                          | Tests |  | Build  |  |   Scan   |
                                          +-------+  +--------+  +----------+
                                                          |
                                                          v
                                              +------------------------+
                                              |         GHCR           |
                                              |  immutable SHA tags    |
                                              +------------------------+
                                                          |
                                                          v SSH
                                              +---------------------------+
                                              |  Ubuntu Server            |
                                              |                           |
                                              |  blue  : 127.0.0.1:3001  |
                                              |  green : 127.0.0.1:3002  |
                                              |  nginx : 0.0.0.0:80      |
                                              +---------------------------+
```

---

## Pipeline Flow

| Stage | Trigger | Action |
|---|---|---|
| **CI** | All pushes and PRs | Install dependencies, run tests |
| **Docker Build** | After CI passes | Build image; push to GHCR on `main` only |
| **Security Scan** | After build (`main` only) | Trivy scans the pushed image for CVEs |
| **Deploy** | `main` + `DEPLOY_ENABLED=true` | Copies scripts, runs blue/green deploy via SSH |
| **Smoke Test** | After deploy | Verifies public `/health` endpoint |

Pull requests run CI and a Docker build test only — no push, no deployment.

---

## Technology Stack

| Component | Technology |
|---|---|
| Application | Node.js 20, Express |
| Container | Docker, Alpine base image |
| Image Registry | GitHub Container Registry (GHCR) |
| CI/CD | GitHub Actions |
| Security Scanning | Trivy |
| Reverse Proxy | Nginx |
| Deployment Strategy | Blue/Green |
| Server | Ubuntu (any VPS) |
| Automation | Bash scripts |

---

## Repository Structure

```
senior-devops-cicd-platform/
├── .github/workflows/
│   └── ci-cd.yml              # Full CI/CD pipeline definition
├── app/
│   ├── server.js              # Express application
│   ├── server.test.js         # Node built-in test runner
│   ├── package.json
│   └── package-lock.json
├── deploy/
│   ├── bootstrap-server.sh    # One-time server setup (Docker, Nginx, UFW)
│   ├── docker-compose.slot.yml # Slot-based compose definition
│   ├── deploy.sh              # Blue/green deploy with healthcheck gate
│   ├── rollback.sh            # Instant rollback to previous slot
│   └── nginx-template.conf    # Nginx proxy config template
├── docs/
│   ├── architecture.md        # System design and decisions
│   ├── runbook.md             # Operational commands and incident scenarios
│   └── security.md            # Security decisions and future hardening
├── screenshots/               # Pipeline and deployment proof for portfolio
├── Dockerfile
├── .dockerignore
├── Makefile
└── README.md
```

---

## Local Development

**Requirements:** Docker, Node.js 20

```bash
git clone https://github.com/DenysMerzlykyn/senior-devops-cicd-platform.git
cd senior-devops-cicd-platform

# Install dependencies and run tests
make install
make test

# Run locally without Docker
make start
```

---

## Docker Build

```bash
# Build the image
make docker-build

# Run locally
make docker-run
```

Test:

```bash
curl http://localhost:3000/health
```

Expected:

```json
{
  "status": "ok",
  "service": "senior-devops-cicd-app",
  "environment": "local",
  "version": "local",
  "slot": "local"
}
```

---

## GitHub Actions Workflow

The pipeline is defined in [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml).

Key design choices:
- **Least-privilege permissions** — only `contents: read` and `packages: write`
- **Concurrency lock** — `cancel-in-progress: false` prevents parallel production deploys
- **Immutable tags** — images tagged with commit SHA, not just `:latest`
- **PR safety** — pull requests build but never push or deploy
- **GHCR login before Trivy** — scanner authenticates to pull the private image

---

## GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Value |
|---|---|
| `SERVER_HOST` | VPS IP address or domain |
| `SERVER_USER` | Linux user (e.g. `ubuntu`) |
| `SERVER_SSH_KEY` | Private SSH key content |

Then go to **Settings → Secrets and variables → Actions → Variables** and add:

| Variable | Value |
|---|---|
| `DEPLOY_ENABLED` | `true` |

Without `DEPLOY_ENABLED=true`, the deploy and smoke test jobs are skipped — the pipeline still shows green for CI, build, and scan.

---

## Server Bootstrap

On a fresh Ubuntu server:

```bash
scp deploy/bootstrap-server.sh ubuntu@YOUR_SERVER:/tmp/
ssh ubuntu@YOUR_SERVER
chmod +x /tmp/bootstrap-server.sh
sudo /tmp/bootstrap-server.sh
```

This installs Docker, Nginx, and UFW, and opens ports 22 and 80.

---

## Deployment Strategy — Blue/Green

```
Current active slot: blue  →  127.0.0.1:3001
New deployment slot: green →  127.0.0.1:3002

deploy.sh:
  1. Pulls new image to green slot
  2. Starts green container
  3. Healthchecks green for up to 2 minutes
  4. If healthy: rewrites Nginx config, reloads Nginx
  5. If unhealthy: exits — blue keeps serving traffic
  6. Blue stays running for rollback
```

Each deployment alternates between slots. The active slot and version are visible in every `/health` response.

---

## Rollback Procedure

SSH into the server and run:

```bash
cd /opt/senior-devops-cicd
sudo ./rollback.sh
```

Rollback verifies the previous slot is still healthy, switches Nginx, and completes in seconds. No container restart required.

To verify:

```bash
curl http://YOUR_SERVER/health
cat /opt/senior-devops-cicd/current_slot
cat /opt/senior-devops-cicd/deployments.log
```

---

## Security Decisions

- SSH credentials stored in GitHub Secrets — never committed
- Container runs as non-root user
- App containers bind to `127.0.0.1` only — not exposed publicly
- Nginx is the only public HTTP entry point
- Minimal `GITHUB_TOKEN` permissions
- Trivy scans for CRITICAL and HIGH CVEs on every push to `main`
- Immutable SHA image tags

See [`docs/security.md`](docs/security.md) for full detail and future hardening steps.

---

## Makefile Commands

| Command | Description |
|---|---|
| `make install` | Install Node.js dependencies |
| `make test` | Run tests |
| `make start` | Start app locally (no Docker) |
| `make docker-build` | Build Docker image |
| `make docker-run` | Run Docker image locally on port 3000 |
| `make clean` | Remove local blue/green containers |

---

## Troubleshooting

**Pipeline fails: `repository name must be lowercase`**
Check that `IMAGE_NAME` in the workflow uses only lowercase characters.

**Docker push denied**
Verify `packages: write` permission exists in the workflow and the image path is lowercase.

**SSH connection fails**
Check `SERVER_HOST`, `SERVER_USER`, `SERVER_SSH_KEY` secrets. Verify SSH access manually: `ssh user@host`.

**Nginx healthcheck fails on server**
```bash
sudo nginx -t
sudo systemctl status nginx
curl http://127.0.0.1:3001/health
curl http://127.0.0.1:3002/health
docker ps
```

See [`docs/runbook.md`](docs/runbook.md) for full incident scenarios.

---

## Screenshots

Pipeline and deployment screenshots are collected in [`screenshots/`](screenshots/).

---

## Interview Talking Points

**On pipeline design:**
> I separated CI, image build, security scanning, and deployment into independent jobs so failures are isolated and easy to debug.

**On image tagging:**
> I use immutable commit SHA tags so every deployment references an exact, auditable build. `:latest` alone makes it impossible to reproduce a specific release.

**On blue/green:**
> The pipeline deploys to the inactive slot and validates it with a healthcheck before Nginx traffic switches. If the new version is unhealthy, production is never touched.

**On rollback:**
> Rollback is fast because the previous slot stays running. The rollback script only reloads Nginx — no container pull or restart needed.

**On security:**
> App containers bind to localhost only. Nginx is the only public entry point. SSH credentials live in GitHub Secrets and are never written to disk or logged.

**On what comes next:**
> For a larger platform I would add Terraform for server provisioning, Kubernetes with Helm charts, Argo CD for GitOps, OIDC instead of SSH keys, Cosign image signing, and Prometheus with Grafana for observability.

---

## Future Improvements

- HTTPS with Let's Encrypt / Certbot
- Terraform for VPS provisioning
- Kubernetes + Helm chart version
- Argo CD GitOps deployment
- OIDC authentication (no static SSH keys)
- Image signing with Cosign and SLSA provenance
- Dependabot for dependency updates
- Prometheus + Grafana monitoring
- Loki centralised logging
- Load testing with k6
- Automatic rollback if smoke test fails
