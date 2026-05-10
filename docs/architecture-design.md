# Observability Design — Hybrid Cluster Stack

## 5a. Metrics

### Tooling Choice: Prometheus + Grafana + Node Exporter + kube-state-metrics + cAdvisor

Each Kubernetes cluster runs its own Prometheus instance deployed using the kube-prometheus-stack Helm chart.

The design intentionally avoids a single centralized Prometheus scraping multiple clusters because that becomes both a scalability bottleneck and a single point of failure.

Instead, every cluster is independently observable and exports metrics to a centralized Grafana layer.

### On-Premise Cluster (Nairobi DC)

The on-premise kubeadm cluster runs:

- Prometheus for metrics collection
- Node Exporter on all bare-metal nodes for host-level metrics
- cAdvisor for container runtime metrics
- kube-state-metrics for Kubernetes object state metrics

Prometheus scrapes:

- Node CPU, memory, disk, filesystem, and network usage
- Pod/container resource consumption
- Kubernetes deployment and replica state
- API server and kubelet metrics
- Application `/metrics` endpoints

Retention strategy:

- 15 days hot storage on local PVC-backed Prometheus TSDB
- 90 days cold retention via remote write to long-term object storage

Given the team size (2 platform engineers), operational simplicity matters more than building a fully distributed Thanos topology on day one.

### AWS EKS Cluster (af-south-1)

The EKS cluster runs the same monitoring stack for operational consistency:

- Prometheus
- Node Exporter
- cAdvisor
- kube-state-metrics

This standardization ensures dashboards and alerts remain reusable across environments.

Prometheus on EKS scrapes:

- Managed node groups (spot + on-demand)
- Kubernetes workloads
- Customer-facing APIs
- Ingress controller metrics
- Cluster autoscaler metrics
- Future ArgoCD metrics

### Unified Visualization Layer

A centralized Grafana instance provides a single-pane operational view across both clusters.

Grafana connects to:

- On-prem Prometheus
- EKS Prometheus
- Loki log backends

This allows engineers to:

- Compare workload health between clusters
- Correlate infrastructure and application incidents
- Build shared dashboards for future development teams
- Create audit-visible operational dashboards for ISO 27001 evidence

### Why This Design

This architecture deliberately favors:

- Low operational overhead
- Fast onboarding
- Predictable troubleshooting
- Simple scaling to the future EU cluster

With only two platform engineers, introducing Thanos federation, Cortex, or Mimir immediately would add unnecessary operational complexity before the organization has observability maturity.

---

## 5b. Logging

### Stack: Promtail → Loki → Grafana

The logging layer is built around:

- Promtail
- Grafana Loki
- Grafana

This replaces the existing legacy Fluentd + ELK deployment.

### Why Loki Instead of ELK

The current ELK stack creates operational overhead that is difficult to justify for a small platform team:

- Elasticsearch storage tuning
- JVM memory management
- Index lifecycle management
- High storage consumption

Loki is better aligned with the current requirements because it:

- Stores compressed logs cheaply in object storage
- Uses labels instead of heavy indexing
- Integrates natively with Grafana
- Requires significantly fewer infrastructure resources

This keeps operational costs within the USD 800/month budget.

### Promtail Deployment

Promtail runs as a DaemonSet in both clusters and tails:

- Container stdout/stderr logs
- Kubernetes events
- Node-level system logs
- journald logs where required

Promtail attaches Kubernetes metadata automatically:

- namespace
- pod
- container
- node
- cluster
- application labels

This removes the need for developers to manually enrich logs.

### Reliability During Connectivity Issues

Because the clusters are connected over AWS Direct Connect, temporary link degradation is possible.

Promtail uses:

- local position tracking
- retry queues
- buffered delivery

This ensures logs are not immediately lost during transient failures between on-prem and AWS.

### Data Residency Compliance

Customer PII logs must remain within AWS af-south-1.

To enforce this:

- Loki storage for customer-facing workloads resides entirely in af-south-1
- Promtail routing rules separate operational logs from customer application logs
- Sensitive workloads are labeled and routed accordingly

This satisfies the stated data residency constraint.

### Retention Strategy

#### Queryable Logs

- 30 days retained in Loki object storage

#### Archived Logs

- S3 lifecycle rules transition logs to Glacier after 30 days
- 1-year archival retention satisfies compliance and audit requirements

### Security Improvements

Compared to the current state (“Fluentd without TLS”), the new design introduces:

- TLS encryption between Promtail and Loki
- Centralized access control through Grafana
- Audit-visible log access
- Immutable object-storage-backed retention

These controls directly support ISO 27001 audit requirements.

---

## 5c. Alerting

### Alerting Stack

The alerting solution is built using:

- Prometheus
- Alertmanager
- Grafana Alerting
- Email notifications
- PagerDuty

Prometheus is responsible for evaluating alert rules, while Alertmanager handles alert routing, grouping, deduplication, and escalation management. Grafana provides centralized alert visualization, operational dashboards, and alert history.

---

### Alerting Architecture and Setup

The monitoring and alerting stack is deployed consistently across both the on-premise Kubernetes cluster and the Amazon EKS cluster using the `kube-prometheus-stack` Helm chart.

Key setup components include:

- Prometheus deployed per cluster for local metric scraping and alert rule evaluation
- Alertmanager deployed alongside Prometheus for centralized notification management
- Grafana configured with both Prometheus instances as data sources for unified visibility
- SMTP integration configured within Alertmanager for email notifications
- PagerDuty integrated using the PagerDuty Events API for critical incident escalation

This architecture ensures each cluster remains operationally independent while still providing centralized observability and incident management.

---

### Alert Flow

```text
Prometheus
    ↓
Alertmanager
    ↓
 ┌────────────────┬
 ↓                ↓
Email          PagerDuty
Notifications  Incident Escalation