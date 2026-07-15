#!/usr/bin/env bash
# Copyright (c) 2026 The EBiM Benchmark Contributors
# SPDX-License-Identifier: Apache-2.0
#
# Run the teleoperation keyboard base publisher (from the baked keyboard-only
# ros_ws). Reads w/a/s/d/q/e from THIS terminal (needs an interactive tty) and
# publishes /keyboard/state, which the keyboard_to_base adapter turns into base
# driving commands. Keep this terminal focused while driving the base.
# NOTE: no `-u` — ROS 2's setup.bash references unbound vars (AMENT_TRACE_SETUP_FILES).
set -eo pipefail

source /opt/ros/jazzy/setup.bash
source /workspace/ros_ws/install/setup.bash

export ROS_DISTRO=jazzy
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTDDS_BUILTIN_TRANSPORTS=UDPv4

exec ros2 run keyboard_state_publisher keyboard_state_publisher
