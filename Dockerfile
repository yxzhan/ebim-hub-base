FROM intel4coro/ebim-hub-base:latest

ARG WORKSPACE_ROOT=/workspace

COPY --chmod=755 start-helpers.sh run-scene-room.sh run-keyboard.sh ${WORKSPACE_ROOT}/
RUN ln -sf ${WORKSPACE_ROOT}/start-helpers.sh   /usr/local/bin/ebim-start-helpers \
    && ln -sf ${WORKSPACE_ROOT}/run-scene-room.sh /usr/local/bin/ebim-run-scene-room \
    && ln -sf ${WORKSPACE_ROOT}/run-keyboard.sh   /usr/local/bin/ebim-keyboard

COPY --chmod=755 EBIM-Task2.desktop /root/Desktop/

COPY ./entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]