#!/usr/bin/env bash
# Expand the existing 4-node WireGuard mesh to 10 nodes WITHOUT disrupting the
# live cluster.
#   existing: 281=.1  288=.2  289=.3  290=.4   (already up, must stay up)
#   new:      282=.5  283=.6  284=.7  285=.8  286=.9  287=.10
# Strategy:
#   - new nodes: apt install docker+wireguard, genkey, write full 9-peer wg0.conf, wg-quick up
#   - existing nodes: rewrite the 9-peer wg0.conf then `wg syncconf` (live-apply, no
#     interface restart -> tunnels/cluster traffic never drop)
set -u
export PATH=/opt/google-cloud-sdk/bin:$PATH

# account project vm zone pubip wgip role
NODES=(
  "<account-281> ebim26ham-281 l4-vm-281 europe-west4-c <static-ip-281> 10.100.0.1 existing"
  "<account-288> ebim26ham-288 l4-vm-288 europe-west4-c <static-ip-288> 10.100.0.2 existing"
  "<account-289> ebim26ham-289 l4-vm-289 europe-west4-c <static-ip-289> 10.100.0.3 existing"
  "<account-290> ebim26ham-290 l4-vm-290 europe-west4-c <static-ip-290> 10.100.0.4 existing"
  "<account-282> ebim26ham-282 l4-vm-282 us-central1-c <static-ip-282> 10.100.0.5 new"
  "<account-283> ebim26ham-283 l4-vm-283 us-west4-c <static-ip-283> 10.100.0.6 new"
  "<account-284> ebim26ham-284 l4-vm-284 europe-west4-c <static-ip-284> 10.100.0.7 new"
  "<account-285> ebim26ham-285 l4-vm-285 us-east1-b <static-ip-285> 10.100.0.8 new"
  "<account-286> ebim26ham-286 l4-vm-286 us-east1-b <static-ip-286> 10.100.0.9 new"
  "<account-287> ebim26ham-287 l4-vm-287 us-west4-c <static-ip-287> 10.100.0.10 new"
)

# Preseeded public keys for the existing 4 (fetched from their private.key)
declare -A PUBKEY=(
  [l4-vm-281]="<wg-pubkey-281>"
  [l4-vm-288]="<wg-pubkey-288>"
  [l4-vm-289]="<wg-pubkey-289>"
  [l4-vm-290]="<wg-pubkey-290>"
)

ALL_WGIPS="10.100.0.1 10.100.0.2 10.100.0.3 10.100.0.4 10.100.0.5 10.100.0.6 10.100.0.7 10.100.0.8 10.100.0.9 10.100.0.10"

gssh() { # 1=account 2=project 3=vm 4=zone 5=cmd
  gcloud compute ssh "$3" --zone="$4" --project="$2" --account="$1" \
    --command="$5" -- -o ConnectTimeout=30 -o StrictHostKeyChecking=no 2>/dev/null
}

echo "### PHASE 1: install docker+wireguard on NEW nodes, generate keys (parallel)"
TMP=$(mktemp -d)
for entry in "${NODES[@]}"; do
  read -r account project vm zone pubip wgip role <<< "$entry"
  [ "$role" = "new" ] || continue
  (
    out=$(gssh "$account" "$project" "$vm" "$zone" '
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

# Collect new pubkeys
for entry in "${NODES[@]}"; do
  read -r account project vm zone pubip wgip role <<< "$entry"
  [ "$role" = "new" ] || continue
  PUBKEY[$vm]=$(grep "^PUBKEY " "$TMP/$vm.out" | awk '{print $2}')
  if [ -z "${PUBKEY[$vm]}" ]; then echo "FATAL: no pubkey for $vm"; exit 1; fi
  echo "$vm pubkey: ${PUBKEY[$vm]}"
done

echo "### PHASE 2: write full 9-peer wg0.conf on every node"
for entry in "${NODES[@]}"; do
  read -r account project vm zone pubip wgip role <<< "$entry"
  peers=""
  for other in "${NODES[@]}"; do
    read -r oaccount oproject ovm ozone opubip owgip orole <<< "$other"
    [ "$ovm" = "$vm" ] && continue
    peers+="
[Peer]
PublicKey = ${PUBKEY[$ovm]}
Endpoint = $opubip:51820
AllowedIPs = $owgip/32
PersistentKeepalive = 25
"
  done

  if [ "$role" = "new" ]; then
    # fresh node: write conf and bring the interface up
    apply='systemctl enable wg-quick@wg0 >/dev/null 2>&1
systemctl restart wg-quick@wg0'
  else
    # live node: write conf and hot-apply peers without restarting the interface
    apply='wg syncconf wg0 <(wg-quick strip wg0)'
  fi

  gssh "$account" "$project" "$vm" "$zone" "sudo bash -c 'cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = $wgip/24
PrivateKey = \$(cat /etc/wireguard/private.key)
ListenPort = 51820
MTU = 1380
$peers
EOF
chmod 600 /etc/wireguard/wg0.conf
$apply' && echo WG_APPLIED $vm $role"
done

echo "### PHASE 3: verify full 10x10 mesh from every node"
sleep 8
for entry in "${NODES[@]}"; do
  read -r account project vm zone pubip wgip role <<< "$entry"
  out=$(gssh "$account" "$project" "$vm" "$zone" "
    ok=1
    for ip in $ALL_WGIPS; do
      ping -c1 -W3 \$ip >/dev/null 2>&1 || { echo \"PING_FAIL \$ip\"; ok=0; }
    done
    [ \$ok = 1 ] && echo MESH_OK")
  if echo "$out" | grep -q MESH_OK; then echo "MESH_OK from $vm"; else echo "MESH_FAIL from $vm: $out"; fi
done
echo "### DONE"
