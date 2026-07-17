# ebim-vrb-lab

A ready-to-run, browser-based lab for the EBiM robot-manipulation tasks (Isaac Sim + MuJoCo teleoperation). No local install — everything runs in the cloud through your browser.


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


## ⚠️ Deployment notice (temporary)

This lab is currently deployed on a **Google Cloud** cluster with **10 NVIDIA L4 GPUs**. Each running lab reserves one GPU, so **at most 10 labs can run at the same time** — if all 10 are busy, you may have to wait for a slot.

The deployment is **temporary and available only until July 20, 2026**. After that date the environment will be shut down.