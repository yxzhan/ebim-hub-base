#!/usr/bin/env bash
# Copyright (c) 2026 The EBiM Benchmark Contributors
# SPDX-License-Identifier: Apache-2.0
#
# The Task 3 sim + keyboard-teleop tmux session, as a single executable so it
# can be handed to a terminal emulator's `-e` (which expects ONE program, not a
# shell string — xterm splits argv, xfce4-terminal wants a single command).
# Same session the EBIM-Task3.desktop icon launches.
exec tmux new-session 'ebim-run-task3-scene-room' \; split-window -h 'ebim-keyboard'
