#!/bin/bash

# unset virtualGL ENV (which breaks ROS2 bridge)
unset LD_PRELOAD
# Clear default ROS ENV
unset PYTHONPATH

source env_isaaclab/bin/activate

# Isaac Sim ROS2 Bridge
export LD_LIBRARY_PATH=/usr/local/nvidia/lib64:/home/jovyan/IROS_Workshop/IsaacLab/_isaac_sim/exts/isaacsim.ros2.bridge/$ROS_DISTRO/lib

isaacsim isaacsim.exp.full.kit