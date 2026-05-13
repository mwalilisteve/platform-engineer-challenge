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
# Safe to run against production — no destructive operations are performed.
# =============================================================================

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
NAMESPACE="default"
DEPLOYMENT=""
LOG_LINES=50
EVENT_LINES=20
LOG_TIMEOUT=10   # seconds before kubectl logs gives up on a stuck pod

# ── Helpers ───────────────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
  exit 0
}

header() {
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  $*"
  echo "════════════════════════════════════════════════════════════════"
}

divider() {
  echo "────────────────────────────────────────────────────────────────"
}

# ── Flag parsing (Requirement 1) ──────────────────────────────────────────────
while getopts ":n:d:h" opt; do
  case $opt in
    n) NAMESPACE="$OPTARG" ;;
    d) DEPLOYMENT="$OPTARG" ;;
    h) usage ;;
    :) echo "ERROR: Flag -$OPTARG requires an argument." >&2; exit 1 ;;
    \?) echo "ERROR: Unknown flag -$OPTARG." >&2; exit 1 ;;
  esac
done

if [[ -z "$DEPLOYMENT" ]]; then
  echo "ERROR: -d <deployment> is required." >&2
  echo "Usage: $0 -n <namespace> -d <deployment>" >&2
  exit 1
fi

# ── Log file setup (Requirement 4) ───────────────────────────────────────────
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/tmp/triage-${DEPLOYMENT}-${TIMESTAMP}.log"

# Tee all output — stdout and stderr — to terminal and log file from one point.
exec > >(tee -a "$LOG_FILE") 2>&1

# ── Validate deployment exists (Requirement 2) ────────────────────────────────
if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &>/dev/null; then
  echo "ERROR: Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'." >&2
  echo "       Run: kubectl get deployments -n $NAMESPACE" >&2
  exit 1
fi

# ── Extract pod label selector dynamically ────────────────────────────────────
# Reads matchLabels directly from the deployment spec so the script works for
# any deployment without hardcoding label names.
SELECTOR=$(
  kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    -o jsonpath='{range .spec.selector.matchLabels}{@k}={@v},{end}' \
  | sed 's/,$//'
)

# ── Report header ─────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                  INCIDENT TRIAGE REPORT                         ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo "  Deployment : $DEPLOYMENT"
echo "  Namespace  : $NAMESPACE"
echo "  Generated  : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "  Log file   : $LOG_FILE"

# ── Section a: Deployment status (Requirement 3a) ────────────────────────────
header "a. DEPLOYMENT STATUS"

kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o wide

echo ""
echo "Rollout status:"
# timeout prevents hanging if the cluster control plane is degraded
timeout 10 kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" 2>&1 || true

echo ""
echo "Rollout conditions:"
kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{range .status.conditions[*]}  {.type}: {.status} — {.message}{"\n"}{end}'

# ── Section b: Pod states (Requirement 3b) ────────────────────────────────────
header "b. POD STATES"

POD_NAMES=$(
  kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
    -o jsonpath='{.items[*].metadata.name}'
)

if [[ -z "$POD_NAMES" ]]; then
  echo "  No pods found matching selector: $SELECTOR"
else
  kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" -o wide \
    --sort-by='.status.startTime'

  echo ""
  echo "Restart counts and container states:"
  for POD in $POD_NAMES; do
    divider
    echo "Pod: $POD"
    kubectl get pod "$POD" -n "$NAMESPACE" \
      -o jsonpath='  Ready:    {.status.conditions[?(@.type=="Ready")].status}{"\n"}  Restarts: {.status.containerStatuses[0].restartCount}{"\n"}  State:    {.status.containerStatuses[0].state}{"\n"}  Node:     {.spec.nodeName}{"\n"}'
    echo ""
  done
fi

# ── Section c: Events (Requirement 3c) ───────────────────────────────────────
header "c. EVENTS — last $EVENT_LINES sorted by time"

echo "Deployment-level events:"
kubectl get events -n "$NAMESPACE" \
  --field-selector "involvedObject.name=$DEPLOYMENT" \
  --sort-by='.lastTimestamp' 2>/dev/null \
  | tail -"$EVENT_LINES" || echo "  No events found for deployment."

for POD in $POD_NAMES; do
  divider
  echo "Pod: $POD"
  kubectl get events -n "$NAMESPACE" \
    --field-selector "involvedObject.name=$POD" \
    --sort-by='.lastTimestamp' 2>/dev/null \
    | tail -"$EVENT_LINES" || echo "  No events found."
done

# ── Section d: Logs (Requirement 3d) ─────────────────────────────────────────
header "d. LOGS — last $LOG_LINES lines per pod (with timestamps)"

for POD in $POD_NAMES; do
  divider
  echo "Pod: $POD — current container"
  # Timeout prevents the script hanging on a stuck pod during an incident.
  timeout "$LOG_TIMEOUT" kubectl logs "$POD" -n "$NAMESPACE" \
    --tail="$LOG_LINES" \
    --timestamps=true 2>/dev/null \
    || echo "  [Could not retrieve logs — timed out or container not ready]"

  echo ""
  echo "Pod: $POD — previous container (crash reason)"
  # --previous is critical: if the pod restarted, the error is in the OLD
  # container's logs, not the current healthy one.
  timeout "$LOG_TIMEOUT" kubectl logs "$POD" -n "$NAMESPACE" \
    --tail="$LOG_LINES" \
    --timestamps=true \
    --previous 2>/dev/null \
    || echo "  [No previous container — pod has not restarted, or logs have been garbage collected]"
done

# ── Section e: Resource usage (Requirement 3e) ────────────────────────────────
header "e. RESOURCE USAGE (kubectl top)"

if kubectl top pods -n "$NAMESPACE" -l "$SELECTOR" 2>/dev/null; then
  : # success
else
  echo "  [kubectl top unavailable — metrics-server may not be installed]"
fi

echo ""
echo "Node resource pressure:"
# Extract unique node names from the pods and check their conditions.
NODE_NAMES=$(
  kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
    -o jsonpath='{.items[*].spec.nodeName}' \
  | tr ' ' '\n' | sort -u
)

for NODE in $NODE_NAMES; do
  divider
  echo "Node: $NODE"
  kubectl get node "$NODE" \
    -o jsonpath='{range .status.conditions[*]}  {.type}: {.status}{"\n"}{end}' \
    2>/dev/null || echo "  [Could not retrieve node status]"
done

# ── Section f: HPA status (Requirement 3f) ────────────────────────────────────
header "f. HPA STATUS"

if kubectl get hpa "$DEPLOYMENT" -n "$NAMESPACE" &>/dev/null; then
  kubectl get hpa "$DEPLOYMENT" -n "$NAMESPACE"
  echo ""
  kubectl describe hpa "$DEPLOYMENT" -n "$NAMESPACE" \
    | grep -E "Reference|Metrics|Min replicas|Max replicas|Current|AbleToScale|ScalingActive|ScalingLimited" \
    || true
else
  echo "  No HPA found for '$DEPLOYMENT' in namespace '$NAMESPACE'."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
header "SUMMARY"

DESIRED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{.spec.replicas}')
READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{.status.readyReplicas}')
READY=${READY:-0}  # default to 0 if field is absent (all pods down)

echo "  Desired replicas : $DESIRED"
echo "  Ready replicas   : $READY"

if [[ "$READY" -lt "$DESIRED" ]]; then
  echo "  ⚠  WARNING: $((DESIRED - READY)) replica(s) not ready"
fi

echo ""
echo "  Pod restart counts:"
for POD in $POD_NAMES; do
  RESTARTS=$(kubectl get pod "$POD" -n "$NAMESPACE" \
    -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "?")
  echo "    $POD : $RESTARTS restart(s)"
done

header "END OF REPORT"
echo "  Full report saved to: $LOG_FILE"
echo ""