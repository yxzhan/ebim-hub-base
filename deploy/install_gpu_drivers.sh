#!/usr/bin/env bash
# Install NVIDIA driver on all 4 L4 VMs (parallel), reboot, verify with nvidia-smi.
set -u
export PATH=/opt/google-cloud-sdk/bin:$PATH

ZONE=europe-west4-c
VMS=(
  "<account-281> ebim26ham-281 l4-vm-281"
  "<account-288> ebim26ham-288 l4-vm-288"
  "<account-289> ebim26ham-289 l4-vm-289"
  "<account-290> ebim26ham-290 l4-vm-290"
)
LOGDIR="${LOGDIR:-/tmp/gpu-driver-logs}"
mkdir -p "$LOGDIR"

gssh() { # 1=account 2=project 3=vm 4=remote command
  gcloud compute ssh "$3" --zone="$ZONE" --project="$2" --account="$1" \
    --command="$4" -- -o ConnectTimeout=30 -o StrictHostKeyChecking=no 2>&1
}

echo "### PHASE 1: install driver (parallel, ~3-6 min each)"
for entry in "${VMS[@]}"; do
  read -r account project vm <<< "$entry"
  (
    out=$(gssh "$account" "$project" "$vm" \
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
  read -r account project vm <<< "$entry"
  gssh "$account" "$project" "$vm" 'sudo reboot' >/dev/null 2>&1
  echo "REBOOT_SENT $vm"
done

echo "### PHASE 3: wait and verify nvidia-smi"
sleep 60
for entry in "${VMS[@]}"; do
  read -r account project vm <<< "$entry"
  ok=""
  for attempt in 1 2 3 4 5 6; do
    out=$(gssh "$account" "$project" "$vm" 'nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader')
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
