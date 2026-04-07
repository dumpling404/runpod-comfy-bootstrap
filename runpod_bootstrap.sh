#!/bin/bash
# 官方 runpod/comfyui 镜像的二次初始化脚本
# 作用：
# 1. git clone / fetch 你的仓库到容器内
# 2. 安装 custom node 依赖
# 3. 可选补装 Impact Subpack
# 4. 可选重启 ComfyUI

set -euo pipefail

NSFW_IP_REPO_URL="${NSFW_IP_REPO_URL:-https://github.com/wulalaya/nsfw-ip.git}"
NSFW_IP_REF="${NSFW_IP_REF:-prod}"
REPO_DIR="${REPO_DIR:-/opt/nsfw-ip}"
COMFY_ROOT="${COMFY_ROOT:-/workspace/ComfyUI}"
CUSTOM_NODES_DIR="${CUSTOM_NODES_DIR:-$COMFY_ROOT/custom_nodes}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
RESTART_COMFYUI_AFTER_SYNC="${RESTART_COMFYUI_AFTER_SYNC:-0}"
PIP_INSTALL_ARGS="${PIP_INSTALL_ARGS:-}"
RUNPOD_VOLUME_ROOT="${RUNPOD_VOLUME_ROOT:-/runpod-volume}"

die() {
  echo "错误：$1" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || die "缺少 git"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || die "缺少 Python：$PYTHON_BIN"
[[ -d "$COMFY_ROOT" ]] || die "ComfyUI 目录不存在：$COMFY_ROOT"

bridge_volume_paths() {
  local volume_comfy="$RUNPOD_VOLUME_ROOT/ComfyUI"
  local workspace_models="$COMFY_ROOT/models"
  local workspace_nodes="$COMFY_ROOT/custom_nodes"
  local volume_models="$volume_comfy/models"
  local volume_nodes="$volume_comfy/custom_nodes"

  if [[ ! -d "$volume_comfy" ]]; then
    echo "==> 未检测到 $volume_comfy，跳过路径桥接"
    return
  fi

  echo "==> 检测到 RunPod volume，桥接 models/custom_nodes"
  mkdir -p "$volume_models" "$volume_nodes"

  if [[ -L "$workspace_models" || -d "$workspace_models" ]]; then
    rm -rf "$workspace_models"
  fi
  ln -s "$volume_models" "$workspace_models"

  if [[ -L "$workspace_nodes" || -d "$workspace_nodes" ]]; then
    rm -rf "$workspace_nodes"
  fi
  ln -s "$volume_nodes" "$workspace_nodes"
}

sync_repo() {
  if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "==> 首次 clone 仓库到 $REPO_DIR"
    rm -rf "$REPO_DIR"
    git clone "$NSFW_IP_REPO_URL" "$REPO_DIR"
  fi

  echo "==> 更新仓库：$NSFW_IP_REF"
  git -C "$REPO_DIR" fetch --tags origin
  git -C "$REPO_DIR" checkout "$NSFW_IP_REF"

  if git -C "$REPO_DIR" rev-parse --verify "origin/$NSFW_IP_REF" >/dev/null 2>&1; then
    git -C "$REPO_DIR" reset --hard "origin/$NSFW_IP_REF"
  fi
}

ensure_impact_subpack() {
  local subpack_dir="$CUSTOM_NODES_DIR/ComfyUI-Impact-Subpack"
  if [[ -d "$subpack_dir/.git" ]]; then
    echo "==> 更新 ComfyUI-Impact-Subpack"
    git -C "$subpack_dir" pull --ff-only || true
    return
  fi

  echo "==> 安装 ComfyUI-Impact-Subpack"
  git clone https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git "$subpack_dir"
}

install_node_deps() {
  local install_script="$REPO_DIR/scripts/install_custom_node_deps.sh"
  if [[ ! -f "$install_script" ]]; then
    install_script="$REPO_DIR/install_custom_node_deps.sh"
  fi
  [[ -f "$install_script" ]] || die "找不到依赖脚本：$install_script"

  echo "==> 安装 custom node 依赖"
  COMFY_ROOT="$COMFY_ROOT" \
  CUSTOM_NODES_DIR="$CUSTOM_NODES_DIR" \
  PYTHON_BIN="$PYTHON_BIN" \
  PIP_INSTALL_ARGS="$PIP_INSTALL_ARGS" \
  bash "$install_script"

  if [[ -f "$CUSTOM_NODES_DIR/ComfyUI-Impact-Subpack/requirements.txt" ]]; then
    echo "==> 安装 Impact Subpack 依赖"
    "$PYTHON_BIN" -m pip install $PIP_INSTALL_ARGS -r "$CUSTOM_NODES_DIR/ComfyUI-Impact-Subpack/requirements.txt"
  fi
}

restart_comfyui() {
  echo "==> 重启 ComfyUI"
  pkill -f "python main.py --listen 0.0.0.0 --port 8188" || true
  pkill -f "python3 main.py --listen 0.0.0.0 --port 8188" || true
  nohup "$PYTHON_BIN" "$COMFY_ROOT/main.py" --listen 0.0.0.0 --port 8188 > /workspace/comfyui.log 2>&1 &
}

main() {
  bridge_volume_paths
  [[ -d "$CUSTOM_NODES_DIR" ]] || die "custom_nodes 目录不存在：$CUSTOM_NODES_DIR"
  sync_repo
  ensure_impact_subpack
  install_node_deps

  mkdir -p /workspace/archive/output /workspace/ComfyUI/input /workspace/ComfyUI/output

  if [[ "$RESTART_COMFYUI_AFTER_SYNC" == "1" ]]; then
    restart_comfyui
  else
    echo "==> 跳过重启 ComfyUI（RESTART_COMFYUI_AFTER_SYNC=$RESTART_COMFYUI_AFTER_SYNC）"
  fi

  echo
  echo "完成："
  echo "  仓库：$REPO_DIR"
  echo "  Ref：$NSFW_IP_REF"
  echo "  ComfyUI：$COMFY_ROOT"
}

main "$@"
