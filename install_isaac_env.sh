# Install Claude code
curl -fsSL https://claude.ai/install.sh | bash

echo "Installing UV..."
curl -LsSf https://astral.sh/uv/install.sh | sh

echo "Installing Python3.11 env..."
uv venv --python 3.11 --seed env_isaaclab

echo "Installing IsaacSim..."
source env_isaaclab/bin/activate
uv pip install "isaacsim[all,extscache]==5.1.0" --extra-index-url https://pypi.nvidia.com
uv pip install -U torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu128
uv pip install pynput

git submodule update --init --recursive

export ISAACSIM_PATH=$PWD/env_isaaclab/lib/python3.11/site-packages/isaacsim

# echo "Installing isaacsim.robot_motion.dual_arm_rmp_widget..."
# export DEMO_PATH=$PWD/DEMO
# ln -s $DEMO_PATH/isaacsim.robot_motion.dual_arm_rmp_widget $ISAACSIM_PATH/exts/isaacsim.robot_motion.dual_arm_rmp_widget

echo "Installing IsaacLab..."
git clone https://github.com/isaac-sim/IsaacLab.git --branch v2.3.2
cd IsaacLab
ln -s $ISAACSIM_PATH $PWD/_isaac_sim
./isaaclab.sh --install

echo "Done!"