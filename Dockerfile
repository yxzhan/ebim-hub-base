FROM intel4coro/ebim-hub-base:latest

ARG WORKSPACE_ROOT=/workspace

ENV SHELL=/bin/bash

ARG EBIM_REPO_URL=https://github.com/EBiM-Benchmark/benchmark.git

# TEMP FIX: the base image baked /workspace/EBiM_Challenge via COPY, which the
# repo's .dockerignore stripped of .git — so it was not a git repo and could not
# be updated. Re-create it as a real clone (proper .git for future `git pull`),
# then carry over the git-ignored, already-downloaded assets that only exist in
# the old baked copy:
#   - cp -an: fill in the git-ignored Task 1 large assets WITHOUT clobbering the
#     freshly cloned latest source (-n = never overwrite existing files).
#   - GIT_LFS_SKIP_SMUDGE=1: clone without needing git-lfs; the clone leaves only
#     an LFS pointer for assets/robot_room.usd, so restore the real file (cp -f)
#     from the old baked copy.
RUN cd ${WORKSPACE_ROOT} \
    && mv EBiM_Challenge EBiM_Challenge.orig \
    && GIT_LFS_SKIP_SMUDGE=1 git clone "${EBIM_REPO_URL}" EBiM_Challenge \
    && cp -an EBiM_Challenge.orig/task1_isaacsim/. EBiM_Challenge/task1_isaacsim/ \
    && cp -f EBiM_Challenge.orig/assets/robot_room.usd EBiM_Challenge/assets/robot_room.usd \
    && rm -rf EBiM_Challenge.orig

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

COPY start-helpers.sh run-task2-scene-room.sh run-keyboard.sh run-task3-scene-room.sh ${WORKSPACE_ROOT}/

RUN chmod +x ${WORKSPACE_ROOT}/start-helpers.sh \
    ${WORKSPACE_ROOT}/run-task2-scene-room.sh \
    ${WORKSPACE_ROOT}/run-keyboard.sh \
    ${WORKSPACE_ROOT}/run-task3-scene-room.sh \
    && ln -sf ${WORKSPACE_ROOT}/start-helpers.sh /usr/local/bin/ebim-start-helpers \
    && ln -sf ${WORKSPACE_ROOT}/run-task2-scene-room.sh /usr/local/bin/ebim-run-task2-scene-room \
    && ln -sf ${WORKSPACE_ROOT}/run-task3-scene-room.sh /usr/local/bin/ebim-run-task3-scene-room \
    && ln -sf ${WORKSPACE_ROOT}/run-keyboard.sh /usr/local/bin/ebim-keyboard

COPY EBIM-Task2.desktop EBIM-Task3.desktop /root/Desktop/
COPY ./entrypoint.sh /entrypoint.sh

# Launcher page, served by a background http.server in entrypoint.sh and reached
# via jupyter-server-proxy at /user/<name>/proxy/8899/
COPY workspace.html ${WORKSPACE_ROOT}/.launcher/index.html

RUN chmod +x /root/Desktop/EBIM-Task2.desktop \
    /root/Desktop/EBIM-Task3.desktop \
    /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]