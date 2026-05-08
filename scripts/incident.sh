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
#     - Structured triage report printed to stdout
#     - Report saved to /tmp/triage-<deployment>-<timestamp>.log
#
# Safe to run against production — no destructive operations are performed.
# =============================================================================

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
NAMESPACE="default"
DEPLOYMENT=""

# ── Argument parsing ─────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \?//'
  exit 0
}

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
  exit 1
fi

# ── Log file setup ───────────────────────────────────────────────────────────
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/tmp/triage-${DEPLOYMENT}-${TIMESTAMP}.log"

# Tee all output to both stdout and the log file.
exec > >(tee -a "$LOG_FILE") 2>&1

# ── Helpers ───────────────────────────────────────────────────────────────────
divider() {
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  $*"
  echo "════════════════════════════════════════════════════════════════"
}

thin_divider() {
  echo "────────────────────────────────────────────────────────────────"
}

# ── Guard: verify deployment exists ─────────────────────────────────────────
if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &>/dev/null; then
  echo "ERROR: Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'." >&2
  echo "       Run: kubectl get deployments -n $NAMESPACE" >&2
  exit 1
fi

# ── Report header ─────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║           INCIDENT TRIAGE REPORT                                ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo "  Deployment : $DEPLOYMENT"
echo "  Namespace  : $NAMESPACE"
echo "  Generated  : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "  Log file   : $LOG_FILE"

# ── Section 1: Deployment status ─────────────────────────────────────────────
divider "1. DEPLOYMENT STATUS"
kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o wide

echo ""
echo "Rollout conditions:"
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=5s 2>&1 || true

echo ""
echo "Detailed status:"
kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{range .status.conditions[*]}Condition: {.type}  Status: {.status}  Reason: {.reason}  Message: {.message}{"\n"}{end}'

# ── Section 2: Pod states ─────────────────────────────────────────────────────
divider "2. POD STATES"

# Identify pods belonging to this deployment via its label selector.
SELECTOR=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{.spec.selector.matchLabels}' \
  | tr -d '{}' | sed 's/"//g; s/:/=/g; s/,/ /g' \
  | awk '{for(i=1;i<=NF;i++) printf $i (i<NF?",":""); print ""}')

kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
  -o custom-columns=\
"NAME:.metadata.name,\
STATUS:.status.phase,\
READY:.status.containerStatuses[0].ready,\
RESTARTS:.status.containerStatuses[0].restartCount,\
NODE:.spec.nodeName,\
AGE:.metadata.creationTimestamp"

# ── Section 3: Recent events ──────────────────────────────────────────────────
divider "3. RECENT EVENTS (last 20, sorted by time)"

# Gather events for the deployment and its pods.
kubectl get events -n "$NAMESPACE" \
  --sort-by='.lastTimestamp' \
  --field-selector "involvedObject.name=$DEPLOYMENT" 2>/dev/null | tail -20 || true

echo ""
echo "Pod-level events:"
POD_NAMES=$(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" \
  -o jsonpath='{.items[*].metadata.name}')

for POD in $POD_NAMES; do
  thin_divider
  echo "Pod: $POD"
  kubectl get events -n "$NAMESPACE" \
    --sort-by='.lastTimestamp' \
    --field-selector "involvedObject.name=$POD" 2>/dev/null | tail -20 || true
done

# ── Section 4: Recent logs ────────────────────────────────────────────────────
divider "4. RECENT LOGS (last 50 lines per pod, with timestamps)"

for POD in $POD_NAMES; do
  thin_divider
  echo "Pod: $POD"
  kubectl logs "$POD" -n "$NAMESPACE" \
    --tail=50 \
    --timestamps=true \
    --container="${DEPLOYMENT}" 2>/dev/null \
  || kubectl logs "$POD" -n "$NAMESPACE" \
    --tail=50 \
    --timestamps=true 2>/dev/null \
  || echo "  [Could not retrieve logs for $POD]"
done

# ── Section 5: Resource usage ─────────────────────────────────────────────────
divider "5. RESOURCE USAGE (kubectl top)"

if kubectl top pods -n "$NAMESPACE" -l "$SELECTOR" 2>/dev/null; then
  : # success
else
  echo "  [kubectl top unavailable — metrics-server may not be installed]"
fi

# ── Section 6: HPA status ─────────────────────────────────────────────────────
divider "6. HPA STATUS"

if kubectl get hpa -n "$NAMESPACE" "$DEPLOYMENT" &>/dev/null; then
  kubectl get hpa "$DEPLOYMENT" -n "$NAMESPACE"
  echo ""
  kubectl describe hpa "$DEPLOYMENT" -n "$NAMESPACE" \
    | grep -E "Reference|Metrics|Min|Max|Deployment pods|AbleToScale|ScalingActive|ScalingLimited" || true
else
  echo "  No HPA found for deployment '$DEPLOYMENT' in namespace '$NAMESPACE'."
fi

# ── Footer ────────────────────────────────────────────────────────────────────
divider "END OF REPORT"
echo "  Full report saved to: $LOG_FILE"
echo ""
