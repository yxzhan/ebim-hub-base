#!/usr/bin/env bash
# Run the Isaac Sim shader-cache warmup Job (isaac-warmup-gc.yaml) on the given
# cluster nodes, one Job per node, then wait for completion.
#
# Usage:
#   bash run_isaac_warmup.sh                 # all 10 nodes
#   bash run_isaac_warmup.sh 287             # just l4-vm-287 (trial)
#   bash run_isaac_warmup.sh 282 283 284     # a subset
#
# Applies through the control plane (281) via `microk8s kubectl`. Each Job holds
# nvidia.com/gpu:1 while warming, then completes and releases the GPU. If a node's
# GPU is busy with a user session, that node's Job stays Pending until it frees.
set -u
export PATH=/opt/google-cloud-sdk/bin:$PATH
HERE="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$HERE/isaac-warmup-gc.yaml"

CP_ACCOUNT="<account-281>"; CP_PROJECT="ebim26ham-281"; CP_VM="l4-vm-281"; CP_ZONE="europe-west4-c"

NODES=("$@")
[ ${#NODES[@]} -eq 0 ] && NODES=(281 282 283 284 285 286 287 288 289 290)

gssh() { gcloud compute ssh "$CP_VM" --zone="$CP_ZONE" --project="$CP_PROJECT" --account="$CP_ACCOUNT" \
    --command="$1" -- -o ConnectTimeout=30 -o StrictHostKeyChecking=no 2>/dev/null; }

# Build a combined multi-doc manifest for the requested nodes.
TMP=$(mktemp)
for n in "${NODES[@]}"; do
  host="l4-vm-${n}.c.ebim26ham-${n}.internal"
  sed -e "s/__SUFFIX__/${n}/g" -e "s/__NODE__/${host}/g" "$TEMPLATE" >> "$TMP"
  echo "---" >> "$TMP"
done

echo "### applying warmup Jobs for nodes: ${NODES[*]}"
# Recreate cleanly so re-runs work (delete any prior Jobs of these names first)
for n in "${NODES[@]}"; do
  gssh "sudo microk8s kubectl delete job isaac-warmup-${n} -n binder --ignore-not-found >/dev/null 2>&1"
done
gcloud compute ssh "$CP_VM" --zone="$CP_ZONE" --project="$CP_PROJECT" --account="$CP_ACCOUNT" \
  --command='sudo microk8s kubectl apply -f -' -- -o ConnectTimeout=30 -o StrictHostKeyChecking=no < "$TMP" 2>/dev/null
rm -f "$TMP"

echo "### waiting for warmup Jobs to finish (shader warmup can take several minutes each)"
n_total=${#NODES[@]}
for i in $(seq 1 60); do
  status=$(gssh "sudo microk8s kubectl get jobs -n binder -l app=isaac-warmup --no-headers 2>/dev/null")
  # Each Job has 1 completion; the "1/1" completions field appears only when done.
  # (kubectl >=1.34 added a STATUS column, so match the field by value, not position.)
  done_cnt=$(echo "$status" | grep -c '1/1')
  echo "--- check $i: $done_cnt/$n_total complete  ($(date +%H:%M:%S))"
  echo "$status" | sed 's/^/      /'
  [ "$done_cnt" = "$n_total" ] && { echo "ALL_WARMUP_COMPLETE"; break; }
  sleep 30
done

echo "### per-node result (pod phase + last log line)"
for n in "${NODES[@]}"; do
  pod=$(gssh "sudo microk8s kubectl get pods -n binder -l job-name=isaac-warmup-${n} --no-headers 2>/dev/null | awk '{print \$1}' | head -1")
  ph=$(gssh "sudo microk8s kubectl get pod $pod -n binder -o jsonpath='{.status.phase}' 2>/dev/null")
  last=$(gssh "sudo microk8s kubectl logs $pod -n binder --tail=2 2>/dev/null | tr '\n' ' '")
  echo "  l4-vm-${n}: phase=$ph  log: $last"
done
echo "### DONE"
