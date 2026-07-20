# ebim-vrb-lab

**ebim-vrb-lab** packages the [EBiM benchmark](https://ebim-benchmark.github.io/) simulation tasks into a ready-to-run, browser-based lab — **no local installation and no GPU of your own required.** Open a single link and you get a GPU-backed cloud session running the official EBiM environments: **Task 1** (cable-routing teleoperation in MuJoCo) and **Task 2 / Task 3** (room-scene and assisted-living teleoperation in Isaac Sim 5.1). The session bundles everything you need to work with them — a full VNC remote desktop, a browser-based ROS 2 arm-teleoperation UI, VS Code, and JupyterLab — and starts Task 3 automatically once it loads.

It runs on the AICOR **VRB** (Virtual Research Building) / BinderHub platform: each session is a self-contained container scheduled onto a pooled GPU cluster, so all the heavy simulation runs in the cloud and streams to your browser.


## Quick start

1. Open this link in your browser:

   **https://ebim-binder.aicor.dev/v2/gh/yxzhan/ebim-vrb-lab.git/main?urlpath=proxy/8899**

2. Wait for the environment to start (the first launch pulls the image and can take a few minutes; later launches are faster).
3. When it loads, you land on the **EBiM Workspace** page. **Task 3 starts automatically** once the virtual desktop is ready — give it a moment for Isaac Sim to open.

## Controlling the robot

- **Arms** — use the **ROS2 Browser** tab.
- **Mobile base** — use the keyboard pane in the task's terminal: `w`/`a`/`s`/`d` to drive, `q`/`e` to turn. Keep that terminal focused while driving.

## Running the tasks

All tasks live on the **Desktop** tab. Start one by **double-clicking its desktop icon**, or by running its command in a desktop terminal.

| Task | Desktop icon | Terminal command |
|------|--------------|------------------|
| **Task 1** — Cable-routing teleop (MuJoCo) | `EBIM-Task1-mujoco` | `vglrun /workspace/EBiM_Challenge/task1_mujoco/start.sh` |
| **Task 2** — Room-scene teleop (Isaac Sim) | `EBIM-Task2` | `tmux new-session 'ebim-run-task2-scene-room' \; split-window -h 'ebim-keyboard'` |
| **Task 3** — Assisted living / feeding (Isaac Sim) | `EBIM-Task3` | `tmux new-session 'ebim-run-task3-scene-room' \; split-window -h 'ebim-keyboard'` |


Notes:
- **Task 3 is already running** when you arrive. To restart it, or to switch tasks, close its window and launch another from the Desktop tab.
- For Task 2 and Task 3, the desktop icon opens a split terminal: the simulator on one side and the keyboard base-driver (`ebim-keyboard`) on the other. Running the command manually starts only the simulator; run `ebim-keyboard` in a second terminal if you also want keyboard base control.
- Only run one Isaac Sim task at a time — each one uses the single GPU assigned to your lab.

## The EBiM Workspace

The workspace is a single page with a tab bar at the top. Each tab embeds one tool; the little **↗** on a tab opens it in its own browser tab.

| Tab | What it is |
|-----|------------|
| **Desktop** | The virtual (noVNC) desktop. This is where the simulator windows appear and where the task launcher icons live. **Task 3 auto-starts here.** |
| **ROS2 Browser** | The browser-based arm teleoperation UI (served on port 8090). Use it to control the robot arms. |
| **VS Code** | VS Code in the browser, opened at `/workspace/EBiM_Challenge`, for reading/editing code. |
| **JupyterLab** | A full JupyterLab session. |


## Demo

A short walkthrough — launching the lab in the browser, Task 3 (Isaac Sim) auto-starting, and controlling the robot arms:

<!-- VIDEO PLACEHOLDER — embed the demo recording here (drag the mp4 into the README editor, or use a <video> tag) -->

https://github.com/user-attachments/assets/34a5de4e-26ec-4559-875b-f3efa1857552


## Stress test

Load-tested by launching **20 lab sessions concurrently** (each auto-starting the Task 3 Isaac Sim scene):

- **20 / 20** launches succeeded, scheduler placing **exactly 2 sessions per L4** across all 10 nodes;
- pod start-up **median 13.7 s** (range 11–20 s); Task 3 scene ready in ~60 s;
- end-to-end VNC-transport round-trip **~20–24 ms** for EU clients (feels local).

<!-- VIDEO PLACEHOLDER — embed the stress-test recording here -->


https://github.com/user-attachments/assets/be6c1dfd-fed6-4fdd-92a3-e5aea390db37



## Infrastructure & hardware

This lab runs on the AICOR VRB / BinderHub stack. The current testbed is a **Google Cloud** cluster of **10 GPU VMs**, pooled from 10 separate GCP projects into a single MicroK8s cluster over a WireGuard mesh:

| | |
|---|---|
| **GPU** | NVIDIA **L4** (24 GB), 1 per VM — **GPU time-sliced 2 shares/card → 20 session slots** |
| **VM** | `g2-standard-32` (32 vCPU / 128 GB RAM), 200 GB disk |
| **Nodes** | 10 × L4 (5 in EU `europe-west4-c`, 5 in the US) |
| **Orchestration** | MicroK8s + NVIDIA GPU Operator; Cloudflare Tunnel ingress (HTTPS) |
| **Environment** | single Docker image: Isaac Sim 5.1 + MuJoCo + VNC desktop + VS Code + JupyterLab |

The full build — from VM creation through drivers, the WireGuard mesh, MicroK8s, BinderHub, Cloudflare ingress, cache pre-warming and an HA control-plane migration — is documented step by step, along with the automation scripts and Kubernetes manifests.

## ⚠️ Deployment notice (temporary)

This lab is currently deployed on the **Google Cloud** cluster described above (**10 NVIDIA L4 GPUs**, time-sliced into **20 session slots**). If all slots are busy, you may have to wait for one to free up.

The deployment is **temporary and available only until July 20, 2026**. After that date the environment will be shut down.
