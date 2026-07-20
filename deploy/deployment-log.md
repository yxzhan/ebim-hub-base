# Deploying the VRB System on Google Cloud

> A complete, step-by-step record of deploying the VRB (BinderHub-based) system on
> Google Cloud for the EBiM benchmark infrastructure.
> Steps marked **manual operation required** cannot be automated and require a human operator; all
> other steps are fully scripted / agent-automatable.

> **Sanitization note.** This document lives in a *public* repository (BinderHub
> clones it to launch the lab). Two classes of genuinely sensitive values have been
> redacted with placeholders: **GCP account emails** (`<account-28x>`) and **static
> external IPs** (`<static-ip-28x>`). Project IDs, WireGuard overlay IPs
> (`10.100.0.x`, private/unreachable), in-cluster ClusterIPs (`10.152.183.x`) and the
> public service domains are retained for reproducibility. The credentials file
> `gc-accounts.md` (account passwords) is **never** committed and is kept out of every
> repository.

## Prerequisites

- **Test accounts.** `gc-accounts.md` (kept private, not in this repo) lists the
  Google Cloud test accounts (name / password / project). During the pilot there were
  first 4, later expanded to 10 accounts, each in its own project:

  | Account | Project |
  |---|---|
  | `<account-281>` | ebim26ham-281 |
  | `<account-288>` | ebim26ham-288 |
  | `<account-289>` | ebim26ham-289 |
  | `<account-290>` | ebim26ham-290 |

  Passwords live only in `gc-accounts.md` (never reproduced here).
- **Target machine type:** `g2-standard-32` (32 vCPU / 128 GB RAM, 1× NVIDIA L4),
  200 GB disk.
- **Zones offering NVIDIA L4** (Europe prioritized), obtained via:

  ```bash
  gcloud compute accelerator-types list --filter="name:nvidia-l4"
  ```

  > The zone list is a point-in-time result (queried 2026-07-16); GPU supply changes
  > over time, so re-run the command before re-deploying.

---

## Step 1 — Create one GPU VM per account

*(Completed 2026-07-16, ~20 min total, most of it manual login.)*

### 1.1 Install the Google Cloud CLI (automated)

If `gcloud` is not present, install from the official tarball (no apt repo needed):

```bash
cd /opt
curl -sSL -o gcloud.tar.gz https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz
tar -xzf gcloud.tar.gz && rm gcloud.tar.gz
export PATH=/opt/google-cloud-sdk/bin:$PATH   # add to ~/.bashrc
```

### 1.2 Console prep: enable API, request GPU quota — manual

New test accounts have a **GPU quota of 0** by default; without a quota increase no
GPU VM can be created. This must be done per account in the web console:

1. Open <https://console.cloud.google.com/> and sign in with the test account
   (password in `gc-accounts.md`; an incognito window is recommended);
2. Select the account's project in the top project picker;
3. Enable the Compute Engine API (Navigation menu → Compute Engine; the first visit
   prompts to Enable);
4. Try to create an NVIDIA L4 VM (Compute Engine → Create instance, GPU = NVIDIA L4):
   the right-hand panel warns that **GPUs (all regions)** quota is insufficient (needs 1);
5. Click **"Request quota adjustment"** and raise GPUs (all regions) to **1**;
6. Once approved (usually an email within minutes), you do **not** need to actually
   finish creating this VM in the console — the script creates them later.

> The 1.4 script does run `gcloud services enable compute.googleapis.com`, but there is
> **no CLI path** to request a GPU quota increase — it must be triggered manually in the
> console. Skipping this makes the script fail with a `GPUS_ALL_REGIONS` quota error and
> skip that account.

### 1.3 Log in to each account — manual operation required

**This is the one step in the whole flow that cannot be automated.** The gcloud CLI does
not support username/password login; Google accounts only authenticate via browser OAuth:

```bash
gcloud auth login <account-281> --no-launch-browser
# ... repeat for each account
```

Per command:

1. The command prints a URL — open it in a browser;
2. Sign in with the matching account (password in `gc-accounts.md`) and authorize;
3. Paste the returned verification code back into the terminal.

Notes:

- Use an **incognito window**; log out / switch windows between accounts so sessions
  don't interfere;
- All account credentials coexist in one gcloud config; later commands disambiguate via
  `--account=<account> --project=<project>` — no need to switch the active account.

Verify: `gcloud auth list` should list all accounts.

### 1.4 Batch-create the VMs (automated)

Run `create_vms.sh`:

```bash
bash create_vms.sh
```

Logic:

- For each project, `gcloud services enable compute.googleapis.com` (idempotent);
- Try zones by priority: europe-west1 → europe-west4 → europe-west2/3/6 → US regions;
- **Co-location strategy:** after the first success, later projects prefer the *same*
  zone, keeping the fleet in one region where possible;
- On `ZONE_RESOURCE_POOL_EXHAUSTED` (capacity) or regional quota shortfall, auto-retry
  another zone; on `GPUS_ALL_REGIONS` (global GPU quota = 0), skip the account and report.

Core creation command (one VM per project):

```bash
gcloud compute instances create <instance> \
    --account=<account> --project=<project> --zone=<zone> \
    --machine-type=g2-standard-32 \
    --accelerator=count=1,type=nvidia-l4 \
    --maintenance-policy=TERMINATE \
    --provisioning-model=STANDARD \
    --image-family=ubuntu-2404-lts-amd64 \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=200GB \
    --boot-disk-type=pd-balanced \
    --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
    --reservation-affinity=any
```

### 1.5 Result of this run

europe-west1-b/c and europe-west4-a/b were out of L4 capacity, so all 4 VMs fell through
to **europe-west4-c** (Netherlands), same zone:

| Project | Instance | Zone | State | External IP |
|---|---|---|---|---|
| ebim26ham-281 | l4-vm-281 | europe-west4-c | RUNNING | `<static-ip-281>` |
| ebim26ham-288 | l4-vm-288 | europe-west4-c | RUNNING | `<static-ip-288>` |
| ebim26ham-289 | l4-vm-289 | europe-west4-c | RUNNING | `<static-ip-289>` |
| ebim26ham-290 | l4-vm-290 | europe-west4-c | RUNNING | `<static-ip-290>` |

> ⚠️ GPU capacity fluctuates; a re-run may land in different zones — trust the script's
> SUMMARY. External IPs here are still ephemeral (they become static in Step 3.2).

### 1.6 Known follow-ups

- **NVIDIA driver not installed** — the Ubuntu 24.04 image ships no GPU driver; install
  per machine before using the GPU (Step 2).
- No Ops Agent / snapshot policy configured (add as needed).

---

## Step 2 — Install the NVIDIA GPU driver

*(Completed 2026-07-16, fully automated, ~8 min.)*

### 2.1 Install & verify (automated)

Run `install_gpu_drivers.sh`. Three phases:

1. **Parallel install** via `gcloud compute ssh --command` on all VMs:
   `sudo apt-get install -y nvidia-driver-570-server` (Ubuntu's server driver; apt may
   resolve a newer point release);
2. **Reboot** each VM to load the kernel module;
3. **Verify** `nvidia-smi` per VM, up to 6 retries (20 s apart), confirming the L4.

> On the first `gcloud compute ssh` to a project, a local SSH key
> (`~/.ssh/google_compute_engine`) is generated and pushed to project metadata — a short
> extra wait is normal.

### 2.2 Result

All VMs installed successfully; consistent `nvidia-smi`:

| Instance | GPU | Driver | VRAM |
|---|---|---|---|
| l4-vm-281 | NVIDIA L4 | 580.159.03 | 23034 MiB |
| l4-vm-288 | NVIDIA L4 | 580.159.03 | 23034 MiB |
| l4-vm-289 | NVIDIA L4 | 580.159.03 | 23034 MiB |
| l4-vm-290 | NVIDIA L4 | 580.159.03 | 23034 MiB |

### 2.3 Notes

- CUDA Toolkit (`nvcc`) and Docker / NVIDIA Container Toolkit are not yet installed —
  deferred to Step 3 per the deployment's needs.
- The driver's bundled CUDA runtime is already usable, so frameworks that bundle their own
  CUDA libraries (e.g. PyTorch) can use the GPU directly.

---

## Step 3 — Docker + MicroK8s: build a cross-project cluster

*(Completed 2026-07-16, fully automated, ~15 min.)*

### 3.1 The problem and the approach

The VMs live in **different projects**, which creates two networking obstacles:

1. Each project's default VPC is isolated — no internal connectivity between them;
2. The VPC subnets use the same CIDR, so internal IPs collide (observed: l4-vm-288 and
   l4-vm-289 both got internal IP `10.164.0.2`).

So neither direct internal networking nor VPC Peering (overlapping CIDRs) works. The
solution: a **full-mesh WireGuard encrypted tunnel** as the cluster substrate — all
Kubernetes traffic rides the tunnel:

| Node | Project | WireGuard IP | Role |
|---|---|---|---|
| l4-vm-281 | ebim26ham-281 | 10.100.0.1 | control plane |
| l4-vm-288 | ebim26ham-288 | 10.100.0.2 | worker |
| l4-vm-289 | ebim26ham-289 | 10.100.0.3 | worker |
| l4-vm-290 | ebim26ham-290 | 10.100.0.4 | worker |

### 3.2 Static IPs & firewall (automated)

WireGuard uses each VM's **external IP** as its endpoint, so the tunnel breaks if that IP
changes. Promote each ephemeral IP to a reserved static IP in place, and open the
WireGuard port (only to the other nodes' IPs) in each project:

```bash
gcloud compute addresses create <vm>-static-ip --region=<region> \
    --addresses=<current-external-ip> --project=<project>   # in-place, IP unchanged
gcloud compute firewall-rules create allow-wireguard-mesh --network=default \
    --direction=INGRESS --action=ALLOW --rules=udp:51820 \
    --source-ranges=<other nodes' external IPs /32, comma-separated> --project=<project>
```

> Cluster ports (16443/25000/10250 …) need **no** GCP firewall rule — they all ride the
> WireGuard tunnel; only UDP 51820 is exposed externally.

### 3.3 Docker + WireGuard full mesh (automated)

Run `setup_docker_wireguard.sh`:

1. Parallel `apt install docker.io wireguard`; add the current user to the docker group;
2. Each node generates a WireGuard keypair (private key never leaves the node); after
   collecting public keys, generate each `wg0.conf`: full mesh (3 peers each), `Endpoint`
   = peer's static external IP, `AllowedIPs` = peer's `10.100.0.x/32`, `MTU 1380` (GCP VPC
   MTU 1460 minus WireGuard overhead), `PersistentKeepalive 25` to keep NAT mappings alive;
3. `systemctl enable --now wg-quick@wg0`; verify full 4×4 ping connectivity.

### 3.4 MicroK8s cluster (automated)

Run `setup_microk8s_cluster.sh`:

1. Parallel `snap install microk8s --classic`;
2. **Key config** — bind Kubernetes components to the WireGuard IP (else they register the
   colliding VPC internal IPs):
   - each kubelet gets `--node-ip=10.100.0.x`;
   - the control plane's kube-apiserver gets `--advertise-address=10.100.0.1`;
3. On 281, `microk8s add-node --token-ttl 3600` to mint a token; the others
   `microk8s join 10.100.0.1:25000/<token> --worker`;
4. Pin Calico to wg0:
   `kubectl set env ds/calico-node -n kube-system IP_AUTODETECTION_METHOD=interface=wg0`.

### 3.5 Result & verification

`kubectl get nodes -o wide`: all 4 nodes Ready, INTERNAL-IP = WireGuard IP, v1.35.6
(containerd 2.1.6). **Cross-node pod networking smoke test** (the critical check for this
design): deploy a 4-replica nginx (one pod per node), curl from the pod on 281 to the pods
on the other 3 nodes — all HTTP 200; cleaned up afterward.

Cluster entrypoint: SSH to l4-vm-281, then `sudo microk8s kubectl ...`.

### 3.6 Notes & follow-ups

- GPU not yet wired into Kubernetes: `microk8s enable gpu` (deploys the NVIDIA GPU
  Operator) is done when deploying VRB (Step 4.1).
- Traffic rides WireGuard (MTU ~1380), so bulk throughput is slightly below native VPC.
- If a VM stops and restarts, the static IP is unchanged, so WireGuard and the cluster
  recover automatically.

---

## Step 4 — Deploy BinderHub (the VRB core)

*(Completed 2026-07-16; config from
[IntEL4CoRo/binder.intel4coro.de-deploy](https://github.com/IntEL4CoRo/binder.intel4coro.de-deploy),
following its Chapter 2 self-hosted MicroK8s route.)*

### 4.1 Complete the Chapter 1 prerequisites: MicroK8s add-ons + GPU Operator (automated)

On the control plane (281):

```bash
sudo microk8s enable dns                # already on by default
sudo microk8s enable hostpath-storage   # storage class for the hub DB PVC
sudo microk8s enable nvidia             # NVIDIA GPU Operator (detects the host driver)
```

Once the GPU Operator is ready (~3 min pulling images across nodes), each node reports
`nvidia.com/gpu: 1`. This must succeed, because user pods in `binder.yaml` hard-request a
GPU and otherwise won't schedule.

### 4.2 Deviations from the tutorial (environment-driven)

| Tutorial | This environment | Why |
|---|---|---|
| MetalLB for LoadBalancer IPs | **ClusterIP** services | MetalLB relies on L2/ARP, which doesn't work over the L3 WireGuard tunnel; exposure is via Cloudflare Tunnel instead (the tutorial's self-hosted route) |
| `hub_url` = domain | temporarily `proxy-public` ClusterIP | domain + HTTPS configured together with Cloudflare Tunnel |
| build node unpinned | `build_node_selector` pinned | build pods mount the host Docker socket; pinning to the control plane simplifies image-cache management |

All deviations live in one overrides file `values-gc-overrides.yaml` (last in the helm
command → highest precedence).

### 4.3 Configure registry credentials — manual operation required

Built user-environment images push to Docker Hub. On the control plane, edit
`~/binder.intel4coro.de-deploy/secret.yaml` with the shared intel4coro account (the VRB
lab images are pre-built there and can be pulled directly):

```yaml
registry:
  username: intel4coro
  password: "dckr_pat_xxxxxxxx"   # quote it
```

> ⚠️ **Gotcha:** the token must be a **plain string value** for `password:`. Pasting a
> nested structure like `password: DOCKERHUB_AUTH_TOKEN: xxx` makes YAML parse it as a
> dict, and helm fails with a schema error (`got object, want null or string`). Quoting
> avoids parse issues from special characters.

### 4.4 Deploy (automated)

On the control plane (chart is the tutorial-verified stable version):

```bash
cd ~/binder.intel4coro.de-deploy
sudo microk8s helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
sudo microk8s helm repo update
sudo microk8s helm upgrade --cleanup-on-fail \
  --install binder \
  jupyterhub/binderhub --version=1.0.0-0.dev.git.3941.h9056a226 \
  --namespace=binder --create-namespace \
  -f ./secret.yaml -f ./binder.yaml -f ./values-gc-overrides.yaml
```

Afterward, read the `proxy-public` ClusterIP, write it into `hub_url` in the overrides
file, and re-run the same `helm upgrade` (without `--install`).

### 4.5 Result

`kubectl get pods -n binder`: 9 pods Running (binder, hub, proxy, 2× user-scheduler,
4× image-cleaner). Services (all ClusterIP):

| Service | ClusterIP | Note |
|---|---|---|
| binder | 10.152.183.176:80 | BinderHub frontend |
| proxy-public | 10.152.183.49:80 | JupyterHub entry (hub_url points here) |

Verify: on a node, `curl http://10.152.183.176/` → HTTP 200, title "IAI Binder" (the
initContainer's custom UI is in effect); `curl http://10.152.183.49/hub/api` → HTTP 200.

### 4.6 Follow-ups

- ⚠️ **Docker Hub token not yet effective** — the first token value was wrong (see 4.3
  gotcha); the registry password is a placeholder. Core services are unaffected, but
  **pushing a built image will fail** until the token is fixed and helm re-upgraded.
- GPU time-slicing (tutorial Ch. 3) not yet configured.
- Domain + HTTPS: Step 5.
- End-to-end test: after the token is fixed.

---

## Step 5 — Expose publicly via Cloudflare Tunnel (domain + HTTPS)

*(Completed 2026-07-16; tutorial Step 7 self-hosted route.)*

Final entrypoints:

- **BinderHub:** <https://ebim-binder.aicor.dev>
- **JupyterHub:** <https://ebim-jupyter.aicor.dev> (`hub_url` points here)

### 5.1 Prereq & install (automated)

Prereq: the domain (`aicor.dev`) DNS is already managed by Cloudflare (free tier is fine).
Install cloudflared (official deb) on the control plane:

```bash
curl -sSL -o /tmp/cloudflared.deb \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i /tmp/cloudflared.deb
```

### 5.2 Authorize the Cloudflare account — manual operation required

Run `cloudflared tunnel login`; it prints a `https://dash.cloudflare.com/argotunnel?...`
URL — open it, sign in, select the target zone, and authorize. The cert is written to
`~/.cloudflared/cert.pem`.

### 5.3 Create the tunnel & routes (automated)

```bash
cloudflared tunnel create vrb          # generates a tunnel id + credentials json
cat > ~/.cloudflared/config.yml <<EOF
tunnel: <TUNNEL_ID>
credentials-file: /root/.cloudflared/<TUNNEL_ID>.json
ingress:
  - hostname: ebim-binder.aicor.dev
    service: http://10.152.183.176:80   # binder ClusterIP
  - hostname: ebim-jupyter.aicor.dev
    service: http://10.152.183.49:80    # proxy-public ClusterIP
  - service: http_status:404
EOF
cloudflared tunnel route dns vrb ebim-binder.aicor.dev
cloudflared tunnel route dns vrb ebim-jupyter.aicor.dev
sudo cloudflared --config /root/.cloudflared/config.yml service install
sudo systemctl restart cloudflared
```

cloudflared runs on the control-plane host and reaches the ClusterIPs directly (kube-proxy
on the node). The outbound tunnel needs no GCP firewall port, and Cloudflare manages the
HTTPS cert automatically.

> ⚠️ If a service's ClusterIP changes (e.g. a release is recreated), update
> `/etc/cloudflared/config.yml` and `systemctl restart cloudflared`.

### 5.4 Gotcha: multi-level subdomains and the free cert

The original plan used `binder.ebim.aicor.dev` (a 2nd-level subdomain); TLS handshake
failed outright (alert 40): **Cloudflare's free Universal SSL covers only `aicor.dev` and
`*.aicor.dev`, not `*.ebim.aicor.dev`.** Multi-level subdomain certs require the paid
Advanced Certificate Manager. Fix: single-level subdomains `ebim-binder` / `ebim-jupyter`.
(Leftover: the initial `binder.ebim` / `jupyter.ebim` CNAMEs can't be deleted via
cloudflared; clean them up in the Cloudflare console.)

### 5.5 Switch hub_url & verify (automated)

Set `hub_url` to `https://ebim-jupyter.aicor.dev` in the overrides and re-run `helm
upgrade`. Public check: `https://ebim-binder.aicor.dev/` and
`https://ebim-jupyter.aicor.dev/hub/api` both return HTTP 200, title "IAI Binder".

### 5.6 Expose the Kubernetes Dashboard (2026-07-17)

After `sudo microk8s enable dashboard`, reuse the same `vrb` tunnel with one extra ingress
(no new tunnel needed). The new dashboard add-on installs into the `kubernetes-dashboard`
namespace behind `kubernetes-dashboard-kong-proxy` (ClusterIP `10.152.183.154:443`, **HTTPS
self-signed**), so the ingress uses `https://` with `noTLSVerify: true`. Insert before the
catch-all `http_status:404`:

```yaml
  - hostname: ebim-dashboard.aicor.dev
    service: https://10.152.183.154:443
    originRequest:
      noTLSVerify: true
```

```bash
sudo cloudflared --config /etc/cloudflared/config.yml tunnel ingress validate
sudo cloudflared tunnel route dns vrb ebim-dashboard.aicor.dev
sudo systemctl restart cloudflared
```

Login needs a Bearer token — manual operation required:

```bash
sudo microk8s kubectl -n kube-system create token default --duration 24h
# If permissions are insufficient, bind cluster-admin to the default SA first:
# sudo microk8s kubectl create clusterrolebinding dashboard-admin \
#   --clusterrole=cluster-admin --serviceaccount=kube-system:default
```

> ⚠️ A public dashboard + cluster-admin token is highly privileged — enable only
> temporarily, or add a Cloudflare Access policy. If the kong-proxy ClusterIP changes,
> update config.yml accordingly.

---

## Step 6 — Pre-pull images (all nodes)

*(Completed 2026-07-16, fully automated.)*

User session images are large; without pre-pulling, the first session on a node waits a
long time. A DaemonSet pulls common images into every node's containerd cache (an
initContainer references the image then exits, forcing kubelet to pull; a pause container
keeps the pod alive so the image isn't GC'd).

`image-prepuller-gc.yaml`, adapted from the repo template with two changes: drop the
GKE-only `nodeSelector`/`tolerations` (all nodes run user pods here), and set the image to
the VRB hub base.

> BinderHub image naming: `<image_prefix><escaped-org>-2d<escaped-repo>-<hash>:<commit-sha>`
> (`-`→`-2d`, `.`→`-2e`, `_`→`-5f`); look them up at https://hub.docker.com/u/intel4coro.

```bash
kubectl apply -f image-prepuller-gc.yaml    # apply/update
kubectl get ds image-prepuller -n binder    # READY == node count → done
```

This run: all nodes READY in ~4.5 min. To pre-pull more images, append to
`initContainers` and re-apply.

---

## Step 7 — End-to-end verification

*(Completed 2026-07-16, fully automated.)*

Test entrypoint (EBiM workspace, with the `urlpath` redirect):

```
https://ebim-binder.aicor.dev/v2/gh/yxzhan/ebim-hub-base.git/stress?urlpath=proxy%2F8899
```

### 7.1 Gotcha: running as root without `--allow-root` → spawn timeout

First launch failed: `Spawn failed: Server ... didn't respond in 120 seconds`. Pod logs
showed Jupyter exiting immediately:

```
[C ServerApp] Running as root is not recommended. Use --allow-root to bypass.
```

Cause: `binder.yaml` runs user pods as root (`c.BinderSpawner.uid = 0`), but the config
that passes `--allow-root` is **commented out** upstream, so Jupyter refuses to start and
the hub times out at 120 s. Fix — append hub extraConfig in the overrides (helm key-merges
extraConfig dicts, so it doesn't clobber existing binder.yaml config):

```yaml
jupyterhub:
  hub:
    extraConfig:
      gc-allow-root: |
        c.BinderSpawner.args = ["--allow-root"]
```

> General way to debug user-pod startup: right after triggering a launch,
> `kubectl logs -n binder -f jupyter-<...>` — after a spawn failure the hub deletes the
> pod, so grab logs within the live window.

### 7.2 Result

- **Pre-pull works:** launch skips the build, event stream shows "already present on
  machine", container starts in seconds;
- **Spawn succeeds:** `phase: ready`, session URL
  `https://ebim-jupyter.aicor.dev/user/yxzhan-ebim-hub-base-<id>/`;
- **JupyterLab:** `/lab?token=...` → HTTP 200, title "JupyterLab";
- **urlpath target:** `/proxy/8899?token=...` → HTTP 200, title **"EBiM Workspace"** — the
  test entrypoint auto-redirects through the BinderHub launch page to the workspace UI.

At this point the full VRB stack is usable on GC. Remaining option: GPU time-slicing
(tutorial Ch. 3).

---

## Step 8 — Mount the Isaac Sim cache directory (hostPath)

*(Completed 2026-07-16, fully automated.)*

Mount the host `/root/isaac-sim/kit/cache` into each user pod at `/isaac-sim/kit/cache` so
Isaac Sim's shader/asset cache is reused across sessions.

### 8.1 Create the directory on all nodes (automated)

hostPath points at a local dir on **whichever node** the pod lands on, and user pods can
schedule anywhere, so create it on every node:

```bash
sudo mkdir -p /root/isaac-sim/kit/cache   # on each node
```

### 8.2 Configure & deploy (automated)

Append to the overrides (z2jh `singleuser.storage` syntax; `DirectoryOrCreate` so kubelet
creates it even if missing):

```yaml
jupyterhub:
  singleuser:
    storage:
      extraVolumeMounts:
        - name: isaacsim-kit-cache
          mountPath: /isaac-sim/kit/cache
      extraVolumes:
        - name: isaacsim-kit-cache
          hostPath:
            path: /root/isaac-sim/kit/cache
            type: DirectoryOrCreate
```

Re-run `helm upgrade`. User pods run as root, so they have RW access to the dir naturally.

### 8.3 Verify

Launch a test session; inside the pod `mount` shows `/isaac-sim/kit/cache`; write a test
file in the pod and confirm it appears on the host's `/root/isaac-sim/kit/cache/` — RW works
both ways.

### 8.4 Notes

- The cache is **node-local**: each node has its own; a session uses whichever node it lands
  on; sessions on the same node share it. First use of a node starts empty and Isaac Sim
  fills it.
- Watch disk usage: the Isaac Sim cache can grow to tens of GB, and node disks are only
  200 GB (also holding container images) — clean up periodically if needed.

---

## Step 9 — Enable VirtualGL EGL rendering (VGL_DISPLAY)

*(Completed 2026-07-16, fully automated.)*

Upstream `binder.yaml` has `VGL_DISPLAY: "egl"` commented out; enable it (VirtualGL uses
the EGL backend for GPU rendering without an X server). Don't edit upstream — add to the
overrides (helm key-merges `extraEnv`, so the existing 6 env vars are preserved):

```yaml
jupyterhub:
  singleuser:
    extraEnv:
      VGL_DISPLAY: "egl"
```

After `helm upgrade`, a new session's `env` confirms `VGL_DISPLAY=egl` alongside the
existing vars (ACCEPT_EULA, OMNI_KIT_*, …).

> The change affects **newly launched sessions only**; existing pods are unchanged. Don't
> exec into an old pod to verify (you'll wrongly conclude it didn't take). Clear all user
> session pods:
>
> ```bash
> microk8s.kubectl get pods -n binder --no-headers | awk '/^jupyter-/{print $1}' \
>   | xargs microk8s.kubectl delete pod -n binder
> ```

---

## Step 10 — Scale out: fold 6 new accounts into the cluster (4 → 10 nodes)

*(Completed 2026-07-16. 6 new accounts/projects 282–287 join as workers, reusing the same
BinderHub / Cloudflare entry — no new system stood up.)*

New accounts & nodes (WireGuard IPs continue after the first 4):

| Account | Project | Instance | WG IP | Final Zone |
|---|---|---|---|---|
| `<account-282>` | ebim26ham-282 | l4-vm-282 | 10.100.0.5 | us-central1-c |
| `<account-283>` | ebim26ham-283 | l4-vm-283 | 10.100.0.6 | us-west4-c |
| `<account-284>` | ebim26ham-284 | l4-vm-284 | 10.100.0.7 | europe-west4-c |
| `<account-285>` | ebim26ham-285 | l4-vm-285 | 10.100.0.8 | us-east1-b |
| `<account-286>` | ebim26ham-286 | l4-vm-286 | 10.100.0.9 | us-east1-b |
| `<account-287>` | ebim26ham-287 | l4-vm-287 | 10.100.0.10 | us-west4-c |

> ⚠️ This round **Europe's L4 capacity was fully exhausted** (`ZONE_RESOURCE_POOL_EXHAUSTED`);
> only 284 landed in europe-west4-c, the rest scattered across US regions (cross-continent).
> That doesn't affect the mesh — WireGuard rides external IPs, so connectivity is fine; only
> latency to the (EU) control plane is a bit higher.

Prereqs (same as Step 1): each account completes the **1.2 GPU-quota request** (manual) and
**1.3 gcloud login** (manual); done in advance by the admin this round.

### 10.1 Create VMs (automated)

`create_vms_batch2.sh` — same logic as `create_vms.sh` but accounts 282–287 and
`PREFERRED_ZONE` seeded to `europe-west4-c` (co-locate with the existing cluster; fall
through on shortage).

### 10.2 Install GPU drivers (automated)

`install_gpu_drivers_batch2.sh` — same as Step 2, but since the 6 VMs are **not in one
zone**, each VM carries its own zone and `gssh` connects per-VM zone. Result: all 6 on
`nvidia-driver 580.159.03`, L4 detected.

### 10.3 Static IP + firewall (automated)

- Promote the 6 ephemeral IPs to static (per region);
- Across **10 projects**, `allow-wireguard-mesh` now allows all 10 external IPs
  (UDP 51820): the existing 4 use `firewall-rules update` to widen source-ranges; the new 6
  use `firewall-rules create`.

### 10.4 Expand the WireGuard mesh to 10 nodes — zero downtime (automated)

`setup_wireguard_expand.sh`. Key point: the cluster is **live** (all Kubernetes traffic
rides WireGuard), so expanding the mesh must **not restart wg0** on existing nodes or the
cluster jitters. Approach:

- Rewrite all 10 nodes with the full 9-peer `wg0.conf` (idempotent);
- **New 6 nodes:** `systemctl restart wg-quick@wg0` (fresh interface, just bring it up);
- **Existing 4 nodes:** only `wg syncconf wg0 <(wg-quick strip wg0)` — hot-load the new
  peers **without down/up**, so existing tunnels and cluster traffic are uninterrupted.

Verify: each node pings all 10 WG IPs, 10×10 all pass.

> ⚠️ **Gotcha:** on the first run, a PHASE 2 log line was `echo WG_APPLIED $vm ($role)`;
> the remote shell interpreted `(existing)`/`(new)` as subshell syntax, so the **entire
> line — including the `sudo bash -c` that wrote the config — was rejected as a syntax
> error and never executed**. Symptom: no config landed and all pings failed, yet the live
> cluster was untouched (and so unharmed). Removing the parens fixed it. Lesson: any bare
> parentheses in a `gcloud compute ssh --command` string are interpreted by the remote
> shell — even in log text.

### 10.5 MicroK8s scale-out (automated)

`setup_microk8s_expand.sh` — 6× `snap install microk8s` (same v1.35.6), kubelet `--node-ip`
= own WG IP, each takes a one-time token and `join 10.100.0.1:25000 --worker`. The control
plane stays 281 (Calico already pinned to wg0, apiserver advertise-address already set).
Result: **10 nodes Ready**, INTERNAL-IP = each WG IP.

### 10.6 BinderHub auto-spreads + wrap-up (automated)

BinderHub is cluster-scoped, so new nodes mostly take effect automatically after join:

- **GPU Operator** auto-detects the 6 new nodes and deploys operands (~3 min); all 10
  report `nvidia.com/gpu: 1`;
- **Image pre-pull DaemonSet** (Step 6): `DESIRED` auto-goes 4 → 10; once the 6 new nodes
  pull hub-base → `READY 10/10`; new sessions start in seconds on any node;
- **Isaac cache dir** (Step 8): hostPath is node-local, so each new node runs
  `sudo mkdir -p /root/isaac-sim/kit/cache`.

The `binder` / `proxy-public` ClusterIPs are **unchanged**, so the Cloudflare Tunnel and
public entrypoints need no edits.

### 10.7 Verification

- 10 nodes Ready, all GPUs `1`, pre-pull `10/10`, all binder core pods Running;
- **New-node GPU scheduling smoke test:** on 287, a `nodeSelector`-pinned pod requesting
  `nvidia.com/gpu:1` runs `nvidia-smi`, returns `NVIDIA L4, 580.159.03`, `phase: Succeeded`;
  cleaned up. New nodes are end-to-end usable.

> All scripts this round are named `*_batch2` / `*_expand`, coexisting with batch 1 for
> traceability.

---

## Step 11 — Isaac Sim shader-cache warmup (all nodes)

*(Completed 2026-07-16. Building on Step 8, pre-fill each node's cache so the first session
on a node skips live shader compilation.)*

### 11.1 Why a Job, not the image-prepuller DaemonSet

`/isaac-sim/warmup.sh` starts Isaac Sim's RTX renderer to warm the shader cache — it must
**own `nvidia.com/gpu: 1` and needs EGL rendering**. In Kubernetes, as soon as any of a
pod's containers (incl. init) requests a GPU, the scheduler **reserves that GPU for the
whole pod lifetime**. The image-prepuller is a **long-lived DaemonSet** with a pause
container; giving it a GPU would **permanently pin each node's only L4 and starve user
sessions**.

So warmup uses a **one-shot Job** (one per node, `nodeSelector` pinned to hostname): it runs
`warmup.sh`, exits, and **releases the GPU**; the cache persists in the node-local hostPath.
The image-prepuller stays as-is for image caching — clean division of labor.

### 11.2 Configure & run (automated)

- Template `isaac-warmup-gc.yaml`: a hub-base container runs `/isaac-sim/warmup.sh`,
  mounting `hostPath /root/isaac-sim/kit/cache → /isaac-sim/kit/cache` just like singleuser,
  with the same Isaac env vars (ACCEPT_EULA / PRIVACY_CONSENT / OMNI_KIT_ACCEPT_EULA /
  OMNI_KIT_ALLOW_ROOT / VGL_DISPLAY=egl / NVIDIA_DRIVER_CAPABILITIES=all), `runAsUser: 0`,
  `resources.limits.nvidia.com/gpu: 1`, `restartPolicy: Never`, `ttlSecondsAfterFinished`
  auto-cleanup.
- Runner `run_isaac_warmup.sh [node...]` (defaults to all 10): fills `__NODE__`/`__SUFFIX__`
  per node, `kubectl apply`, polls to `Complete`.

```bash
bash run_isaac_warmup.sh 287            # single-node trial
bash run_isaac_warmup.sh                # all 10 (each on its own node's GPU, in parallel)
```

### 11.3 Result

- Trial on 287: Job `Complete` in ~4 min, cache dir **0 files → 174 MB / 307 files** —
  confirms warmup.sh works and the cache lands;
- Full rollout: **all 10 Jobs `Complete`** (~2.5–4 min each, in parallel on each node's own
  GPU, no contention). Thereafter any session hits the pre-warmed shader cache.

> Notes:
> - During warmup that node's GPU is busy; if a node is already serving a user session, its
>   warmup Job stays `Pending` until free (it doesn't preempt a running session).
> - The cache is node-local; after a `base` image update (shaders may change), re-run
>   `run_isaac_warmup.sh` to refresh each node.

### 11.4 Clean up warmup Jobs (automated)

Warmup is one-shot; once `Complete`, the pod just holds a record and uses no resources; the
Job carries `ttlSecondsAfterFinished: 86400` (**auto-deleted after 24 h**). To clear
immediately (deleting the Job removes its pods):

```bash
sudo microk8s kubectl delete jobs -n binder -l app=isaac-warmup
sudo microk8s kubectl get jobs,pods -n binder -l app=isaac-warmup   # confirm empty
```

> ⚠️ Deleting the Job **does not affect the warmup result** — the shader cache lives in each
> node's hostPath, independent of the Job. Re-run `run_isaac_warmup.sh` to refresh (it
> deletes the old same-named Job first).

---

## Step 12 — Tune the session culler (cull) policy

*(Completed 2026-07-16. Relax idle culling and the session cap.)*

Upstream `binder.yaml` culls idle sessions after 5 min (`timeout: 300`), max age 4 h
(`maxAge: 14400`). Relax to **idle 60 min, max age 24 h**. Add to the overrides (helm
key-merge, highest precedence):

```yaml
jupyterhub:
  cull:
    every: 300       # check interval unchanged (5 min)
    timeout: 3600    # idle 60 min (was 300)
    maxAge: 86400    # max session 24 h (was 14400 / 4 h)
```

Apply: `gcloud compute scp` the overrides to the control plane's
`~/binder.intel4coro.de-deploy/`, then `helm upgrade` → REVISION 10. The hub pod rolls to
load the new config; running sessions are unaffected.

Verify: `helm get values binder` shows `cull.timeout=3600 / maxAge=86400 / every=300`; the
rendered `jupyterhub_config.py` runs idle-culler with
`--timeout=3600 --cull-every=300 --max-age=86400`.

---

## Step 13 — Upgrade the BinderHub chart + move the custom-UI initContainer into overrides

*(Completed 2026-07-16.)*

### 13.1 First, sync the *currently effective* overrides file (important)

The live overrides file is on the control plane at `~/binder.intel4coro.de-deploy/`. Before
editing locally, **pull it back** so you don't clobber live changes with a stale copy:

```bash
gcloud compute scp \
  l4-vm-281:/root/binder.intel4coro.de-deploy/values-gc-overrides.yaml \
  ./values-gc-overrides.yaml \
  --zone=europe-west4-c --project=ebim26ham-281 --account=<account-281>
```

### 13.2 Add the custom-UI initContainer to overrides

The custom UI uses an initContainer to clone `github.com/yxzhan/binderhub-custom-files`
(branch `main`) into a shared `custom-templates` emptyDir (defined in binder.yaml's
`extraVolumes`); the binderhub container then reads
`/etc/binderhub/custom/iai/templates`. Add to the **top level** of the overrides:

```yaml
initContainers:
  - name: git-clone-templates
    image: alpine/git
    command:
      - /bin/sh
      - -c
      - |
        rm -rf /etc/binderhub/custom/iai && \
        git clone -b main https://github.com/yxzhan/binderhub-custom-files.git /etc/binderhub/custom/iai
    securityContext:
      runAsUser: 0
    volumeMounts:
      - name: custom-templates
        mountPath: /etc/binderhub/custom
```

> ⚠️ **helm replaces list-type keys wholesale, it does not merge them.** `initContainers`
> is a list, so this one **entirely replaces** the same-named list in binder.yaml — hence
> `securityContext` and `volumeMounts` **must be included**, or the clone lands in the
> container's private dir instead of the shared volume, binderhub can't read the templates,
> and the custom UI silently breaks. The `custom-templates` volume itself comes from
> binder.yaml's `extraVolumes` (a different key, unaffected by this replacement).

### 13.3 Upgrade & apply (command includes the new version)

`helm repo update`, then upgrade with `--version` (chart 3506 → 3941; since the version
changed, keep `--install` + `--create-namespace` for safety):

```bash
sudo microk8s helm repo update
cd ~/binder.intel4coro.de-deploy
sudo microk8s helm upgrade --cleanup-on-fail \
  --install binder \
  jupyterhub/binderhub --version=1.0.0-0.dev.git.3941.h9056a226 \
  --namespace=binder --create-namespace \
  -f ./secret.yaml -f ./binder.yaml -f ./values-gc-overrides.yaml
```

### 13.4 Result & verification

- helm **REVISION 11, deployed**, chart `1.0.0-0.dev.git.3941.h9056a226`;
- binder / hub / proxy / user-scheduler all rolled to new Running pods;
- **initContainer `git-clone-templates` exitCode 0 Completed**; inside binder,
  `/etc/binderhub/custom/iai/templates/page.html` exists;
- custom UI in effect: `curl http://<binder ClusterIP>/` → 200, title **"AICOR Binder"**
  (main branch rebranded to AICOR); `proxy-public/hub/api` → 200;
- **both Service ClusterIPs unchanged** (binder 10.152.183.176 / proxy-public
  10.152.183.49) — the chart upgrade didn't recreate Services, so **Cloudflare Tunnel needs
  no change**.

> Note: the new chart's Service selector label changed from `app=binder-binderhub` to
> `component=binder` (query binder pods with `-l component=binder`); ClusterIP is stable as
> long as the Service isn't deleted, so cloudflared's ingress is unaffected.

---

## Step 14 — Pin the proxy (CHP) to EU, eliminate the trans-Atlantic detour (2026-07-17)

Of the 10 nodes, 5 are in EU (281/284/288/289/290, europe-west4-c) and 5 in US
(282 central1 / 283 west4 / 285/286 east1 / 287 west4). Problem: the scheduler placed
**`proxy` (configurable-http-proxy, CHP) on US node 282**, while the public entry
(cloudflared) and hub are on 281 (EU). So an EU user's path became
`cloudflared(EU) → WG → CHP(US) → WG → userpod(EU)` — **two trans-Atlantic hops** — with
noticeably higher latency.

Why not just replicate the proxy: CHP holds its routing table **in memory**, updated
dynamically by the hub via API (each spawn adds a route). Replicas don't share the table, so
requests randomly hit a replica without the route → 404/misroute. True multi-replica needs
external shared routing state (a different ingress architecture) — not worth it at this
scale.

Right fix: **pin CHP to 281**, co-located with cloudflared/hub (same node → loopback, no WG
at all). EU users now do 0 ocean crossings; US users still do 1 (the entry is in EU anyway,
unavoidable, and no worse). Edit the overrides:

```yaml
jupyterhub:
  proxy:
    service:
      type: ClusterIP
    chp:
      nodeSelector:
        kubernetes.io/hostname: l4-vm-281.c.ebim26ham-281.internal
```

Sync to the control plane, `helm upgrade`.

**Result:** helm REVISION 20; the `proxy` pod rebuilds onto **l4-vm-281**; `proxy-public`
ClusterIP **unchanged** (10.152.183.49), **cloudflared needs no change**;
`ebim-jupyter/hub/api` and `ebim-binder` both 200.

Similarly pin the **binder pod (BinderHub itself) to 281** (REVISION 21) via the chart's
**top-level** `nodeSelector` (not the `jupyterhub.*` subkey); binder.yaml sets no top-level
nodeSelector, so map merge is conflict-free:

```yaml
# top level of values-gc-overrides.yaml
nodeSelector:
  kubernetes.io/hostname: l4-vm-281.c.ebim26ham-281.internal
```

Now **binder / hub / proxy — the three control-plane pods — plus the build pod are all on
281 (EU)**, co-located with cloudflared; binder ClusterIP unchanged (10.152.183.176), entry
200.

> ⚠️ helm upgrade rebuilds the CHP pod; during ~10–30 s the routing table rebuilds and
> active connections reconnect once (running user pods unaffected). This is the unavoidable
> brief blip of migrating a stateful component.

---

## Step 15 — GPU time-slicing: split each L4 into 2 shares (2026-07-17)

Completes the time-slicing left from Step 3 (tutorial Ch. 3). Goal: expose 2
`nvidia.com/gpu` per L4 so two sessions share a card — cluster concurrency 10 → **20**.

MicroK8s uses the NVIDIA gpu-operator (namespace `gpu-operator-resources`, ClusterPolicy
`cluster-policy`). The repo's `time-slicing-config-all.yaml` is `replicas: 4`; this cluster
wants 2, so a GC variant `time-slicing-config-gc.yaml` (ConfigMap name stays
`time-slicing-config-all` to match the patch command), `replicas: 2`:

```yaml
data:
  any: |-
    version: v1
    flags: { migStrategy: none }
    sharing:
      timeSlicing:
        resources:
        - name: nvidia.com/gpu
          replicas: 2
```

Apply on the control plane (load the config into gpu-operator, then point the ClusterPolicy
at it):

```bash
sudo microk8s kubectl apply -f time-slicing-config-gc.yaml -n gpu-operator-resources
sudo microk8s kubectl patch clusterpolicies.nvidia.com/cluster-policy \
  -n gpu-operator-resources --type merge \
  -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config-all","default":"any"}}}}'
```

gpu-operator auto-rolls `nvidia-device-plugin-daemonset` (**no manual rollout restart
needed**); within ~1 min all 10 nodes go from `nvidia.com/gpu: 1` to `2`.

**Result:** 10/10 nodes `allocatable nvidia.com/gpu: 2`; GFD labels
`nvidia.com/gpu.product=NVIDIA-L4-SHARED`, `replicas=2`, `sharing-strategy=time-slicing`
(GFD labels lag the device-plugin slightly; converge within tens of seconds).

> ⚠️ **Time-slicing does not isolate VRAM:** two sessions share the full 24 GB of one L4
> with only time-slice rotation. Isaac Sim is VRAM-heavy, so two heavy sessions on one card
> can OOM each other. For VRAM isolation use MIG (unsupported on L4) or one heavy session
> per card. User pods still request `nvidia.com/gpu: 1`; a physical card now holds 2.

---

## Step 16 — Migrate the control plane 281 → 290 + 3-node HA (2026-07-19)

**Background:** 281 was the single control plane (single-replica dqlite) + cloudflared host +
the pinned binder/hub/proxy node — a complete SPOF. On 7-17 it was manually stopped by
another account and, colliding with a europe-west4-c L4 STOCKOUT, took the whole service down
for two days. To get the "stoppable 281" off the critical path, migrate the control
plane/ingress/load to 290 and make EU nodes 288/289/290 a 3-node HA set (any 1 can fail).

**Key trap: the new control plane must advertise its WireGuard IP.** Test-project VPC
internal IPs collide (e.g. 288/289 both `10.164.0.2`), and MicroK8s defaults to the
default-route IP (VPC), which would write colliding/unreachable addresses into dqlite and the
`kubernetes` service endpoints. So for each new CP node: join over the WG IP
(`microk8s join 10.100.0.1:25000/<token>`, source IP naturally goes via wg0), then append
`--advertise-address=10.100.0.X` to `/var/snap/microk8s/current/args/kube-apiserver` and
restart kubelite; confirm dqlite members and endpoints are all `10.100.0.x`.

**Execution order** (keep 281 as a healthy, rollback-able CP until the last step):

1. Snapshot 281's boot disk (datastore rollback insurance).
2. Promote 290/289/288 to CP one at a time: `microk8s leave` → `microk8s join <WG>` (without
   `--worker`) → set `--advertise-address` + restart → relabel controlplane. At the 3rd node,
   `high-availability: yes` (3 voters). 288 as the 4th ensures 3 voters remain after removing
   281.
3. Migrate cloudflared to 290: install deb → copy `/etc/cloudflared` + `/root/.cloudflared`
   (tunnel credentials) from 281 → `service install` → start → stop 281's cloudflared. Same
   tunnel, multiple replicas coexist; switchover is seamless.
4. Migrate the load to 290: change all nodeSelectors in `values-gc-overrides.yaml` (3
   places + top level + `build_node_selector`) and add `jupyterhub.hub.nodeSelector` to 290,
   then helm upgrade. **hub trap:** the hub's `hub-db-dir` is a hostPath PVC bound to 281,
   so pinning to 290 makes it Pending (node-affinity conflict). BinderHub's hub DB is
   ephemeral session state, so `scale hub 0` → delete the old PVC → helm recreates (a new PV
   on 290), accepting a session-state reset.
5. Demote 281: `microk8s leave` (281) → `microk8s remove-node l4-vm-281...` (on 290) → dqlite
   auto-promotes 288 from standby to voter → 281 rejoins as
   `microk8s join <290 WG>:25000/<token> --worker`.
6. Verify: existing workers' `args/traefik/provider.yaml` already point to the new CP
   (10.100.0.2/3/4), no disconnects; GPU time-slicing survives (device-plugin re-reads after
   leave/join, still `gpu:2`).

**Result:** control plane = **288/289/290** (dqlite 3 voters, all WG IPs, HA=yes); **281
demoted to worker**; 10 nodes all Ready; binder/hub/proxy + cloudflared all on **290**;
`kubernetes` endpoints = 10.100.0.2/3/4; all three public entries (binder/jupyter/dashboard)
200. The deploy dir `~/binder.intel4coro.de-deploy` (incl. secret.yaml) is copied to 290, so
the new primary is self-sufficient.

> ⚠️ Follow-up: `values-gc-overrides.yaml` now pins 290, and `build_node_selector` is on 290
> too; earlier sections describing "control plane 281 / build on 281" are superseded by this
> step. The old hub DB (hostPath on 281) was deleted with its PVC.

---

## Appendix — Node access (SSH) quick reference

`gcloud` is not on the default PATH; prefix commands with
`export PATH=/opt/google-cloud-sdk/bin:$PATH` (or use the absolute path). The gcloud CLI
doesn't support username/password login — credentials go through browser OAuth (see 1.3);
all account credentials are already in the local gcloud config, disambiguated by
`--account`/`--project`.

**Log in to the primary (control plane is 290 since 2026-07-19; HA trio 288/289/290, see
Step 16):**

```bash
gcloud compute ssh l4-vm-290 \
    --zone=europe-west4-c \
    --project=ebim26ham-290 \
    --account=<account-290>
```

> Cluster ops can run on any CP node (290/289/288); the deploy dir
> `~/binder.intel4coro.de-deploy` is on 290. 281 is now a plain worker.

Then use `sudo microk8s kubectl ...`, e.g.:

```bash
sudo microk8s kubectl get nodes -o wide                        # 10 nodes
sudo microk8s kubectl get pods -n binder                       # all BinderHub pods
sudo microk8s kubectl get jobs -n binder -l app=isaac-warmup   # warmup Job status
```

**Log in to any node:** swap `l4-vm-2XX` / `--zone` / `--project` / `--account` per the table
(**the 6 new VMs are not in one zone — use the right zone**). Passwords are in
`gc-accounts.md` (only needed for the first browser OAuth authorization).

| Node | Role | Project | Zone |
|---|---|---|---|
| l4-vm-281 | worker (former control plane, demoted 7-19) | ebim26ham-281 | europe-west4-c |
| l4-vm-288 | control plane (HA) | ebim26ham-288 | europe-west4-c |
| l4-vm-289 | control plane (HA) | ebim26ham-289 | europe-west4-c |
| l4-vm-290 | control plane (HA, primary) | ebim26ham-290 | europe-west4-c |
| l4-vm-282 | worker | ebim26ham-282 | us-central1-c |
| l4-vm-283 | worker | ebim26ham-283 | us-west4-c |
| l4-vm-284 | worker | ebim26ham-284 | europe-west4-c |
| l4-vm-285 | worker | ebim26ham-285 | us-east1-b |
| l4-vm-286 | worker | ebim26ham-286 | us-east1-b |
| l4-vm-287 | worker | ebim26ham-287 | us-west4-c |

> First connection to a new project auto-generates a local SSH key and pushes it to project
> metadata — a short extra wait is normal (see 2.1). Cluster ops only need any CP node
> (290/289/288); SSH into workers only to debug that machine.
