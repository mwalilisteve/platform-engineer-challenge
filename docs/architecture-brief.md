# Architecture Brief — Current Infrastructure

This document describes the current state of our hybrid platform. Use it as context for Task 5.

---

## Overview

We run a hybrid platform spanning two environments:

- **On-premise** — a self-managed Kubernetes cluster (kubeadm, v1.29) running in our Nairobi data centre. 12 worker nodes (bare metal), 3 control plane nodes. Hosts internal tooling, databases, and batch workloads.
- **AWS (af-south-1 / Cape Town)** — an Amazon EKS cluster (v1.30) hosting customer-facing APIs and web applications. Currently 2 managed node groups (spot + on-demand).

Both clusters are connected via AWS Direct Connect to our on-premise network.

---

## Current State

| Concern | Current Approach |
|---------|-----------------|
| Metrics | Node Exporter on bare metal, no scraping on EKS |
| Logging | Fluentd on on-premise (ships to an old ELK stack, no TLS), nothing on EKS |
| Alerting | Manual Grafana dashboards, PagerDuty configured but untriggered |
| Tracing | Not implemented |
| Uptime | Manually checked |

The on-call engineer currently SSHs to nodes and runs `journalctl` when something goes wrong.

---

## Constraints

- **Budget:** We can spend approximately USD 800/month on managed observability tooling in AWS.
- **Team size:** 2 platform engineers (including the hire for this role).
- **Data residency:** Customer PII logs must not leave AWS af-south-1.
- **Retention:** Metrics: 15 days hot, 90 days cold. Logs: 30 days queryable, 1 year archived.
- **Compliance:** We are pursuing ISO 27001 — audit log access and change tracking are required.

---

## Future State (6-month horizon)

- Add a third cluster (EKS, eu-west-1) for European customers.
- Introduce ArgoCD for GitOps-based deployments across all clusters.
- Onboard 3 more development teams.
- Implement multi-tenancy on the on-premise cluster using namespaces + NetworkPolicy.
