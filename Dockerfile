FROM runpod/comfyui:latest

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends git rsync && \
    rm -rf /var/lib/apt/lists/*

COPY bootstrap_entry.sh /usr/local/bin/bootstrap_entry.sh
RUN chmod +x /usr/local/bin/bootstrap_entry.sh

ENV BOOTSTRAP_REPO_URL="https://github.com/dumpling404/runpod-comfy-bootstrap.git"
ENV BOOTSTRAP_REPO_REF="main"
ENV BOOTSTRAP_REPO_DIR="/workspace/runpod-comfy-bootstrap"
ENV NSFW_IP_REPO_URL=""
ENV NSFW_IP_REF="prod"
ENV RESTART_COMFYUI_AFTER_SYNC="1"
ENV COMFY_ROOT="/workspace/ComfyUI"
ENV CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"
ENV PYTHON_BIN="python3"
ENV PIP_INSTALL_ARGS=""

