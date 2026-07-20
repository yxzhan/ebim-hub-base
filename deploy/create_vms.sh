#!/usr/bin/env bash
# Create one g2-standard-32 (1x NVIDIA L4) VM with 200GB disk in each of the 4 test projects.
# Tries europe zones first; once a zone works, prefers it for the remaining projects
# so all VMs land in the same zone when possible.
set -u
export PATH=/opt/google-cloud-sdk/bin:$PATH

ACCOUNTS=(
  "<account-281> ebim26ham-281"
  "<account-288> ebim26ham-288"
  "<account-289> ebim26ham-289"
  "<account-290> ebim26ham-290"
)

# L4 zones (gcloud compute accelerator-types list --filter="name:nvidia-l4"), europe first
ZONES=(
  europe-west1-b europe-west1-c
  europe-west4-a europe-west4-b europe-west4-c
  europe-west2-a europe-west2-b
  europe-west3-a europe-west3-b
  europe-west6-b europe-west6-c
  us-central1-a us-central1-b us-central1-c
  us-east1-b us-east1-c us-east1-d
  us-east4-a us-east4-c
  us-west1-a us-west1-b us-west1-c
  us-west4-a us-west4-c
)

PREFERRED_ZONE=""
declare -A RESULTS

create_in_zone() {
  local account="$1" project="$2" name="$3" zone="$4"
  gcloud compute instances create "$name" \
    --account="$account" \
    --project="$project" \
    --zone="$zone" \
    --machine-type=g2-standard-32 \
    --accelerator=count=1,type=nvidia-l4 \
    --maintenance-policy=TERMINATE \
    --provisioning-model=STANDARD \
    --image-family=ubuntu-2404-lts-amd64 \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=200GB \
    --boot-disk-type=pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --reservation-affinity=any 2>&1
}

for entry in "${ACCOUNTS[@]}"; do
  account="${entry%% *}"
  project="${entry##* }"
  name="l4-vm-${project##*-}"
  echo "=============================================="
  echo ">>> $account / $project  (instance: $name)"

  # Make sure the Compute API is enabled (no-op if already enabled)
  gcloud services enable compute.googleapis.com --account="$account" --project="$project" >/dev/null 2>&1

  # Build zone try-order: preferred zone first if we have one
  try_zones=()
  [ -n "$PREFERRED_ZONE" ] && try_zones+=("$PREFERRED_ZONE")
  for z in "${ZONES[@]}"; do
    [ "$z" != "$PREFERRED_ZONE" ] && try_zones+=("$z")
  done

  created=""
  for zone in "${try_zones[@]}"; do
    echo "--- trying zone $zone ..."
    out=$(create_in_zone "$account" "$project" "$name" "$zone")
    if echo "$out" | grep -q "RUNNING"; then
      echo "$out" | tail -3
      echo "*** SUCCESS: $project -> $name in $zone"
      RESULTS[$project]="$zone"
      PREFERRED_ZONE="$zone"
      created="yes"
      break
    fi
    # Retryable in another zone: capacity or zonal resource issues
    if echo "$out" | grep -qiE "ZONE_RESOURCE_POOL_EXHAUSTED|resource pool|does not have enough resources|not available in zone|UNSUPPORTED_OPERATION"; then
      echo "    zone unavailable: $(echo "$out" | grep -m1 -iE 'exhausted|resources|available' || echo 'capacity issue')"
      continue
    fi
    # Quota errors: region-specific quota -> try other region; global quota -> stop for this account
    if echo "$out" | grep -qi "quota"; then
      echo "    QUOTA error:"
      echo "$out" | grep -i -m2 "quota"
      if echo "$out" | grep -qi "GPUS_ALL_REGIONS\|all_regions"; then
        echo "    Global GPU quota is 0 for $project - cannot create GPU VM anywhere. Skipping."
        RESULTS[$project]="FAILED: global GPU quota"
        break
      fi
      continue
    fi
    # Anything else (auth, permission, billing) - report and stop for this account
    echo "    FATAL error for $project:"
    echo "$out" | tail -5
    RESULTS[$project]="FAILED: see error above"
    break
  done
  [ -z "$created" ] && [ -z "${RESULTS[$project]:-}" ] && RESULTS[$project]="FAILED: no zone available"
done

echo "=============================================="
echo "SUMMARY:"
for entry in "${ACCOUNTS[@]}"; do
  project="${entry##* }"
  echo "  $project : ${RESULTS[$project]:-unknown}"
done
