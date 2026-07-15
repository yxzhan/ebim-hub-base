#!/bin/bash

# Best-effort: seed the Isaac Sim kit cache from the shared cache. Never let a
# failure here (missing source, permissions, no space, ...) abort startup.
if [ -d /mnt/dev-tools/ebim-cache/cache ]; then
    echo "[ebim-cache] copying cache into /isaac-sim/kit/ ..."
    cp -a /mnt/dev-tools/ebim-cache/cache /isaac-sim/kit/ \
        && echo "[ebim-cache] done." \
        || echo "[ebim-cache] copy failed, continuing without it."
else
    echo "[ebim-cache] /mnt/dev-tools/ebim-cache/cache not found, skipping."
fi

ebim-start-helpers

# Launcher page: static http server, reachable via jupyter-server-proxy at
# /user/<name>/proxy/8899/. Wrapped in a loop so it is respawned if it ever dies.
nohup bash -c 'while true; do
    python3 -m http.server 8899 --bind 127.0.0.1 --directory /workspace/.launcher
    echo "[ebim-launcher] http.server exited, restarting in 2s..."
    sleep 2
done' >/tmp/ebim-launcher.log 2>&1 &

exec "$@"