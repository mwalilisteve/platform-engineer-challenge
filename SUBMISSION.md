# Submission — Platform Engineer (DevOps) Challenge

**Candidate:** Steeve Titus Mwalili
**Date:** 10/5/2026
**Time spent:** ~3 hours

---

## Tasks Completed

- [x] Task 1a — Fixed Terraform bugs
- [x] Task 1b — Extended EKS module (IRSA + node group)
- [x] Task 1c — Added remote state backend config
- [x] Task 2a — Fixed all 6 Kubernetes issues
- [x] Task 2b — Created Kustomize staging overlay
- [x] Task 2c — Wrote NetworkPolicy
- [x] Task 3a — Fixed pipeline bugs
- [x] Task 3b — Applied security improvements (OIDC, Trivy)
- [x] Task 3c — Added GitOps update step
- [x] Task 4  — Wrote incident triage script
- [x] Task 5  — Wrote observability design document

---

## Key Decisions and Trade-offs

### Task 1 — Terraform

- **Bug 1 (ELB subnet tags):** Tags used integer `0`; AWS requires the string `"1"` for EKS to discover subnets when provisioning load balancers.
- **Bug 2 (Control-plane subnets):** Module was passed `public_subnets` — corrected to `private_subnets` to avoid exposing the API server.
- **Bug 3 (Module body):** `main.tf` was a copy of `variables.tf` with no resources. Rewrote it with the full EKS cluster, OIDC provider, IAM roles, and node group.
- **Bug 4 (Node group):** No instance type defined and scaling values were wrong. Moved instance type to a launch template (required to tag EC2 instances, not just the node group object) and corrected scaling to min 1 / max 3.
- **IRSA:** Trust policy uses both `sub` and `aud` conditions — omitting `aud` is a common mistake that over-permits role assumption.
- **Backend:** Static key string used intentionally — Terraform does not support variable interpolation in backend blocks. The `staging/eks-cluster/` path makes adding a production workspace straightforward.
- **Plan output:** No AWS account available. `terraform validate` passes. Reviewer instructions are in the "How to Test" section.

### Task 2 — Kubernetes

- **Secret handling:** `secret.yaml` commits a placeholder. In production, ESO + AWS Secrets Manager would inject the real value — it never touches the repo. Sealed Secrets is the simpler alternative for smaller teams.
- **NetworkPolicy:** Egress targets `kube-dns` pods using both `namespaceSelector` and `podSelector` — a `namespaceSelector` alone would allow all traffic to `kube-system`. Both TCP and UDP 53 are opened since DNS falls back to TCP for large responses.
- **PDB:** Used `minAvailable: 1` over `maxUnavailable: 1` — it stays correct if replicas are scaled to 1, whereas `maxUnavailable: 1` would allow full eviction.

### Task 3 — CI/CD

- **Trigger scoping:** Build and scan run on all pushes and PRs to `main`; ECR push and GitOps update are gated on `github.event_name == 'push'`. Kept in step-level `if:` conditions so PRs still get scan feedback without writing to ECR.
- **OIDC auth:** Long-lived credentials replaced with `configure-aws-credentials` OIDC. Only `AWS_ROLE_ARN` (an ARN, not a secret) is stored in GitHub Secrets.
- **Trivy:** `ignore-unfixed: true` suppresses noise for vulnerabilities with no available fix.

### Task 4 — Scripting

- `exec > >(tee -a "$LOG_FILE") 2>&1` captures all output (including subshell stderr) in one place rather than piping each command individually.
- Pod selector is extracted dynamically from `kubectl get deployment -o jsonpath` so the script works for any deployment.
- `kubectl top` and HPA sections degrade gracefully — missing metrics-server or no HPA does not fail the script.

### Task 5 — Architecture

Full design in `docs/observability-design.md`. Core trade-offs:

- **Loki self-hosted vs Grafana Cloud:** Managed Loki at this scale would consume ~2× the $800 budget. Self-hosting on two `m6i.large` nodes costs ~$180/month with equivalent capability.
- **Thanos vs VictoriaMetrics:** Thanos was chosen because the team already has Prometheus knowledge; it is a thin sidecar add-on rather than a full replacement. VictoriaMetrics is the natural migration path if operational complexity grows.

---

## Assumptions

- The API service exposes `/healthz` on port 3000. Adjust probe paths if different.
- EKS is in `af-south-1`, matching the architecture brief.
- The GitHub Actions OIDC IAM role is pre-created and stored as `secrets.AWS_ROLE_ARN`.
- Ingress controller pods carry the label `role: ingress-controller`. Update the `NetworkPolicy` `podSelector` to match your actual controller labels.

---

## What I Would Do With More Time

- **Terraform:** Run against an AWS sandbox and commit `plan-output.txt`. Add Terratest to verify the OIDC provider URL matches the cluster issuer.
- **Kubernetes:** Replace `secret.yaml` with an ESO `ExternalSecret`. Add a `ServiceAccount` for `app-sa` with the IRSA annotation and a `HorizontalPodAutoscaler` at 70% CPU.
- **CI/CD:** Add a `workflow_dispatch` trigger with an environment selector for manual deploys. Add Cosign image signing post-push.
- **Scripting:** Add `-o json` output mode for ticketing system ingestion. Add per-pod timeouts on `kubectl logs` to avoid blocking on stuck pods.
- **Observability:** Commit initial `PrometheusRule` CRDs and the ESO `ExternalSecret` for Grafana credentials.

---

## How to Test

### Task 1
```bash
cd terraform/environments/staging
terraform init
terraform validate
# With AWS credentials:
# terraform plan -var="app_bucket_name=my-bucket" -out=plan.tfplan
```

### Task 2
```bash
kubectl --dry-run=client apply -f kubernetes/base/
kubectl kustomize kubernetes/overlays/staging | kubectl --dry-run=client apply -f -
```

### Task 3
```
Push to master branch. Expected sequence:
  1. Build Docker image
  2. Run npm test
  3. Trivy scan (fails on CRITICAL CVEs)
  4. Push to ECR (push to main only, not PRs)
  5. Update kustomization.yaml and auto-commit
```

### Task 4
```bash
chmod +x scripts/incident.sh
./scripts/incident.sh -n default -d api-service
./scripts/incident.sh -n default -d does-not-exist  # expect exit 1
ls /tmp/triage-api-service-*.log
```