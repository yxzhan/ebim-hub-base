# Task 2 — All-in-one container (Isaac Sim 5.1.0 + ROS 2 jazzy helpers + keyboard teleop)

This directory builds a **single** Docker image that runs the entire Task 2
`--scene room --with-keyboard-teleop` simulation that normally spans **5
containers**:

| Role (multi-container name)      | In the all-in-one container                     | ROS runtime          |
| -------------------------------- | ----------------------------------------------- | -------------------- |
| `isaac-sim-5-1-0-workshop`       | `scene_room.py` bridge (`ebim-run-scene-room`)  | Isaac bundled jazzy  |
| `task2_ros_republisher`          | `ros_joint_republisher.py`  (background)        | apt `ros-jazzy`      |
| `task2_position_controller`      | `joint_position_controller.py` (background)     | apt `ros-jazzy`      |
| `task2_teleop_adapters`          | `keyboard_to_base.py` adapter (background)      | apt `ros-jazzy`      |
| `task2_browser_controller`       | browser arm UI on `:8090` (background)          | apt `ros-jazzy`      |
| device publisher (host, `teleoperation` repo) | `keyboard_state_publisher` (`ebim-keyboard`) | apt `ros-jazzy` (baked `ros_ws`) |

Both repositories are **baked into the image**:

- the benchmark repo (this repo, including the USD assets you already
  downloaded) at `/workspace/EBiM_Challenge`;
- the `EBiM-Benchmark/teleoperation` repo at `/workspace/teleoperation`, with a
  **keyboard-only** colcon workspace built at `/workspace/ros_ws`
  (`keyboard_state_publisher` + `keyboard_state_subscriber`; GELLO and USB
  foot-pedal packages are excluded).

> **Why it works in one container:** Isaac Sim 5.1.0's base image is Ubuntu
> 24.04 (noble), so ROS 2 jazzy installs natively via apt. The Isaac Sim bridge
> keeps using the jazzy libraries bundled with its `isaacsim.ros2.bridge`
> extension and never sources `/opt/ros/jazzy`, so the apt ROS install coexists
> with it. All processes talk over localhost/shared-memory DDS inside the
> container. Isaac Sim runs as **root**, so the host cache-permission error that
> breaks the multi-container setup does not occur.

## Prerequisites

- Linux host with an NVIDIA GPU + recent driver and the **NVIDIA Container
  Toolkit** (Isaac Sim 5.1.0 and the Task 2 thermal-pad PhysX GPU deformables
  require a GPU).
- The `benchmark` and `teleoperation` repos checked out next to this repo
  (sibling directories); the build reads them at `../benchmark` and
  `../teleoperation` via named build contexts.
- The large USD assets already downloaded into the local `benchmark` checkout
  (`task1_isaacsim/scripts/download_large_assets.sh` + `assets/`), since the
  build copies the checkout as-is — nothing is downloaded at build time.

## Build

Run from **this repo's root** (the build context). The `benchmark` and
(private) `teleoperation` repos are copied from local checkouts passed as named
build contexts:

```bash
cd /srv/binder.intel4coro.de/dev-tools/ebim-hub-base

DOCKER_BUILDKIT=1 docker build \
  --build-context benchmark=../benchmark \
  --build-context teleoperation=../teleoperation \
  -t intel4coro/ebim-hub-base:latest \
  .
```

> The build copies the local `benchmark` checkout (submodules + already-
> downloaded USD assets are taken as-is; its `.dockerignore` drops `.git`,
> `docs/`, caches), then pulls the Isaac Sim 5.1.0 base image and installs ROS 2
> jazzy plus the VNC / code-server layer — so expect it to take a while and
> produce a large image.

## Run

The image ships a VNC desktop + code-server for JupyterHub use, but for a quick
local test you can still run Isaac Sim's Kit GUI on your host X display. Allow
the container (running as root) to reach your X server, then start it with GPU +
host networking + X11 passthrough. The trailing `bash` is required — the image's
entrypoint just `exec`s its arguments, and `-e DISPLAY` overrides the image's
default `:1.0` (its internal VNC display):

```bash
export DISPLAY=${DISPLAY:-:0}
export XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}
touch "$XAUTHORITY"
xhost +local:root

docker run --rm -it \
  --name ebim-hub-base \
  --gpus all \
  --network host \
  -e DISPLAY="$DISPLAY" \
  -e XAUTHORITY="$XAUTHORITY" \
  -e QT_X11_NO_MITSHM=1 \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$XAUTHORITY:$XAUTHORITY" \
  intel4coro/ebim-hub-base:latest bash
```

This drops you into a `bash` shell inside the container. Now run the three
pieces (the helper roles, the simulator, and the keyboard base publisher).

### 1. Start the background helper roles

In the shell you just got (call it **Terminal A**):

```bash
ebim-start-helpers
```

This launches the republisher, position controller, keyboard→base adapter, and
the browser arm UI (`http://localhost:8090`). Logs are written to
`/tmp/ebim-*.log`.

### 2. Start Isaac Sim (the room scene)

In the same Terminal A (or a new one, see below):

```bash
ebim-run-scene-room
```

The Kit window appears on your host display and starts publishing the
`/isaac/*` topics and the Task 2 eval camera. Add `--headless` to run without a
visible window: `ebim-run-scene-room --headless`.

### 3. Drive the base with the keyboard

Open another shell into the running container:

```bash
docker exec -it ebim-hub-base bash
```

Then start the keyboard publisher and drive the base with `w/a/s/d` and rotate
with `q/e`. **This terminal must stay focused** for the keys to register:

```bash
ebim-keyboard
```

### 4. Arms and spine

- **Arms/grippers:** open the browser UI at <http://localhost:8090> and control
  the joints with the sliders (no hardware needed).
- **Spine:** `Up`/`Down` keys with the **Isaac Sim Kit window** focused.

## Manual equivalents

If you prefer to run things by hand instead of the `ebim-*` launchers, each
wraps a plain command:

```bash
# helpers (each in its own shell, or backgrounded) — first: source /opt/ros/jazzy/setup.bash
python3 /workspace/EBiM_Challenge/task1_isaacsim/scripts/controllers/ros_joint_republisher.py \
  --bridge-prefix /bridge --isaac-prefix /isaac \
  --gripper-open-position 0.0 --gripper-closed-position 0.8
python3 /workspace/EBiM_Challenge/task1_isaacsim/scripts/controllers/joint_position_controller.py
python3 /workspace/EBiM_Challenge/task1_isaacsim/scripts/adapters/keyboard_to_base.py
python3 /workspace/EBiM_Challenge/task1_isaacsim/services/browser_controller/app.py \
  --host 0.0.0.0 --port 8090 --publish-rate 60.0

# keyboard publisher — first: source /opt/ros/jazzy/setup.bash && source /workspace/ros_ws/install/setup.bash
ros2 run keyboard_state_publisher keyboard_state_publisher
```

The Isaac Sim command is exactly what `ebim-run-scene-room` runs; see
`run-scene-room.sh` for the required environment (bundled-jazzy
`LD_LIBRARY_PATH`, `ROS_HOME`, etc.).

## Notes

- **GPU is mandatory.** Without `--gpus all` and the NVIDIA runtime, Isaac Sim
  and the thermal-pad PhysX GPU deformables will not run.
- **Shader cache:** the image has no persistent Omniverse cache, so the first
  Isaac Sim launch recompiles shaders and is slow. For repeated runs you can
  bind-mount a host cache dir onto `/isaac-sim/kit/cache` and
  `/root/.cache/ov`.
- **Ports:** `--network host` exposes the browser UI on host `:8090`. If you
  don't want host networking, drop it and add `-p 8090:8090` instead (all
  in-container DDS still works over localhost).
- **One helper stack at a time:** don't also run the multi-container Task 1/2
  helper stacks against the same host network — they bind the same topics and
  port 8090.
- **JupyterHub / VNC:** this image already bundles the VNC desktop, code-server,
  and JupyterHub/JupyterLab layer (see the lower half of the `Dockerfile`). The
  host-X11 `docker run` above is only a quick local smoke test of the sim; under
  JupyterHub the same `ebim-*` commands run inside the container's VNC desktop.
```
