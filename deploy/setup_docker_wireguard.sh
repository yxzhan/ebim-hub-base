#!/usr/bin/env bash
# Install docker + wireguard on all 4 VMs and build a full-mesh WireGuard network:
#   l4-vm-281=10.100.0.1  l4-vm-288=10.100.0.2  l4-vm-289=10.100.0.3  l4-vm-290=10.100.0.4
set -u
export PATH=/opt/google-cloud-sdk/bin:$PATH
ZONE=europe-west4-c

# account project vm public_ip wg_ip
NODES=(
  "<account-281> ebim26ham-281 l4-vm-281 <static-ip-281> 10.100.0.1"
  "<account-288> ebim26ham-288 l4-vm-288 <static-ip-288> 10.100.0.2"
  "<account-289> ebim26ham-289 l4-vm-289 <static-ip-289> 10.100.0.3"
  "<account-290> ebim26ham-290 l4-vm-290 <static-ip-290> 10.100.0.4"
)

gssh() { # 1=account 2=project 3=vm 4=cmd
  gcloud compute ssh "$3" --zone="$ZONE" --project="$2" --account="$1" \
    --command="$4" -- -o ConnectTimeout=30 -o StrictHostKeyChecking=no 2>/dev/null
}

echo "### PHASE 1: install docker + wireguard, generate wg keys (parallel)"
TMP=$(mktemp -d)
for entry in "${NODES[@]}"; do
  read -r account project vm pubip wgip <<< "$entry"
  (
    out=$(gssh "$account" "$project" "$vm" '
      sudo DEBIAN_FRONTEND=noninteractive apt-get -qq update &&
      sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq install docker.io wireguard >/dev/null &&
      sudo usermod -aG docker $USER &&
      sudo systemctl enable --now docker >/dev/null 2>&1
      if sudo test -f /etc/wireguard/private.key; then :; else
        wg genkey | sudo tee /etc/wireguard/private.key >/dev/null
        sudo chmod 600 /etc/wireguard/private.key
      fi
      echo "PUBKEY $(sudo cat /etc/wireguard/private.key | wg pubkey)"
      echo "DOCKER $(docker --version 2>/dev/null || sudo docker --version)"')
    echo "$out" > "$TMP/$vm.out"
    if grep -q PUBKEY "$TMP/$vm.out"; then echo "PHASE1_OK $vm"; else echo "PHASE1_FAIL $vm"; cat "$TMP/$vm.out"; fi
  ) &
done
wait

declare -A PUBKEY
for entry in "${NODES[@]}"; do
  read -r account project vm pubip wgip <<< "$entry"
  PUBKEY[$vm]=$(grep "^PUBKEY " "$TMP/$vm.out" | awk '{print $2}')
  if [ -z "${PUBKEY[$vm]}" ]; then echo "FATAL: no pubkey for $vm"; exit 1; fi
  echo "$vm pubkey: ${PUBKEY[$vm]}"
done

echo "### PHASE 2: write wg0.conf on each node and start wg-quick"
for entry in "${NODES[@]}"; do
  read -r account project vm pubip wgip <<< "$entry"
  peers=""
  for other in "${NODES[@]}"; do
    read -r oaccount oproject ovm opubip owgip <<< "$other"
    [ "$ovm" = "$vm" ] && continue
    peers+="
[Peer]
PublicKey = ${PUBKEY[$ovm]}
Endpoint = $opubip:51820
AllowedIPs = $owgip/32
PersistentKeepalive = 25
"
  done
  gssh "$account" "$project" "$vm" "sudo bash -c 'cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = $wgip/24
PrivateKey = \$(cat /etc/wireguard/private.key)
ListenPort = 51820
MTU = 1380
$peers
EOF
chmod 600 /etc/wireguard/wg0.conf
systemctl enable wg-quick@wg0 >/dev/null 2>&1
systemctl restart wg-quick@wg0' && echo WG_STARTED $vm"
done

echo "### PHASE 3: verify full mesh from every node"
sleep 5
for entry in "${NODES[@]}"; do
  read -r account project vm pubip wgip <<< "$entry"
  out=$(gssh "$account" "$project" "$vm" '
    ok=1
    for ip in 10.100.0.1 10.100.0.2 10.100.0.3 10.100.0.4; do
      ping -c1 -W3 $ip >/dev/null 2>&1 || { echo "PING_FAIL $ip"; ok=0; }
    done
    [ $ok = 1 ] && echo MESH_OK')
  if echo "$out" | grep -q MESH_OK; then echo "MESH_OK from $vm"; else echo "MESH_FAIL from $vm: $out"; fi
done
echo "### DONE"
