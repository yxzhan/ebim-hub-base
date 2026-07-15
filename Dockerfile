# syntax=docker/dockerfile:1.7
# ---------------------------------------------------------------------------
# All-in-one Task 2 image (Mobile FR3 Duo teleoperation, Isaac Sim 5.1.0 / PhysX)
#
# Collapses the 5-container helper stack into a SINGLE container:
#   * Isaac Sim 5.1.0 simulator (scene_room.py bridge)          [bundled jazzy]
#   * ros_joint_republisher    (/bridge/* -> /isaac/*)          [apt jazzy]
#   * joint_position_controller (holds arm/gripper joints)      [apt jazzy]
#   * keyboard_to_base adapter (/keyboard/state -> /pedal/state)[apt jazzy]
#   * browser_controller web UI (arms/grippers, :8090)          [apt jazzy]
#   * keyboard_state_publisher  (base w/a/s/d/q/e device node)  [apt jazzy]
#
# Isaac Sim 5.1.0's base image is Ubuntu 24.04 (noble), so ROS 2 jazzy is the
# native distro and installs cleanly via apt. The Isaac Sim bridge keeps using
# the jazzy libraries bundled with its isaacsim.ros2.bridge extension (it never
# sources /opt/ros/jazzy), so the apt ROS install sits alongside without
# conflict -- the same isolation the multi-container stack already relies on.
#
# Contents baked into the image:
#   * benchmark repo (local copy, incl. submodules + assets) -> /workspace/EBiM_Challenge
#   * teleoperation repo (keyboard packages only)            -> /workspace/teleoperation
#   * all-in-one helper scripts                               -> /workspace/EBiM_Challenge
#
# Build (from THIS repo root). The benchmark and (private) teleoperation repos
# are copied from local checkouts passed as named build contexts:
#   DOCKER_BUILDKIT=1 docker build \
#     --build-context benchmark=../benchmark \
#     --build-context teleoperation=../teleoperation \
#     -t ebim-hub-base:latest .
# ---------------------------------------------------------------------------
ARG ISAAC_SIM_IMAGE=nvcr.io/nvidia/isaac-sim:5.1.0
FROM ${ISAAC_SIM_IMAGE}

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
USER root

# Isaac Sim runs as root here (OMNI_KIT_ALLOW_ROOT=1); this sidesteps the host
# cache-directory permission problem that breaks the multi-container setup.
ENV ACCEPT_EULA=Y \
    PRIVACY_CONSENT=Y \
    OMNI_KIT_ALLOW_ROOT=1 \
    ROS_DISTRO=jazzy \
    RMW_IMPLEMENTATION=rmw_fastrtps_cpp \
    FASTDDS_BUILTIN_TRANSPORTS=UDPv4

# ---------------------------------------------------------------------------
# 1. Runtime prereqs (from docker/Dockerfile.runtime) + ROS 2 apt repository.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        libdbus-1-3 \
        curl \
        gnupg2 \
        ca-certificates \
        locales \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu noble main" \
        > /etc/apt/sources.list.d/ros2.list \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 2. ROS 2 jazzy (helper nodes, browser UI, keyboard workspace) + colcon.
#    ros-base already provides rclpy/std_msgs/sensor_msgs; geometry_msgs is
#    the only extra message package the browser_controller needs.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-jazzy-ros-base \
        ros-jazzy-geometry-msgs \
        python3-colcon-common-extensions \
        python3-argcomplete \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8


ENV DISPLAY=:1.0

RUN apt-get update && \
    apt-get install -y git git-lfs && \
    git lfs install

RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo git curl vim ca-certificates tmux \
    xfce4 xfce4-terminal \
    xubuntu-icon-theme \
    tigervnc-standalone-server \
    dbus-x11 \
     # Disable the automatic screenlock since the account password is unknown
    && apt-get -y -qq remove xfce4-screensaver \
    && rm -rf /var/lib/apt/lists/*

# Install VirtualGL
RUN apt update && apt install -y wget
RUN wget https://github.com/VirtualGL/virtualgl/releases/download/3.1.4/virtualgl_3.1.4_amd64.deb && \
    apt install -y ./virtualgl_3.1.4_amd64.deb && \
    rm virtualgl_3.1.4_amd64.deb
                
RUN curl -fsSL https://code-server.dev/install.sh | sh
RUN code-server --install-extension ms-python.python
RUN code-server --install-extension ms-toolsai.jupyter
RUN code-server --install-extension mhutchie.git-graph
RUN code-server --install-extension lichenxi.sysmonitor
RUN curl -LO https://github.com/yxzhan/vscode_remote_desktop/releases/download/v0.1.0/vscode-remote-desktop-0.1.0.vsix && \
    code-server --install-extension vscode-remote-desktop-0.1.0.vsix && \
    rm vscode-remote-desktop-0.1.0.vsix

# UV (Python package manager) + Python
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"
RUN uv venv /opt/venv --python 3.12
ENV VIRTUAL_ENV=/opt/venv \
    PATH="/opt/venv/bin:$PATH"

# Make pip/pip3 delegate to uv pip
RUN printf '#!/bin/sh\nexec uv pip "$@"\n' > /usr/local/bin/pip \
    && chmod +x /usr/local/bin/pip \
    && ln -s /usr/local/bin/pip /usr/local/bin/pip3

# Install python env
RUN pip install \
    numpy \
    jupyterhub \
    jupyterlab \
    jupyter-server-proxy \
    jupyter-remote-desktop-proxy \
    git+https://github.com/yxzhan/jupyter-code-server.git

# ---------------------------------------------------------------------------
# 3. WORKSPACE_ROOT holds the benchmark repo, copied from a local checkout in
#    the binder section below; the all-in-one helper scripts are copied in
#    right after it.
# ---------------------------------------------------------------------------
ARG WORKSPACE_ROOT=/workspace

# ---------------------------------------------------------------------------
# 4. Bake the teleoperation repo and build a KEYBOARD-ONLY colcon workspace.
#    Only keyboard_state_publisher/_subscriber are built (pure rclpy + std_msgs);
#    GELLO and USB foot-pedal packages are deliberately excluded.
# ---------------------------------------------------------------------------
COPY --from=teleoperation . /workspace/teleoperation
RUN mkdir -p /workspace/ros_ws \
    && ln -s /workspace/teleoperation/src /workspace/ros_ws/src \
    && cd /workspace/ros_ws \
    && source /opt/ros/jazzy/setup.bash \
    && colcon build --symlink-install \
        --packages-select keyboard_state_publisher keyboard_state_subscriber

WORKDIR ${WORKSPACE_ROOT}/EBiM_Challenge
ENV EBIM_REPO=${WORKSPACE_ROOT}/EBiM_Challenge


# Copy the benchmark repo (with submodules + already-downloaded large assets)
# straight from a local checkout, supplied as a named build context:
#   docker build --build-context benchmark=../benchmark ...
# The benchmark repo's own .dockerignore (drops .git/docs/caches) applies here.
WORKDIR ${EBIM_REPO}
COPY --from=benchmark . ${EBIM_REPO}

# ---------------------------------------------------------------------------
# All-in-one helper launchers. These scripts live at the root of THIS image
# repo (the build context); copy them under WORKSPACE_ROOT (after the benchmark
# copy) and expose them on PATH as ebim-* commands.
# ---------------------------------------------------------------------------

COPY --chmod=755 start-helpers.sh run-scene-room.sh run-keyboard.sh ${WORKSPACE_ROOT}/
RUN ln -sf ${WORKSPACE_ROOT}/start-helpers.sh   /usr/local/bin/ebim-start-helpers \
    && ln -sf ${WORKSPACE_ROOT}/run-scene-room.sh /usr/local/bin/ebim-run-scene-room \
    && ln -sf ${WORKSPACE_ROOT}/run-keyboard.sh   /usr/local/bin/ebim-keyboard


COPY ./entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]