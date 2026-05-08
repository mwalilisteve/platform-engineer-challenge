# Observability Design — Hybrid Cluster Stack

**Author:** Steeve Titus Mwalili  
**Date:** 2026-05-08  
**Scope:** On-premise Kubernetes (Nairobi, kubeadm v1.29) + Amazon EKS (af-south-1, v1.30)

---

## 5a. Metrics

### Tooling Choice: Prometheus + Thanos + Amazon Managed Prometheus (AMP)

Each cluster runs a **Prometheus** instance (deployed via the kube-prometheus-stack Helm chart) responsible for local scraping only. No remote-write fan-out from a single central Prometheus — that pattern creates a single point of failure and does not scale.

**On-premise cluster:** Prometheus scrapes Node Exporter (already deployed), kube-state-metrics, and any application `/metrics` endpoints. A **Thanos Sidecar** runs alongside Prometheus, uploading 2-hour TSDB blocks to an S3-compatible store (MinIO on-prem, or directly to S3 over Direct Connect).

**EKS cluster:** Prometheus scrapes the managed node groups and application pods. IRSA grants the Thanos Sidecar write access to the same S3 bucket (or to AMP via remote-write). Given the $800/month budget, AMP is worth evaluating here — at current af-south-1 pricing, ingesting ~50M samples/month is well within budget and eliminates the operational cost of managing Thanos Compactor and Store.

**Single query layer:** A **Thanos Query** deployment (could run on-prem or as a small EKS workload) fans out queries across both Thanos Sidecars and the AMP remote-write endpoint via the Prometheus API compatibility layer. Grafana connects to Thanos Query as a single data source — on-call engineers see a unified view.

**Retention:**
- Hot (15 days): Local Prometheus TSDB on each cluster, 50Gi PVC.
- Cold (90 days): S3 with Thanos Compactor running 2h → 24h → 7d downsampling. Compacted blocks are cheap; at ~1–2 USD/GB/month in af-south-1, 90-day cold storage for two clusters stays well under $100/month.

---

## 5b. Logging

### Stack: Fluent Bit → Loki → S3 (Glacier for archive)

**Agent:** Replace the existing Fluentd (on-prem) and the absent EKS agent with **Fluent Bit** across both clusters. Fluent Bit uses ~10x less memory than Fluentd and is the CNCF-recommended replacement. It runs as a DaemonSet on all nodes.

**On-premise reliability:** Fluent Bit's tail input uses a SQLite database to track file offsets. Even if the Direct Connect link degrades, the agent buffers to local disk (configurable up to several GiB) and retries with exponential back-off. No logs are dropped during transient outages.

**Transport:** Fluent Bit ships logs over TLS to a **Grafana Loki** instance running on EKS (or to an AWS-managed Loki equivalent). TLS is non-negotiable given the current setup ships logs without it — this is an ISO 27001 finding waiting to happen. Direct Connect provides the private path; Fluent Bit's forward output uses mutual TLS.

**Structured logging and trace correlation:** Applications must emit JSON logs with a `trace_id` field (aligned to OpenTelemetry's `traceparent` convention). Fluent Bit's `record_modifier` filter promotes `trace_id` to a Loki label, enabling log-to-trace correlation in Grafana (LogQL `{app="api-service"} | json | trace_id="abc123"`). Development teams get a Loki label schema document as part of onboarding — enforcing it at the agent level rather than the app level means it works even for teams that don't control their logging library.

**Data residency:** Customer PII logs are tagged at the app level (`pii: "true"` label). Fluent Bit routing rules ensure these logs are written only to Loki backed by S3 in af-south-1. Non-PII operational logs may be shipped anywhere.

**Retention:**
- 30-day queryable: Loki with S3 backend.
- 1-year archived: S3 Lifecycle rule transitions logs to Glacier after 30 days (~$0.004/GB/month). A Loki ruler query can re-hydrate on demand.

---

## 5c. Alerting

### SLO Definition for the API Service (99.9% over 30 days)

99.9% availability over 30 days means an error budget of **43.2 minutes** of downtime. We express this as two SLIs:

1. **Availability SLI:** `(sum(rate(http_requests_total{job="api-service",code!~"5.."}[5m])) / sum(rate(http_requests_total{job="api-service"}[5m])))` — must stay ≥ 0.999.
2. **Latency SLI:** p99 response time < 500 ms for ≥ 99% of requests.

Alerts fire at two burn rates (Google SRE "multi-window" approach):
- **Fast burn (page):** Error budget burning >14.4x normal over the last 1 hour AND last 5 minutes → immediate page to on-call.
- **Slow burn (ticket):** Error budget burning >3x normal over the last 6 hours AND last 30 minutes → creates a high-priority ticket, no page.

### Alert Fatigue Strategy

Rules we create on day 1: fast-burn SLO page, slow-burn SLO ticket, `KubePodCrashLooping`, `KubeDeploymentReplicasMismatch`, `TargetDown` (Prometheus scrape targets). That is five rules total.

Rules we explicitly do NOT create on day 1: CPU/memory thresholds ("pod used 80% CPU" fires constantly and drives no action), individual node disk pressure (covered by PDB + node-level eviction), per-endpoint latency (too noisy before we have baseline data).

The test for adding any new alert: *"If this fires at 3 AM, would the on-call engineer take a different action than they would at 9 AM?"* If no, it is a dashboard metric, not an alert.

### On-call Escalation

PagerDuty is already configured but untriggered. The escalation path:
1. **L1 (on-call platform engineer):** Acknowledges within 5 minutes via the incident.sh script for initial triage.
2. **L2 (second platform engineer):** Auto-escalated if unacknowledged after 15 minutes.
3. **L3 (engineering manager):** Auto-escalated after 30 minutes of unacknowledged critical alert.

Postmortems are blameless and filed within 48 hours of any SEV-1.

---

## 5d. Trade-offs

### Budget Allocation (~$800/month)

| Service | Estimated Monthly Cost | Rationale |
|---|---|---|
| AMP (EKS metrics remote-write) | ~$80 | Eliminates Thanos Compactor/Store ops burden |
| Loki on EKS (2×m6i.large) | ~$180 | Self-hosted; managed Grafana Cloud Loki exceeds budget |
| S3 (logs + metrics cold storage) | ~$60 | Lifecycle to Glacier keeps costs low |
| Grafana Cloud Free → Pro | ~$50 | Dashboards + alerting; avoid self-hosting Grafana |
| PagerDuty (existing) | ~$40 | Already configured |
| **Buffer** | ~$390 | Headroom for EU cluster (month 6) |

**Managed vs self-hosted:** The metrics query layer (Thanos Query) and Loki ingest are self-hosted because managed alternatives at this scale would consume the entire budget. AMP is the one managed service worth paying for — it absorbs the most operationally complex piece (compaction, downsampling) at low cost.

### What We Would NOT Do in the First 90 Days

- **Distributed tracing (Tempo/Jaeger):** High operational cost, requires application instrumentation across all teams. Prioritised for month 4+ once teams are on structured logging.
- **OpenTelemetry Collector as a replacement for Fluent Bit:** OTEL Collector is the right long-term choice but is more complex to configure for log routing; switching mid-flight while stabilising everything else adds risk.
- **Multi-region Thanos federation:** The EU cluster (month 6) can add a third Sidecar. Doing the federation architecture before the cluster exists is premature optimisation.
- **Fine-grained RBAC on Loki label streams:** Important for multi-tenancy (month 6 when 3 more teams onboard), but adds configuration complexity before we have tenants to isolate.
