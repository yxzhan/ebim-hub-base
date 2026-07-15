#!/usr/bin/env bash
# Copyright (c) 2026 The EBiM Benchmark Contributors
# SPDX-License-Identifier: Apache-2.0
#
# Start the background ROS 2 jazzy helper roles inside the all-in-one container.
# Equivalent to the task2_ros_republisher / task2_position_controller /
# task2_teleop_adapters / task2_browser_controller containers, but as four
# background processes in one container.
#
# Keyboard base teleop + browser arm UI (the `--scene room --with-keyboard-teleop`
# flow). Logs go to /tmp/ebim-*.log.
# NOTE: no `-u` — ROS 2's setup.bash references unbound vars (AMENT_TRACE_SETUP_FILES).
set -eo pipefail

source /opt/ros/jazzy/setup.bash

REPO="${EBIM_REPO:-/workspace/EBiM_Challenge}"
TASK1="${REPO}/task1_isaacsim"
export PYTHONPATH="${TASK1}/services/browser_controller:${TASK1}/services:${TASK1}/scripts:${PYTHONPATH:-}"
export ROS_DISTRO=jazzy
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTDDS_BUILTIN_TRANSPORTS=UDPv4

# Gripper open/closed calibration (matches task2_isaacsim/.env.example defaults).
GRIPPER_OPEN="${REPUBLISHER_GRIPPER_OPEN_POSITION:-0.0}"
GRIPPER_CLOSED="${REPUBLISHER_GRIPPER_CLOSED_POSITION:-0.8}"

log() { echo "[start-helpers] $*"; }

log "ros_joint_republisher ..."
nohup python3 "${TASK1}/scripts/controllers/ros_joint_republisher.py" \
    --bridge-prefix /bridge --isaac-prefix /isaac \
    --gripper-open-position "${GRIPPER_OPEN}" \
    --gripper-closed-position "${GRIPPER_CLOSED}" \
    >/tmp/ebim-republisher.log 2>&1 &

log "joint_position_controller ..."
nohup python3 "${TASK1}/scripts/controllers/joint_position_controller.py" \
    >/tmp/ebim-position.log 2>&1 &

log "keyboard_to_base adapter ..."
nohup python3 "${TASK1}/scripts/adapters/keyboard_to_base.py" \
    >/tmp/ebim-keyboard-adapter.log 2>&1 &

log "browser_controller (http://localhost:8090) ..."
nohup python3 "${TASK1}/services/browser_controller/app.py" \
    --host 0.0.0.0 --port 8090 --publish-rate 60.0 \
    >/tmp/ebim-browser.log 2>&1 &

sleep 1
log "helpers started. Logs:"
log "  /tmp/ebim-republisher.log"
log "  /tmp/ebim-position.log"
log "  /tmp/ebim-keyboard-adapter.log"
log "  /tmp/ebim-browser.log"
log "browser arm UI: http://localhost:8090"
