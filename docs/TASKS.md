# Task Details

---

## Task 1 — Terraform: Fix and Extend a Broken EKS Module

**Directory:** `terraform/`

### Background

A colleague started provisioning an EKS cluster in AWS but left the configuration in a broken state before going on leave. The `staging` environment references an `eks-cluster` module that has several bugs and missing pieces.

### Your Tasks

**1a. Fix the bugs** in `terraform/environments/staging/main.tf` and `terraform/modules/eks-cluster/main.tf`. There are at least **4 intentional errors** — find and fix them. Document each fix with a comment explaining what was wrong.

**1b. Extend the module** to add the following, which the team needs before go-live:

- An **IRSA (IAM Role for Service Accounts)** resource that allows a Kubernetes service account named `app-sa` in namespace `default` to assume a role with `s3:GetObject` and `s3:ListBucket` permissions on a bucket whose name is passed as a variable `var.app_bucket_name`.
- A **node group** that uses `t3.medium` instances, with a minimum of 1 and maximum of 3 nodes, using a launch template that adds the tag `Environment = var.environment`.

**1c. Add a `terraform/environments/staging/backend.tf`** that configures remote state using S3 + DynamoDB locking. Use variables where appropriate.

### Constraints

- Do not hard-code AWS account IDs or region strings — use `data` sources or variables.
- All resources must have a `tags` block that includes at minimum `Environment` and `ManagedBy = "terraform"`.
- Write your module to be **reusable** — it should work for a `production` environment with different inputs.

### Deliverable

Working Terraform that passes `terraform validate`. Include a `terraform plan` output saved to `terraform/plan-output.txt` (you may use dummy credentials / `-target` / mock if you don't have an AWS account — explain your approach in SUBMISSION.md).

---

## Task 2 — Kubernetes: Harden a Misconfigured Deployment

**Directory:** `kubernetes/`

### Background

The application team has handed over Kubernetes manifests for a Node.js API service called `api-service`. The manifests work, but the security team has flagged several concerns and the SRE team has flagged reliability gaps.

### Current State

Review the manifests in `kubernetes/base/`. The deployment runs the app but has the following **known issues** (find them and fix them):

1. The container runs as **root**.
2. There are **no resource requests or limits** set.
3. There is **no liveness or readiness probe** configured.
4. The `SECRET_KEY` environment variable is sourced directly from a **plaintext ConfigMap** instead of a Secret.
5. There is **no PodDisruptionBudget** ensuring at least 1 pod is always available.
6. The Service is of type `LoadBalancer` — it should be `ClusterIP` since ingress is handled separately.

### Your Tasks

**2a. Fix all 6 issues** above in the manifests. For the secret, create a `Secret` manifest (you may use a placeholder value — explain how it would be populated in production in SUBMISSION.md).

**2b. Create a Kustomize overlay** in `kubernetes/overlays/staging/` that:
- Sets the replica count to `2`
- Sets the image tag to `v1.2.0`
- Adds the label `environment: staging` to all resources

**2c. Write a `NetworkPolicy`** in `kubernetes/base/network-policy.yaml` that:
- Allows ingress to `api-service` pods only from pods with label `role: ingress-controller`
- Allows egress to the cluster DNS (`kube-dns`) on port 53 only
- Denies all other ingress and egress by default

### Deliverable

Updated manifests that pass `kubectl --dry-run=client -f .` validation. Include a short comment on each fix explaining the security or reliability rationale.

---

## Task 3 — CI/CD: Repair and Improve a GitHub Actions Pipeline

**Directory:** `ci-cd/pipeline.yml`

### Background

The pipeline was written by a developer unfamiliar with GitHub Actions best practices. It builds a Docker image, runs tests, and pushes to Amazon ECR — but it has bugs and security problems.

### Your Tasks

**3a. Find and fix all bugs.** The pipeline as written will not run successfully. There are at least **5 problems** (syntax errors, logic errors, missing steps).

**3b. Apply security improvements:**
- Replace any hardcoded credentials with GitHub Actions OIDC-based authentication to AWS (no long-lived access keys).
- Ensure the Docker image is **not pushed on pull request events** — only on push to `main`.
- Add image vulnerability scanning using **Trivy** before the push step; fail the pipeline if `CRITICAL` vulnerabilities are found.

**3c. Add a deployment step** (after push) that:
- Updates the image tag in `kubernetes/overlays/staging/kustomization.yaml` using `kustomize edit set image`
- Commits and pushes the change back to the repository (GitOps pattern)
- Only runs on push to `main`

### Deliverable

A corrected and improved `ci-cd/pipeline.yml`. Add comments explaining each significant change you made.

---

## Task 4 — Scripting: Incident Triage Helper

**Directory:** `scripts/incident.sh`

### Background

When an on-call engineer gets paged for a degraded service, they currently run 10+ manual `kubectl` commands to gather information. You need to automate this into a single triage script.

### Your Tasks

Write a **Bash script** `scripts/incident.sh` that accepts a namespace and deployment name as arguments and outputs a structured triage report. The report must include:

1. **Deployment status** — desired vs ready replicas, rollout conditions
2. **Pod states** — list all pods, their status, restart count, and node
3. **Recent events** — last 20 events for the deployment and its pods (sorted by time)
4. **Last 50 log lines** — from each pod's primary container (last 50 lines, with timestamps)
5. **Resource usage** — CPU and memory for each pod (using `kubectl top`)
6. **HPA status** — if an HPA exists for this deployment, show its current metrics

The script must:
- Accept `-n <namespace>` and `-d <deployment>` flags (with sensible defaults)
- Exit with a non-zero code and clear error message if the deployment does not exist
- Output to both stdout and a timestamped log file in `/tmp/triage-<deployment>-<timestamp>.log`
- Be safe to run in production (no destructive operations)

### Deliverable

A working, well-commented Bash script. Include a `## Usage` block at the top of the file.

---

## Task 5 — Architecture: Design a Hybrid Observability Stack

**Directory:** `docs/`

### Background

Read `docs/architecture-brief.md` for context on the current hybrid infrastructure (on-premise Kubernetes + Amazon EKS).

### Your Tasks

Write a design document `docs/observability-design.md` that covers:

**5a. Metrics**
- What tooling you would use (e.g., Prometheus, VictoriaMetrics, Thanos, Amazon Managed Prometheus)
- How you handle scraping from both on-premise and EKS clusters
- How you federate or aggregate metrics into a single query layer
- How you manage retention and cost

**5b. Logging**
- Your recommended log shipping stack (agents, aggregator, storage)
- How you handle structured logging and trace correlation (tracing IDs)
- How you ensure logs from on-premise are reliably delivered to the central store

**5c. Alerting**
- How you define SLOs for a fictional API service with a target of 99.9% over 30 days
- Your alert fatigue strategy — what rules you'd create and why
- How on-call escalation works

**5d. Trade-offs**
- What you would prioritise with a limited budget (managed services vs self-hosted)
- What you would not do in the first 90 days, and why

### Constraints

- Keep it to **1,000–1,500 words**. Diagrams (Mermaid or ASCII) are welcome but not required.
- Write for a technical audience — avoid marketing language.

### Deliverable

`docs/observability-design.md` — a markdown file committed to your branch.
