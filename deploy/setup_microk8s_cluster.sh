#!/usr/bin/env bash
# Install MicroK8s on all 4 VMs and form a cluster over the WireGuard mesh.
# l4-vm-281 (10.100.0.1) = control plane; others join as workers via wg IPs.
set -u
export PATH=/opt/google-cloud-sdk/bin:$PATH
ZONE=europe-west4-c

NODES=(
  "<account-281> ebim26ham-281 l4-vm-281 10.100.0.1"
  "<account-288> ebim26ham-288 l4-vm-288 10.100.0.2"
  "<account-289> ebim26ham-289 l4-vm-289 10.100.0.3"
  "<account-290> ebim26ham-290 l4-vm-290 10.100.0.4"
)
CP_ACCOUNT="<account-281>"; CP_PROJECT="ebim26ham-281"; CP_VM="l4-vm-281"; CP_WGIP="10.100.0.1"

gssh() { # 1=account 2=project 3=vm 4=cmd
  gcloud compute ssh "$3" --zone="$ZONE" --project="$2" --account="$1" \
    --command="$4" -- -o ConnectTimeout=30 -o StrictHostKeyChecking=no 2>/dev/null
}

echo "### PHASE 1: snap install microk8s on all nodes (parallel)"
for entry in "${NODES[@]}"; do
  read -r account project vm wgip <<< "$entry"
  (
    out=$(gssh "$account" "$project" "$vm" "
      sudo snap install microk8s --classic >/dev/null 2>&1 || sudo snap install microk8s --classic
      sudo usermod -aG microk8s \$USER
      # pin kubelet to the wireguard IP
      grep -q -- '--node-ip=$wgip' /var/snap/microk8s/current/args/kubelet || echo '--node-ip=$wgip' | sudo tee -a /var/snap/microk8s/current/args/kubelet >/dev/null
      $( [ "$vm" = "$CP_VM" ] && echo "grep -q -- '--advertise-address=$CP_WGIP' /var/snap/microk8s/current/args/kube-apiserver || echo '--advertise-address=$CP_WGIP' | sudo tee -a /var/snap/microk8s/current/args/kube-apiserver >/dev/null" )
      sudo snap restart microk8s >/dev/null 2>&1
      echo SNAP_OK")
    echo "$out" | grep -q SNAP_OK && echo "INSTALL_OK $vm" || { echo "INSTALL_FAIL $vm"; echo "$out" | tail -5; }
  ) &
done
wait

echo "### PHASE 2: wait for control plane ready"
gssh "$CP_ACCOUNT" "$CP_PROJECT" "$CP_VM" 'sudo microk8s status --wait-ready >/dev/null && echo CP_READY'

echo "### PHASE 3: join workers over wireguard"
for entry in "${NODES[@]}"; do
  read -r account project vm wgip <<< "$entry"
  [ "$vm" = "$CP_VM" ] && continue
  token=$(gssh "$CP_ACCOUNT" "$CP_PROJECT" "$CP_VM" 'sudo microk8s add-node --token-ttl 3600' | grep -m1 "25000/" | sed 's|.*25000/||' | awk '{print $1}')
  if [ -z "$token" ]; then echo "TOKEN_FAIL for $vm"; continue; fi
  for attempt in 1 2 3; do
    out=$(gssh "$account" "$project" "$vm" "sudo microk8s join $CP_WGIP:25000/$token --worker 2>&1 && echo JOIN_OK")
    echo "$out" | grep -q JOIN_OK && { echo "JOIN_OK $vm"; break; }
    echo "join attempt $attempt failed for $vm: $(echo "$out" | tail -2)"
    sleep 10
  done
done

echo "### PHASE 4: pin calico to wg0 and wait for all nodes Ready"
gssh "$CP_ACCOUNT" "$CP_PROJECT" "$CP_VM" \
  'sudo microk8s kubectl set env ds/calico-node -n kube-system IP_AUTODETECTION_METHOD=interface=wg0 >/dev/null && echo CALICO_PINNED'

for i in $(seq 1 20); do
  ready=$(gssh "$CP_ACCOUNT" "$CP_PROJECT" "$CP_VM" 'sudo microk8s kubectl get nodes --no-headers 2>/dev/null' | awk '$2=="Ready"' | wc -l)
  echo "ready nodes: $ready/4 (check $i)"
  [ "$ready" = "4" ] && break
  sleep 20
done

echo "### FINAL: cluster state"
gssh "$CP_ACCOUNT" "$CP_PROJECT" "$CP_VM" 'sudo microk8s kubectl get nodes -o wide'
echo "### DONE"
