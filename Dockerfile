# Dockerfile of the base image: https://github.com/IntEL4CoRo/jupyter-ros2/blob/main/Dockerfile
FROM intel4coro/jupyter-ros2:jazzy-py3.12

USER root
ENV PATH=$HOME/.local/bin:$PATH

# Install git-lfs
RUN apt-get update && \
    apt-get install -y git-lfs && \
    git lfs install

# Install VirtualGL
RUN wget https://github.com/VirtualGL/virtualgl/releases/download/3.1.4/virtualgl_3.1.4_amd64.deb && \
    apt install -y ./virtualgl_3.1.4_amd64.deb && \
    rm virtualgl_3.1.4_amd64.deb

# Upgrade vscode-server
RUN mamba update -y conda-forge::code-server
RUN code-server --install-extension mhutchie.git-graph
RUN code-server --install-extension lichenxi.sysmonitor
RUN curl -LO https://github.com/yxzhan/vscode_remote_desktop/releases/download/v0.1.0/vscode-remote-desktop-0.1.0.vsix && \
    code-server --install-extension vscode-remote-desktop-0.1.0.vsix && \
    rm vscode-remote-desktop-0.1.0.vsix

# Install Claude code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install UV
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install IsaacLab
WORKDIR /home
RUN uv venv --python 3.12 --seed env_isaaclab && \
    source env_isaaclab/bin/activate && \
    uv pip install --upgrade pip && \
    uv pip install "isaaclab[isaacsim,all]" --extra-index-url https://pypi.nvidia.com --index-strategy unsafe-best-match --prerelease=allow && \
    uv pip install -U torch==2.10.0 torchvision==0.25.0 --index-url https://download.pytorch.org/whl/cu128


WORKDIR ${HOME}
ENV CODE_WORKING_DIRECTORY=${HOME}

# The entrypoint of the docker image
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]