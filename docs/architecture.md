# Architecture

## System Diagram

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
                                              |  GitHub Container      |
                                              |  Registry (GHCR)       |
                                              |  immutable SHA tags    |
                                              +------------------------+
                                                          |
                              SSH + deploy.sh             v
+----------------------+ ----------------------> +---------------------------+
|  GitHub Actions      |                         |  Ubuntu VPS               |
|  Runner              |                         |                           |
+----------------------+                         |  blue  :  127.0.0.1:3001  |
                                                 |  green :  127.0.0.1:3002  |
                                                 |  nginx :  0.0.0.0:80      |
                                                 +---------------------------+
```

## Design Decisions

### Why Nginx instead of exposing the app directly
Nginx is the only process bound to the public interface (`0.0.0.0:80`). The app containers bind to `127.0.0.1` only. This means a misconfigured or crashed app container cannot accidentally accept public traffic, and Nginx handles connection limits, logging, and proxy headers centrally.

### Why blue/green instead of restart-in-place
An in-place restart creates a window where the old version is stopped but the new version has not yet started. During that window the service is unavailable. With blue/green, the new version starts and passes healthchecks before Nginx switches — zero-downtime by design.

### Why the healthcheck runs before Nginx switches
If the new container starts but the app crashes, hangs, or fails to connect to dependencies, `deploy.sh` exits with an error and Nginx is never touched. Production traffic continues on the old slot. This is the critical safety gate.

### Why the old slot stays running after deployment
Rollback is a single Nginx reload, not a container restart. Because the previous slot is still running and healthy, `rollback.sh` can switch traffic back in under 5 seconds without pulling or starting anything.

### Why immutable SHA tags
Using `:latest` for deployment means you cannot reproduce a specific release. SHA tags (`abc1234`) tie every GHCR image to an exact commit. A deployment can always be rerun with the same image, and the active version is visible in `/health` and `/version` responses.

## Pipeline Stages

| Stage | Trigger | What it does |
|---|---|---|
| CI | All pushes and PRs | Installs deps, runs tests |
| Docker build | After CI passes | Builds image; pushes to GHCR on main only |
| Security scan | After build, main only | Trivy scans the pushed image for CVEs |
| Deploy | main + `DEPLOY_ENABLED=true` | Copies scripts, runs deploy.sh over SSH |
| Smoke test | After deploy | Curls the public `/health` endpoint |

## Ports

| What | Where |
|---|---|
| Nginx (public) | `0.0.0.0:80` |
| Blue slot | `127.0.0.1:3001` |
| Green slot | `127.0.0.1:3002` |
| App inside container | `127.0.0.1:3000` |
