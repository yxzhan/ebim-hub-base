FROM intel4coro/ebim-hub-base:latest

ARG WORKSPACE_ROOT=/workspace

ENV SHELL=/bin/bash

COPY start-helpers.sh run-scene-room.sh run-keyboard.sh ${WORKSPACE_ROOT}/

RUN chmod +x ${WORKSPACE_ROOT}/start-helpers.sh \
    ${WORKSPACE_ROOT}/run-scene-room.sh \
    ${WORKSPACE_ROOT}/run-keyboard.sh \
    && ln -sf ${WORKSPACE_ROOT}/start-helpers.sh /usr/local/bin/ebim-start-helpers \
    && ln -sf ${WORKSPACE_ROOT}/run-scene-room.sh /usr/local/bin/ebim-run-scene-room \
    && ln -sf ${WORKSPACE_ROOT}/run-keyboard.sh /usr/local/bin/ebim-keyboard

COPY EBIM-Task2.desktop /root/Desktop/
COPY ./entrypoint.sh /entrypoint.sh

# Launcher page, served by a background http.server in entrypoint.sh and reached
# via jupyter-server-proxy at /user/<name>/proxy/8899/
COPY workspace.html ${WORKSPACE_ROOT}/.launcher/index.html

RUN chmod +x /root/Desktop/EBIM-Task2.desktop \
    /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]