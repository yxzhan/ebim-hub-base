#!/bin/bash

ebim-start-helpers

# Launcher page: static http server, reachable via jupyter-server-proxy at
# /user/<name>/proxy/8899/. Wrapped in a loop so it is respawned if it ever dies.
nohup bash -c 'while true; do
    python3 -m http.server 8899 --bind 127.0.0.1 --directory /workspace/.launcher
    echo "[ebim-launcher] http.server exited, restarting in 2s..."
    sleep 2
done' >/tmp/ebim-launcher.log 2>&1 &

exec "$@"