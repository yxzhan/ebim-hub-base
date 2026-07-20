#!/usr/bin/env bash
# Add the 6 new VMs to the EXISTING MicroK8s cluster as workers, over WireGuard.
# Control plane stays l4-vm-281 (10.100.0.1). New workers pin kubelet to their wg IP.
# The CP already has calico pinned to wg0 and --advertise-address set, so new
# nodes just join.
#   282=.5  283=.6  284=.7  285=.8  286=.9  287=.10
set -u
export PATH=/opt/google-cloud-sdk/bin:$PATH

CP_ACCOUNT="<account-281>"; CP_PROJECT="ebim26ham-281"; CP_VM="l4-vm-281"
CP_ZONE="europe-west4-c"; CP_WGIP="10.100.0.1"

# account project vm zone wgip  (new workers only)
NEW=(
  "<account-282> ebim26ham-282 l4-vm-282 us-central1-c 10.100.0.5"
  "<account-283> ebim26ham-283 l4-vm-283 us-west4-c 10.100.0.6"
  "<account-284> ebim26ham-284 l4-vm-284 europe-west4-c 10.100.0.7"
  "<account-285> ebim26ham-285 l4-vm-285 us-east1-b 10.100.0.8"
  "<account-286> ebim26ham-286 l4-vm-286 us-east1-b 10.100.0.9"
  "<account-287> ebim26ham-287 l4-vm-287 us-west4-c 10.100.0.10"
)

gssh() { # 1=account 2=project 3=vm 4=zone 5=cmd
  gcloud compute ssh "$3" --zone="$4" --project="$2" --account="$1" \
    --command="$5" -- -o ConnectTimeout=30 -o StrictHostKeyChecking=no 2>/dev/null
}

echo "### PHASE 1: snap install microk8s on 6 new nodes, pin kubelet to wg IP (parallel)"
for entry in "${NEW[@]}"; do
  read -r account project vm zone wgip <<< "$entry"
  (
    out=$(gssh "$account" "$project" "$vm" "$zone" "
      sudo snap install microk8s --classic >/dev/null 2>&1 || sudo snap install microk8s --classic
      sudo usermod -aG microk8s \$USER
      grep -q -- '--node-ip=$wgip' /var/snap/microk8s/current/args/kubelet || echo '--node-ip=$wgip' | sudo tee -a /var/snap/microk8s/current/args/kubelet >/dev/null
      sudo snap restart microk8s >/dev/null 2>&1
      echo SNAP_OK")
    echo "$out" | grep -q SNAP_OK && echo "INSTALL_OK $vm" || { echo "INSTALL_FAIL $vm"; echo "$out" | tail -5; }
  ) &
done
wait

echo "### PHASE 2: wait for control plane ready"
gssh "$CP_ACCOUNT" "$CP_PROJECT" "$CP_VM" "$CP_ZONE" 'sudo microk8s status --wait-ready >/dev/null && echo CP_READY'

echo "### PHASE 3: join each new worker over wireguard (fresh token per node)"
for entry in "${NEW[@]}"; do
  read -r account project vm zone wgip <<< "$entry"
  token=$(gssh "$CP_ACCOUNT" "$CP_PROJECT" "$CP_VM" "$CP_ZONE" 'sudo microk8s add-node --token-ttl 3600' | grep -m1 "25000/" | sed 's|.*25000/||' | awk '{print $1}')
  if [ -z "$token" ]; then echo "TOKEN_FAIL for $vm"; continue; fi
  joined=""
  for attempt in 1 2 3; do
    out=$(gssh "$account" "$project" "$vm" "$zone" "sudo microk8s join $CP_WGIP:25000/$token --worker 2>&1 && echo JOIN_OK")
    echo "$out" | grep -q JOIN_OK && { echo "JOIN_OK $vm"; joined=yes; break; }
    echo "join attempt $attempt failed for $vm: $(echo "$out" | tail -2)"
    sleep 12
  done
  [ -z "$joined" ] && echo "JOIN_FAIL $vm"
done

echo "### PHASE 4: wait for all 10 nodes Ready"
for i in $(seq 1 24); do
  ready=$(gssh "$CP_ACCOUNT" "$CP_PROJECT" "$CP_VM" "$CP_ZONE" 'sudo microk8s kubectl get nodes --no-headers 2>/dev/null' | awk '$2=="Ready"' | wc -l)
  echo "ready nodes: $ready/10 (check $i)"
  [ "$ready" = "10" ] && break
  sleep 20
done

echo "### FINAL: cluster state"
gssh "$CP_ACCOUNT" "$CP_PROJECT" "$CP_VM" "$CP_ZONE" 'sudo microk8s kubectl get nodes -o wide'
echo "### DONE"
