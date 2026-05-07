#!/usr/bin/env bash
# =============================================================================
# incident.sh — Kubernetes deployment incident triage helper
# =============================================================================
#
# ## Usage
#   ./scripts/incident.sh -n <namespace> -d <deployment>
#
#   Flags:
#     -n  Kubernetes namespace (default: default)
#     -d  Deployment name (required)
#     -h  Show this help
#
#   Example:
#     ./scripts/incident.sh -n payments -d api-service
#
#   Output:
#     - Triage report printed to stdout
#     - Report saved to /tmp/triage-<deployment>-<timestamp>.log
#
# =============================================================================

set -euo pipefail

# TODO (Task 4): Implement this script
#
# Requirements:
#   1. Parse -n and -d flags with getopts; default namespace to "default"
#   2. Validate that the deployment exists; exit 1 with a clear error if not
#   3. Output the following sections, separated by clear headers:
#      a. Deployment status (desired vs ready replicas, rollout conditions)
#      b. Pod states (name, status, restarts, node)
#      c. Last 20 events for the deployment and its pods, sorted by time
#      d. Last 50 log lines from each pod's primary container (with timestamps)
#      e. Resource usage per pod (kubectl top pods)
#      f. HPA status, if an HPA exists for this deployment
#   4. Tee output to /tmp/triage-<deployment>-<timestamp>.log
#   5. Do NOT perform any destructive kubectl operations
#   6. The script must be safe to run against a production cluster

echo "TODO: implement incident.sh"
exit 1
