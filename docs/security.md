# Security Decisions

## Implemented

| Decision | Reason |
|---|---|
| SSH credentials stored as GitHub Secrets | Never committed to the repository |
| Minimal GitHub Actions permissions (`contents: read`, `packages: write`) | Least privilege — the workflow cannot read org secrets or modify repo settings |
| Container runs as non-root user (`appuser`) | A process escape from the container cannot write to the host as root |
| App containers bind to `127.0.0.1` only | Nginx is the only public HTTP entry point; app ports are not reachable from the internet |
| Immutable SHA image tags | Every deployment references an exact, auditable image — no surprise changes from `:latest` |
| Trivy vulnerability scan in the pipeline | CVEs in the base image or dependencies are caught before production |
| `concurrency: cancel-in-progress: false` | Prevents two deployments running in parallel and corrupting slot state |
| No secrets committed anywhere | `.gitignore` excludes `.env` files; bootstrap and deploy scripts use environment variables |

## Future Hardening

The following are standard next steps for a production system:

- **Pin GitHub Actions to full commit SHAs** — using `actions/checkout@v4` trusts the tag. Pinning to a SHA (e.g. `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af68`) eliminates risk from a compromised action tag.
- **OIDC instead of static SSH keys** — cloud providers support OIDC federation so GitHub Actions can authenticate without a stored private key.
- **HTTPS with Let's Encrypt / Certbot** — the current setup serves plain HTTP. `certbot --nginx` adds TLS in minutes.
- **Image signing with Cosign** — proves the image in GHCR was built by the expected pipeline and was not tampered with.
- **SLSA provenance** — generates a verifiable build attestation linking the image to its source commit.
- **SBOM generation** — produces a software bill of materials for supply-chain auditing.
- **Dependabot / Renovate** — automated PRs when dependencies or base image versions have available updates.
- **Second scanner (Docker Scout or Grype)** — running two scanners reduces false-negative risk.
- **Centralized logging** — shipping container logs to a SIEM or log aggregator (Loki, CloudWatch) rather than relying on `docker logs`.
- **Prometheus + Grafana** — adds metrics and alerting; currently the only health signal is the `/health` endpoint.
- **Replace SSH deployment with GitOps** — for Kubernetes environments, Argo CD eliminates the need for SSH access from CI runners entirely.

## Supply-Chain Risk Note

CI/CD tooling itself is a supply-chain risk. A compromised third-party GitHub Action with write access to `GITHUB_TOKEN` could exfiltrate secrets or push malicious images. Mitigations: pin to SHAs, review action source code before adopting, restrict `GITHUB_TOKEN` permissions to the minimum required.
