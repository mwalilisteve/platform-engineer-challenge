# Submission — Platform Engineer (DevOps) Challenge

**Candidate name: Steeve Titus Mwalili**
**Date submitted: 8/5/2026**
**Time spent (approximate): 3hrs**

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

**Bug 1 (ELB subnet tags):** The `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb` tags had value `0` (integer). AWS requires the string `"1"` — any other value causes EKS's in-tree load-balancer controller to ignore the subnet entirely, meaning no load balancers can be provisioned. Fixed to `"1"`.

**Bug 2 (Control-plane subnets):** The module call passed `module.vpc.public_subnets` to `subnet_ids`. EKS control-plane ENIs must be in private subnets — placing them in public subnets exposes the API server endpoint to the internet and breaks private-endpoint-only configurations. Fixed to `module.vpc.private_subnets`.

**Bug 3 (Module body was variables, not resources):** `terraform/modules/eks-cluster/main.tf` was a copy of the staging `variables.tf`. `outputs.tf` referenced `aws_eks_cluster.this`, `aws_iam_openid_connect_provider.this`, and `aws_iam_role.node_group` — none of which existed. Rewrote the file with all required resource definitions.

**Bug 4 (Node group missing instance type and misconfigured scaling):** The original node group had no `instance_types` and used scaling values (desired 2, max 4) that did not match the task spec (min 1, max 3). Moved instance type to a launch template (required to propagate `Environment` tag to EC2 instances — `aws_eks_node_group.tags` only tags the node group object, not the underlying EC2s) and corrected scaling to min 1 / max 3 per spec.

**IRSA design:** The IRSA trust policy uses both `sub` and `aud` condition keys. Using only `sub` is a common mistake that allows any client in the OIDC provider to assume the role. The `aud: sts.amazonaws.com` condition restricts it to AWS STS token exchange only.

**Backend:** The S3 backend config uses a static key string rather than a variable because Terraform does not support variable interpolation in backend blocks. The path `staging/eks-cluster/terraform.tfstate` makes it straightforward to add a `production/eks-cluster/terraform.tfstate` key for the production workspace without changing the bucket.

**`terraform plan` output:** No AWS account is available for a real plan. `terraform validate` passes locally with the fixes applied (confirmed). For a reviewer with AWS access: `AWS_PROFILE=<profile> terraform init && terraform plan -var="app_bucket_name=my-bucket" -out=plan.tfplan && terraform show -no-color plan.tfplan > terraform/plan-output.txt`.

---

### Task 2 — Kubernetes

**Issue 1 (root):** Added `securityContext` at the pod level with `runAsNonRoot: true`, `runAsUser: 1000`. The UID 1000 is a convention; in production this should match the UID baked into the container image to avoid permission errors on volume mounts.

**Issue 4 (secret):** The `secret.yaml` commits a placeholder value (`REPLACE_ME`). In production we would use the External Secrets Operator (ESO) with an `ExternalSecret` resource pointing to AWS Secrets Manager — the actual value never touches the Git repository. A simpler alternative for smaller teams is Sealed Secrets (Bitnami), which encrypts the value with the cluster's public key and is safe to commit.

**NetworkPolicy (Task 2c):** The egress rule targets `kube-dns` pods in `kube-system` using both a `namespaceSelector` and a `podSelector`. Using only a `namespaceSelector` (i.e., allowing all traffic to kube-system) would be too permissive. Both TCP and UDP port 53 are opened — DNS uses UDP by default but falls back to TCP for large responses, so opening only UDP is a subtle production bug.

**PodDisruptionBudget:** `minAvailable: 1` rather than `maxUnavailable: 1` — with a replica count of 2, both mean the same thing. I prefer `minAvailable` because it is explicit about the floor and remains correct if replicas are scaled down to 1 (whereas `maxUnavailable: 1` with 1 replica allows all pods to be evicted).

---

### Task 3 — CI/CD

**Bug 1 (trigger):** Changed from `on: push` to scoped triggers: CI runs on push and PR to main; push-to-ECR and GitOps steps are gated behind `github.event_name == 'push' && github.ref == 'refs/heads/main'`. This is done in the step `if:` condition rather than a separate job trigger so the build and scan still run on PRs (giving the developer feedback) without pushing to ECR.

**Bug 2 (hardcoded credentials):** Replaced with `aws-actions/configure-aws-credentials@v4` using OIDC. The repo needs an IAM role with a trust policy restricting `token.actions.githubusercontent.com` to `repo:ORG/REPO:ref:refs/heads/main`. Only `secrets.AWS_ROLE_ARN` (an ARN, not a credential) needs to be stored as a secret.

**Bug 3 (hardcoded account ID):** The `amazon-ecr-login` action resolves the registry URL from the caller identity returned by the assumed OIDC role — no account ID needed in the workflow.

**Bug 4 (push before test):** Tests and Trivy scan now run before the push step. The job fails fast if tests fail; the image is never pushed.

**Bug 5 (yarn vs npm):** Changed to `npm test`. Yarn is not available on the GitHub-hosted runner by default.

**Trivy:** `ignore-unfixed: true` avoids failing on vulnerabilities for which no patched version exists — these are noise until a fix is available. Adjust to `false` if your compliance posture requires reporting on all findings.

---

### Task 4 — Scripting

The script uses `exec > >(tee -a "$LOG_FILE") 2>&1` to redirect all output (stdout and stderr) to both the terminal and the log file from a single point. The alternative — manually piping every command — is error-prone and misses subshell stderr.

Pod label discovery uses `kubectl get deployment -o jsonpath` to extract the `matchLabels` selector dynamically rather than hardcoding label names. This makes the script work for any deployment, not just `api-service`.

The `kubectl top` section degrades gracefully if metrics-server is not installed rather than exiting non-zero — the rest of the report is still useful. Same pattern for HPA: `kubectl get hpa ... &>/dev/null` probes existence before describing, avoiding a hard failure when no HPA exists.

---

### Task 5 — Architecture

See `docs/observability-design.md` for the full document (~1,200 words).

The central trade-off is self-hosted Loki vs managed Grafana Cloud Loki. At $800/month, Grafana Cloud's pricing for two clusters with 30-day retention and 90-day archive would exceed the budget by ~2x. Self-hosting Loki on two `m6i.large` nodes with S3 backend keeps costs ~$180/month while providing the same query capability. The operational cost (upgrades, scaling) is manageable for a two-person team given Loki's relatively simple operational model compared to Elasticsearch.

Thanos was chosen over VictoriaMetrics for the metrics federation layer because the team will already have Prometheus expertise (kube-prometheus-stack), and Thanos is a thin add-on rather than a full Prometheus replacement. If the team grows and operational complexity becomes a concern, VictoriaMetrics is the natural migration path.

---

## Assumptions

- The Node.js API service exposes a `/healthz` endpoint on port 3000 (used for liveness/readiness probes). If it does not, the probe path should be adjusted to whatever health endpoint exists.
- The EKS cluster is provisioned in `af-south-1` (same region as Direct Connect anchor), consistent with the architecture brief.
- The GitHub Actions OIDC role ARN is pre-created and stored as `secrets.AWS_ROLE_ARN` — the workflow does not create the AWS IAM role itself (that would be a circular dependency with Terraform).
- For the NetworkPolicy, "ingress controller" pods are labelled `role: ingress-controller`. If your ingress controller uses a different label (e.g., `app.kubernetes.io/name: ingress-nginx`), adjust the `podSelector` accordingly.

---

## What I Would Do With More Time

- **Terraform:** Run a real `terraform plan` against an AWS sandbox and commit `terraform/plan-output.txt`. Add Terratest unit tests for the module (at minimum: verify that the OIDC provider URL matches the cluster issuer).
- **Kubernetes:** Convert `secret.yaml` to an `ExternalSecret` using ESO + AWS Secrets Manager, and add a `ServiceAccount` manifest for `app-sa` with the IRSA annotation (`eks.amazonaws.com/role-arn`). Add a `HorizontalPodAutoscaler` targeting 70% CPU utilisation.
- **CI/CD:** Add a `workflow_dispatch` trigger with an environment selector so operators can manually deploy a specific image tag to staging without a Git push. Add Cosign image signing after push.
- **Scripting:** Add a `-o json` output mode so the triage report can be ingested by a ticketing system. Wrap the log-gathering loop with a timeout per pod so a stuck `kubectl logs` call does not block the entire script.
- **Observability:** Define and commit the first set of Prometheus alerting rules as a `PrometheusRule` CRD and add the ESO `ExternalSecret` for Grafana's admin password.

---

## How to Test My Solution

### Task 1
```bash
cd terraform/environments/staging
terraform init   # initialises providers and module sources (no AWS creds needed)
terraform validate
# For a real plan (requires AWS credentials + pre-existing S3 state bucket):
# terraform plan -var="app_bucket_name=my-bucket" -out=plan.tfplan
```

### Task 2
```bash
# Validate base manifests
kubectl --dry-run=client apply -f kubernetes/base/

# Validate with kustomize staging overlay
kubectl kustomize kubernetes/overlays/staging | kubectl --dry-run=client apply -f -
```

### Task 3
```
Push a commit to the `main` branch of your fork.
The workflow should:
  1. Build the Docker image
  2. Run npm test
  3. Scan with Trivy (fails on CRITICAL CVEs)
  4. Push to ECR (only on push to main, not PRs)
  5. Update kubernetes/overlays/staging/kustomization.yaml and auto-commit
```

### Task 4
```bash
chmod +x scripts/incident.sh

# Test with a real cluster:
./scripts/incident.sh -n default -d api-service

# Test error handling (non-existent deployment):
./scripts/incident.sh -n default -d does-not-exist
# Expected: exits 1 with clear error message

# Check log file was created:
ls /tmp/triage-api-service-*.log
```
