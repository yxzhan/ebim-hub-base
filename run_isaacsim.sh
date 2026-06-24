#!/bin/bash

# unset virtualGL ENV (which breaks ROS2 bridge)
unset LD_PRELOAD
# Clear default ROS ENV
unset PYTHONPATH

source $PWD/env_isaaclab/bin/activate

# Isaac Sim ROS2 Bridge
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$PWD/IsaacLab/_isaac_sim/exts/isaacsim.ros2.bridge/$ROS_DISTRO/lib

isaacsim isaacsim.exp.full.kit