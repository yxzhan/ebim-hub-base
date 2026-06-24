# ebim-hub-base

Configuration for the **EBIM JupyterHub user pod**. This repo holds two things:

1. **The Docker image** for the user pod (`Dockerfile`), prebuilt and pushed manually to
   [`intel4coro/ebimhub:latest`](https://hub.docker.com/r/intel4coro/ebimhub).
2. **The home-directory files** (`.bashrc`, `env_init.sh`, `run_isaacsim.sh`) that live in
   the pod's persistent home volume and set up / launch the runtime environment.

## Why dependencies aren't installed in the Dockerfile

In this JupyterHub deployment the user's home directory (`/home/jovyan`) is backed by a
**persistent volume**. When the pod starts, that volume is mounted over `/home/jovyan`,
which **shadows / clears anything the image baked into `$HOME` at build time**. As a result,
heavy dependencies cannot be installed into the home directory from the `Dockerfile` — they
would simply disappear once the volume is mounted.

So the split is:

- **System-level tools** (things that live *outside* `$HOME`) → installed in the `Dockerfile`.
- **User-level dependencies** (things that live *inside* `$HOME`, e.g. Isaac Sim / Isaac Lab,
  Python virtualenvs) → installed **once at runtime** via [`env_init.sh`](env_init.sh) into the
  persistent home volume, where they survive pod restarts.

## Repository layout

| File                | Purpose                                                                                  |
| ------------------- | ---------------------------------------------------------------------------------------- |
| `Dockerfile`        | Builds the user pod image on top of `intel4coro/jupyter-ros2:jazzy-py3.12`.              |
| `env_init.sh`       | One-time, in-pod setup: installs uv, the Python 3.11 env, Isaac Sim and Isaac Lab.       |
| `run_isaacsim.sh`   | Launches Isaac Sim with the ROS 2 bridge configured.                                     |
| `.bashrc`           | Shell config placed in the home directory (conda hook, `code` alias, etc.).              |

## The Docker image

The image (`intel4coro/ebimhub:latest`) adds the following on top of the
[`jupyter-ros2`](https://github.com/IntEL4CoRo/jupyter-ros2) base:

- **git-lfs**
- **VirtualGL 3.1.4** (GPU-accelerated remote rendering)
- An upgraded **code-server**, plus the `git-graph`, `sysmonitor`, and
  `vscode-remote-desktop` extensions

### Build & push

The image is **prebuilt and pushed manually** (it is not built by JupyterHub):

```bash
docker build -t intel4coro/ebimhub:latest .
docker push intel4coro/ebimhub:latest
```

JupyterHub is then configured to spawn user pods from `intel4coro/ebimhub:latest`.

## First-time setup inside the pod

After a user pod starts for the first time (or after the persistent volume is reset), run the
setup script once from the home directory to populate the environment:

```bash
./env_init.sh
```

This installs [uv](https://docs.astral.sh/uv/), creates a Python 3.12 virtualenv
(`env_isaaclab`), and installs:

- `isaacsim[all,extscache]==6.0.0.1`
- `torch==2.10.0` / `torchvision==0.25.0` (CUDA 12.8)
- [Isaac Lab](https://github.com/isaac-sim/IsaacLab) (`develop` branch)
- The `isaacsim.robot_motion.dual_arm_rmp_widget` extension (linked from `DEMO/`)

Versions follow the official
[Isaac Lab pip installation guide](https://isaac-sim.github.io/IsaacLab/develop/source/setup/installation/pip_installation.html).

Because the home directory is persistent, this only needs to be done once per volume.

## Running Isaac Sim

```bash
./run_isaacsim.sh
```

This activates the `env_isaaclab` virtualenv, fixes up the environment for the Isaac Sim
ROS 2 bridge (unsets `LD_PRELOAD` / `PYTHONPATH`, sets `LD_LIBRARY_PATH`), and launches the
full Isaac Sim kit.
