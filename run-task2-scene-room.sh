#!/usr/bin/env bash
# Copyright (c) 2026 The EBiM Benchmark Contributors
# SPDX-License-Identifier: Apache-2.0
#
# Launch the Isaac Sim 5.1.0 Task 2 room-scene teleop bridge inside the
# all-in-one container. Mirrors what run_isaacsim_teleop.sh execs into the
# Isaac Sim container for `--scene room`, but runs directly (single container).
#
# Extra arguments are forwarded to scene_room.py, e.g.:
#   ebim-run-task2-scene-room --headless
set -euo pipefail

REPO="${EBIM_REPO:-/workspace/EBiM_Challenge}"
TASK2="${REPO}/task2_isaacsim"

ROBOT_USD="${ROBOT_USD:-${REPO}/task1_isaacsim/assets/Robotiq_2f_85_with_d405_mobile_fr3_duo_v0_2.usd}"
ROOM_USD="${ROOM_USD:-${REPO}/assets/robot_room.usd}"
EMBODIMENT="${EMBODIMENT:-fr3duo_mobile}"

# The bridge uses the ROS 2 jazzy libraries bundled with Isaac Sim's ros2 bridge
# extension. LD_LIBRARY_PATH must be set BEFORE the process starts, and we must
# NOT source /opt/ros/jazzy here (that is only for the apt-installed helpers).
export ROS_DISTRO=jazzy
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTDDS_BUILTIN_TRANSPORTS=UDPv4
export LD_LIBRARY_PATH="/isaac-sim/exts/isaacsim.ros2.bridge/jazzy/lib:${LD_LIBRARY_PATH:-}"
export ROS_HOME="${ROS_HOME:-/tmp/isaac_ros_home}"
export QT_X11_NO_MITSHM=1

echo "[run-task2-scene-room] robot USD: ${ROBOT_USD}"
echo "[run-task2-scene-room] room  USD: ${ROOM_USD}"

exec /isaac-sim/python.sh "${TASK2}/scripts/scene_room.py" \
    --robot-usd "${ROBOT_USD}" \
    --room-usd "${ROOM_USD}" \
    --task task2 \
    --embodiment "${EMBODIMENT}" \
    --franka-root "${REPO}/task1_isaacsim" \
    "$@"
