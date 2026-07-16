#!/usr/bin/env bash
# Copyright (c) 2026 The EBiM Benchmark Contributors
# SPDX-License-Identifier: Apache-2.0
#
# Launch the Isaac Sim 5.1.0 Task 3 room-scene teleop bridge inside the
# all-in-one container. Mirrors what task3_isaacsim/scripts/run_isaacsim_teleop.sh
# execs into the Isaac Sim container, but runs directly (single container),
# just like ebim-run-task2-scene-room does for Task 2.
#
# Extra arguments are forwarded to scene_room.py, e.g.:
#   ebim-run-task3-scene-room --headless
#   ebim-run-task3-scene-room --gripper panda
set -euo pipefail

REPO="${EBIM_REPO:-/workspace/EBiM_Challenge}"
TASK3="${REPO}/task3_isaacsim"

GRIPPER="${GRIPPER:-robotiq}"
ROBOT_USD="${ROBOT_USD:-${REPO}/task1_isaacsim/assets/Robotiq_2f_85_with_d405_mobile_fr3_duo_v0_2.usd}"
ROOM_USD="${ROOM_USD:-${REPO}/assets/robot_room.usd}"
HEAD_PLACEMENT="${HEAD_PLACEMENT:-random}"

# The bridge uses the ROS 2 jazzy libraries bundled with Isaac Sim's ros2 bridge
# extension. LD_LIBRARY_PATH must be set BEFORE the process starts, and we must
# NOT source /opt/ros/jazzy here (that is only for the apt-installed helpers).
export ROS_DISTRO=jazzy
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTDDS_BUILTIN_TRANSPORTS=UDPv4
export LD_LIBRARY_PATH="/isaac-sim/exts/isaacsim.ros2.bridge/jazzy/lib:${LD_LIBRARY_PATH:-}"
export ROS_HOME="${ROS_HOME:-/tmp/isaac_ros_home}"
export QT_X11_NO_MITSHM=1

echo "[run-task3-scene-room] gripper : ${GRIPPER}"
echo "[run-task3-scene-room] robot USD: ${ROBOT_USD}"
echo "[run-task3-scene-room] room  USD: ${ROOM_USD}"

exec /isaac-sim/python.sh "${TASK3}/scripts/scene_room.py" \
    --gripper "${GRIPPER}" \
    --robot-usd "${ROBOT_USD}" \
    --room-usd "${ROOM_USD}" \
    --head-placement "${HEAD_PLACEMENT}" \
    --franka-root "${REPO}/task1_isaacsim" \
    "$@"
