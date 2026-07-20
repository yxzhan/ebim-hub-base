#!/usr/bin/env bash
# Copyright (c) 2026 The EBiM Benchmark Contributors
# SPDX-License-Identifier: Apache-2.0
#
# Auto-launch EBIM Task 3 as soon as the graphical session (and $DISPLAY) is up.
# Wired via XDG autostart (/root/.config/autostart/EBIM-Task3-autostart.desktop),
# which fires when the Xfce/VNC desktop session starts — i.e. exactly when the
# display becomes available. Opens a terminal on the desktop so the keyboard
# teleop has a real tty. Written defensively so it survives across desktop
# environments / terminal emulators.
set -u

: "${DISPLAY:=:1}"
export DISPLAY

# The session manager already started us after X came up, but give the display
# server / window manager a moment to actually accept clients before we spawn
# Isaac Sim. No hard dependency on xdpyinfo — fall back to the X socket.
for _ in $(seq 1 60); do
    if command -v xdpyinfo >/dev/null 2>&1; then
        xdpyinfo >/dev/null 2>&1 && break
    else
        n="${DISPLAY#*:}"; n="${n%%.*}"
        [ -S "/tmp/.X11-unix/X${n}" ] && break
    fi
    sleep 0.5
done

# Pick whatever terminal emulator this image ships.
for t in x-terminal-emulator xfce4-terminal lxterminal mate-terminal konsole xterm; do
    if command -v "$t" >/dev/null 2>&1; then
        TERM_EMU="$t"
        break
    fi
done

if [ -n "${TERM_EMU:-}" ]; then
    exec "$TERM_EMU" -e ebim-run-task3-session
else
    # No terminal emulator found: run without a tty. The sim + browser arm UI
    # still come up; only the keyboard-base teleop loses its key input.
    exec ebim-run-task3-session
fi
