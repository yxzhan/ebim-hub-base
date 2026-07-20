#!/usr/bin/env bash
# Install NVIDIA driver on the 6 new L4 VMs (282-287, spread across zones),
# reboot, verify with nvidia-smi. Same logic as install_gpu_drivers.sh but
# each VM carries its own zone (batch 2 did not all land in one zone).
set -u
export PATH=/opt/google-cloud-sdk/bin:$PATH

# account project vm zone
VMS=(
  "<account-282> ebim26ham-282 l4-vm-282 us-central1-c"
  "<account-283> ebim26ham-283 l4-vm-283 us-west4-c"
  "<account-284> ebim26ham-284 l4-vm-284 europe-west4-c"
  "<account-285> ebim26ham-285 l4-vm-285 us-east1-b"
  "<account-286> ebim26ham-286 l4-vm-286 us-east1-b"
  "<account-287> ebim26ham-287 l4-vm-287 us-west4-c"
)
LOGDIR="${LOGDIR:-/tmp/gpu-driver-logs-batch2}"
mkdir -p "$LOGDIR"

gssh() { # 1=account 2=project 3=vm 4=zone 5=remote command
  gcloud compute ssh "$3" --zone="$4" --project="$2" --account="$1" \
    --command="$5" -- -o ConnectTimeout=30 -o StrictHostKeyChecking=no 2>&1
}

echo "### PHASE 1: install driver (parallel, ~3-6 min each)"
for entry in "${VMS[@]}"; do
  read -r account project vm zone <<< "$entry"
  (
    out=$(gssh "$account" "$project" "$vm" "$zone" \
      'sudo DEBIAN_FRONTEND=noninteractive apt-get -qq update && sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq install nvidia-driver-570-server && echo INSTALL_OK')
    echo "$out" > "$LOGDIR/$vm.install.log"
    if echo "$out" | grep -q INSTALL_OK; then
      echo "INSTALL_OK $vm"
    else
      echo "INSTALL_FAIL $vm (see $LOGDIR/$vm.install.log)"
    fi
  ) &
done
wait

echo "### PHASE 2: reboot all"
for entry in "${VMS[@]}"; do
  read -r account project vm zone <<< "$entry"
  gssh "$account" "$project" "$vm" "$zone" 'sudo reboot' >/dev/null 2>&1
  echo "REBOOT_SENT $vm"
done

echo "### PHASE 3: wait and verify nvidia-smi"
sleep 60
for entry in "${VMS[@]}"; do
  read -r account project vm zone <<< "$entry"
  ok=""
  for attempt in 1 2 3 4 5 6; do
    out=$(gssh "$account" "$project" "$vm" "$zone" 'nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader')
    if echo "$out" | grep -qi "L4"; then
      echo "VERIFY_OK $vm : $out"
      ok=yes
      break
    fi
    sleep 20
  done
  [ -z "$ok" ] && echo "VERIFY_FAIL $vm : $out"
done
echo "### DONE"
