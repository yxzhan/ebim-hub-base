FROM intel4coro/ebim-hub-base:latest

ARG WORKSPACE_ROOT=/workspace

ENV SHELL=/bin/bash

ARG EBIM_REPO_URL=https://github.com/EBiM-Benchmark/benchmark.git

# TEMP FIX: the base image baked /workspace/EBiM_Challenge via COPY, which the
# repo's .dockerignore stripped of .git — so it was not a git repo and could not
# be updated. Re-create it as a real, normal clone (proper .git for future
# `git pull`), pulling submodules and Git-LFS content the usual way.
#
# task1_isaacsim carries large, git-ignored downloaded assets that only exist in
# the old baked copy, so drop the freshly cloned task1_isaacsim and replace it
# wholesale with the old directory.
RUN cd ${WORKSPACE_ROOT} \
    && mv EBiM_Challenge EBiM_Challenge.orig \
    && git clone --recurse-submodules "${EBIM_REPO_URL}" EBiM_Challenge \
    && git -C EBiM_Challenge checkout cb5184574f33611f943ff42aae461678ccb538e9 \
    && git -C EBiM_Challenge submodule update --init --recursive \
    && rm -rf EBiM_Challenge/task1_isaacsim \
    && cp -a EBiM_Challenge.orig/task1_isaacsim EBiM_Challenge/ 

# Pre-install Miniconda at build time (task1_mujoco/start.sh would otherwise do
# this on first launch). On newer conda, `conda env create` shows an interactive
# Anaconda Terms-of-Service prompt (the "(a)ccept/(r)eject/(v)iew" prompt where
# the user types "a") — that cannot be answered inside a container desktop, so
# we accept the ToS non-interactively here.
#
# CONDA_PLUGINS_AUTO_ACCEPT_TOS also auto-accepts at runtime, covering the first-
# run `conda env create` no matter which user launches it.
#
# Installed under /root (= the container's $HOME) so start.sh's own fallback loop
# ("$HOME/miniconda3/bin/conda") finds it. Deliberately NOT put on the global
# PATH and NOT `conda init`'d, so conda's base python does not shadow the system
# python3 that the ROS 2 helpers rely on.
ENV CONDA_PLUGINS_AUTO_ACCEPT_TOS=yes

ARG MINICONDA_URL=https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
RUN wget -qO /tmp/miniconda.sh "${MINICONDA_URL}" \
    && bash /tmp/miniconda.sh -b -p /root/miniconda3 \
    && rm -f /tmp/miniconda.sh \
    && /root/miniconda3/bin/conda tos accept --override-channels \
         --channel https://repo.anaconda.com/pkgs/main \
         --channel https://repo.anaconda.com/pkgs/r

# Pre-create the task1_mujoco conda env ("duo-teleop") from its environment.yml
# so the first launch of the mujoco task (start.sh -> start.py) skips the
# multi-minute `conda env create` (and its pip installs of mujoco/pygame/...).
# start.py detects the existing env via `conda env list` and jumps straight to
# `conda run -n duo-teleop python main.py`. `conda clean` trims the pkg cache to
# keep the image smaller.
RUN /root/miniconda3/bin/conda env create -f \
      ${WORKSPACE_ROOT}/EBiM_Challenge/task1_mujoco/robotiq_duo_full_scene_minimal_core/environment.yml \
    && /root/miniconda3/bin/conda clean -a -y

COPY container/scripts/start-helpers.sh container/scripts/run-task2-scene-room.sh \
     container/scripts/run-keyboard.sh container/scripts/run-task3-scene-room.sh \
     container/scripts/run-task3-session.sh container/scripts/autostart-task3.sh \
     ${WORKSPACE_ROOT}/

RUN chmod +x ${WORKSPACE_ROOT}/start-helpers.sh \
    ${WORKSPACE_ROOT}/run-task2-scene-room.sh \
    ${WORKSPACE_ROOT}/run-keyboard.sh \
    ${WORKSPACE_ROOT}/run-task3-scene-room.sh \
    ${WORKSPACE_ROOT}/run-task3-session.sh \
    ${WORKSPACE_ROOT}/autostart-task3.sh \
    && ln -sf ${WORKSPACE_ROOT}/start-helpers.sh /usr/local/bin/ebim-start-helpers \
    && ln -sf ${WORKSPACE_ROOT}/run-task2-scene-room.sh /usr/local/bin/ebim-run-task2-scene-room \
    && ln -sf ${WORKSPACE_ROOT}/run-task3-scene-room.sh /usr/local/bin/ebim-run-task3-scene-room \
    && ln -sf ${WORKSPACE_ROOT}/run-task3-session.sh /usr/local/bin/ebim-run-task3-session \
    && ln -sf ${WORKSPACE_ROOT}/run-keyboard.sh /usr/local/bin/ebim-keyboard

COPY container/desktop/EBIM-Task1-mujoco.desktop container/desktop/EBIM-Task2.desktop \
     container/desktop/EBIM-Task3.desktop /root/Desktop/

# XDG autostart: run Task 3 automatically when the desktop session (display)
# comes up. Remove this file to disable auto-start.
RUN mkdir -p /root/.config/autostart
COPY container/desktop/EBIM-Task3-autostart.desktop /root/.config/autostart/

COPY container/scripts/entrypoint.sh /entrypoint.sh

ENV CODE_WORKING_DIRECTORY=/workspace/EBiM_Challenge/

# Launcher page, served by a background http.server in entrypoint.sh and reached
# via jupyter-server-proxy at /user/<name>/proxy/8899/
COPY container/web/workspace.html ${WORKSPACE_ROOT}/.launcher/index.html
# Stress-test page, same server, reached at /user/<name>/proxy/8899/stress-test.html
COPY container/web/stress-test.html ${WORKSPACE_ROOT}/.launcher/stress-test.html

# Patch the Task 1 (Isaac Sim) browser-controller static assets: overlay our
# versions onto the cloned EBiM_Challenge repo (must run after the clone above),
# overwriting the upstream index.html / monitor.html / topology.html.
COPY container/browser_control_patch/static/ \
     ${WORKSPACE_ROOT}/EBiM_Challenge/task1_isaacsim/services/browser_controller/static/

RUN chmod +x /root/Desktop/EBIM-Task1-mujoco.desktop \
    /root/Desktop/EBIM-Task2.desktop \
    /root/Desktop/EBIM-Task3.desktop \
    /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]