# GC deployment — scripts & Kubernetes configs

The automation scripts and Kubernetes manifests used to build the EBiM cloud testbed on
Google Cloud (10 GPU VMs across 10 projects → one MicroK8s cluster over a WireGuard mesh,
running BinderHub). The full narrative — what each step does, gotchas, and verification —
is in **[`deployment-log.md`](./deployment-log.md)** (this directory).

> ⚠️ **Sanitized for a public repo.** GCP account emails, static external IPs, and
> WireGuard public keys have been replaced with placeholders (`<account-28x>`,
> `<static-ip-28x>`, `<wg-pubkey-28x>`). **The scripts will not run as-is** — fill the
> config arrays at the top of each script with real values first. Real credentials live
> only in the private `gc-accounts.md` (never committed).
>
> **Not included** (secrets / upstream): `secret.yaml` (real Docker Hub token — create it
> locally, never commit), and the upstream `binder.yaml` / chart values, which come from
> [IntEL4CoRo/binder.intel4coro.de-deploy](https://github.com/IntEL4CoRo/binder.intel4coro.de-deploy).

## Shell scripts

| Script | Deployment-log step | What it does |
|---|---|---|
| `create_vms.sh` | 1.4 | Create the first 4 GPU VMs (one per project), auto-retry zones on capacity/quota |
| `install_gpu_drivers.sh` | 2 | Install NVIDIA drivers on the first 4 VMs (parallel), reboot, verify `nvidia-smi` |
| `setup_docker_wireguard.sh` | 3.3 | Install Docker + WireGuard; build the full-mesh encrypted overlay |
| `setup_microk8s_cluster.sh` | 3.4 | Install MicroK8s; bind components to WireGuard IPs; form the 4-node cluster |
| `create_vms_batch2.sh` | 10.1 | Create the 6 scale-out VMs (projects 282–287) |
| `install_gpu_drivers_batch2.sh` | 10.2 | NVIDIA drivers on the 6 new VMs (per-VM zones) |
| `setup_wireguard_expand.sh` | 10.4 | Expand the mesh 4 → 10 nodes with **zero downtime** (`wg syncconf`, no interface bounce) |
| `setup_microk8s_expand.sh` | 10.5 | Join the 6 new nodes as workers |
| `run_isaac_warmup.sh` | 11 | Run the per-node Isaac Sim shader-cache warmup Jobs and poll to completion |

## Kubernetes manifests

| Manifest | Deployment-log step | What it is |
|---|---|---|
| `values-gc-overrides.yaml` | 4 → 16 | The central Helm overrides for the GC environment (ClusterIP services, `--allow-root`, Isaac cache hostPath, VGL_DISPLAY, cull policy, custom-UI initContainer, node pinning) |
| `image-prepuller-gc.yaml` | 6 | DaemonSet that pre-pulls the lab image into every node's containerd cache |
| `isaac-warmup-gc.yaml` | 11 | One-shot Job template (per node) that pre-fills the Isaac Sim shader cache and releases the GPU |
| `time-slicing-config-gc.yaml` | 15 | GPU time-slicing config — 2 shares per L4 (concurrency 10 → 20) |

## Related

- Full deployment narrative: [`deployment-log.md`](./deployment-log.md)
- Technical report: [`../docs/infrastructure-report.md`](../docs/infrastructure-report.md)
- Stress-test results: [`../docs/stress-test-results.md`](../docs/stress-test-results.md)
