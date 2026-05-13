# Observability Design — Hybrid Cluster Stack

## 5a. Metrics

### Tooling: Prometheus + Grafana + Node Exporter + kube-state-metrics + cAdvisor

Each Kubernetes cluster runs its own Prometheus instance deployed via the `kube-prometheus-stack` Helm chart. The design intentionally avoids a single centralized Prometheus scraping multiple clusters — that pattern creates a scalability bottleneck and a single point of failure.

### Scraping — On-Premise Cluster (Nairobi DC)

The on-premise kubeadm cluster runs Prometheus, Node Exporter on all bare-metal nodes, cAdvisor for container runtime metrics, and kube-state-metrics for Kubernetes object state.

Prometheus scrapes:
- Node CPU, memory, disk, filesystem, and network usage
- Pod and container resource consumption
- Kubernetes deployment and replica state
- API server and kubelet metrics
- Application `/metrics` endpoints

### Scraping — AWS EKS Cluster (af-south-1)

The EKS cluster runs the same stack for operational consistency: Prometheus, Node Exporter, cAdvisor, and kube-state-metrics. This standardization keeps dashboards and alert rules reusable across environments.

EKS-specific scrape targets include managed node groups (spot and on-demand), ingress controller metrics, cluster autoscaler metrics, and future ArgoCD metrics.

### Federation and Aggregation

Each Prometheus instance uses `remote_write` to push metrics to a centralized **Grafana Mimir** instance hosted in af-south-1. Mimir provides a horizontally scalable, multi-tenant query layer across both clusters without requiring Thanos sidecar complexity.

Grafana connects to Mimir as a single datasource, providing a unified query and dashboard layer across both environments. Engineers can compare on-prem and EKS workloads in a single panel using cluster-label selectors.

```
On-Prem Prometheus ──remote_write──▶ ┐
                                      Mimir (af-south-1) ◀── Grafana
EKS Prometheus     ──remote_write──▶ ┘
```

### Retention and Cost

- **Hot retention**: 15 days on local Prometheus TSDB (PVC-backed) per cluster
- **Long-term retention**: Mimir writes to S3 (af-south-1) with a 90-day retention policy
- **Cost control**: Mimir's block compaction and downsampling reduce S3 storage costs over time. Recording rules pre-aggregate high-cardinality metrics so raw series are not retained longer than needed.

With a USD 800/month budget, self-hosted Mimir on a small EKS node group is significantly cheaper than Amazon Managed Prometheus at equivalent retention volumes.

---

## 5b. Logging

### Stack: Promtail → Loki → Grafana

The logging layer replaces the existing Fluentd + ELK deployment with Promtail, Grafana Loki, and Grafana.

**Why Loki over ELK**: Elasticsearch requires JVM memory tuning, index lifecycle management, and high storage. Loki stores compressed logs in object storage using label-based indexing — operationally simpler and significantly cheaper at this scale.

### Promtail Deployment

Promtail runs as a DaemonSet in both clusters and tails container stdout/stderr, Kubernetes events, node system logs, and journald where applicable. It automatically attaches Kubernetes metadata: `namespace`, `pod`, `container`, `node`, `cluster`, and application labels — removing the need for developers to manually enrich logs.

### Structured Logging and Trace Correlation

Applications are expected to emit logs as structured JSON. Promtail is configured with a pipeline stage to parse the `trace_id` field from JSON log lines and promote it to a Loki label:

```yaml
- json:
    expressions:
      trace_id: trace_id
- labels:
    trace_id:
```

This enables log-to-trace correlation in Grafana. When an engineer views a trace in Tempo, they can jump directly to the logs for that specific request using the shared `trace_id`. OpenTelemetry SDK propagation handles injecting `trace_id` into application log output.

### Reliable Delivery from On-Premise

Because clusters connect over AWS Direct Connect, transient link degradation is possible. Promtail uses local position tracking, retry queues, and buffered delivery to ensure logs are not lost during connectivity interruptions. On recovery, Promtail resumes from the last committed position.

### Retention

- **Queryable**: 30 days in Loki object storage (S3, af-south-1)
- **Archived**: S3 lifecycle rules transition to Glacier after 30 days; 1-year archival retention for compliance

### Data Residency

Customer PII logs are routed exclusively to Loki storage in af-south-1 via Promtail label-based routing rules. Sensitive workloads are labeled at the pod level and routed accordingly, satisfying the stated data residency constraint.

---

## 5c. Alerting

### Stack: Prometheus + Alertmanager + Grafana Alerting + PagerDuty + Email

### SLO Definition — API Service (Target: 99.9% over 30 days)

99.9% availability over 30 days allows a maximum **43.8 minutes of downtime** per month.

**Error rate SLO**:
```
sum(rate(http_requests_total{status=~"5.."}[5m]))
/
sum(rate(http_requests_total[5m])) < 0.001
```

**Latency SLO** (p99 < 500ms):
```
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) < 0.5
```

**Burn rate alerts** replace naive threshold alerts to reduce fatigue:

| Window | Burn Rate | Severity | Action |
|--------|-----------|----------|--------|
| 1h     | 14×       | Critical | Page on-call immediately |
| 6h     | 6×        | Warning  | Slack notification |
| 3d     | 1×        | Info     | Ticket for review |

A 14× burn rate over 1 hour means the error budget will be exhausted in ~2 hours — warranting immediate escalation. A 1× burn rate over 3 days is slow degradation worth tracking but not waking anyone up for.

### Alert Fatigue Strategy

Rules created and why:

- **CrashLoopBackOff** (>2 restarts in 10m) — actionable, indicates broken deployment
- **PodNotReady** (>5m) — indicates scheduling or startup failure
- **HighErrorRate** (burn-rate based, not raw %) — avoids noisy transient spikes
- **NodeMemoryPressure** — precursor to OOMKill events
- **PVCNearFull** (>85%) — gives time to act before data loss

Rules explicitly **not created**:
- CPU usage thresholds (too noisy, rarely actionable alone)
- Pod restarts < 2 (transient, not worth paging)
- Liveness probe failures without sustained impact

All alerts require a `for` duration of at least 2–5 minutes to eliminate single-scrape false positives.

### On-Call Escalation

```
Prometheus fires alert
        │
        ▼
Alertmanager routes by severity
        │
   ┌────┴─────┐
   ▼          ▼
 Email     PagerDuty
(warning)  (critical)
               │
         ┌─────┴──────┐
         ▼            ▼
    On-call eng   Escalate to
    (0–15 min)    senior / lead
                  (15–30 min)
```

PagerDuty escalation policy: if the primary on-call does not acknowledge within 15 minutes, the incident auto-escalates to the secondary. After 30 minutes unacknowledged, it pages the engineering lead.

---

## 5d. Trade-offs

### Managed Services vs Self-Hosted

Given a USD 800/month infrastructure budget and a two-person platform team, self-hosted wins for the core observability stack. The operational cost of learning Loki and Mimir is a one-time investment; the ongoing cost of Amazon Managed Prometheus and CloudWatch at equivalent retention is prohibitive.

Exceptions where managed services are worth the cost:
- **S3 + Glacier** for log and metric archival — undifferentiated storage, not worth self-managing
- **PagerDuty** for on-call — reliability of incident delivery is not a place to cut costs

### What We Would Not Do in the First 90 Days

| What | Why not yet |
|------|-------------|
| Thanos federation | Mimir remote_write covers the multi-cluster query requirement at lower complexity |
| Distributed tracing (Tempo + OTel) full rollout | High instrumentation effort; lay the groundwork (trace_id in logs) first |
| Custom Grafana plugin development | Premature; use off-the-shelf dashboards from kube-prometheus-stack |
| Multi-region Loki replication | Single af-south-1 region satisfies current data residency; replication adds cost without current need |
| SLO dashboards for every service | Start with the one customer-facing API; expand once the pattern is proven |

The first 90 days should produce a working, alerting, queryable observability stack — not a perfectly architected one.