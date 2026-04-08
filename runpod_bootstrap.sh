#!/bin/bash
# 官方 runpod/comfyui 镜像的二次初始化脚本
# 作用：
# 1. 探测 ComfyUI 根目录
# 2. 桥接 volume 中的 models/custom_nodes
# 3. 安装 custom node 依赖
# 4. 可选补装 Impact Subpack
# 5. 可选重启 ComfyUI

set -euo pipefail

COMFY_ROOT="${COMFY_ROOT:-}"
CUSTOM_NODES_DIR="${CUSTOM_NODES_DIR:-}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
RESTART_COMFYUI_AFTER_SYNC="${RESTART_COMFYUI_AFTER_SYNC:-0}"
PIP_INSTALL_ARGS="${PIP_INSTALL_ARGS:-}"
RUNPOD_VOLUME_ROOT="${RUNPOD_VOLUME_ROOT:-/runpod-volume}"
COMFY_VENV_ACTIVATE="${COMFY_VENV_ACTIVATE:-}"
HF_TOKEN="${HF_TOKEN:-}"
MODEL_SPECS="${MODEL_SPECS:-}"
MODEL_SPECS_FILE="${MODEL_SPECS_FILE:-}"
MODEL_DOWNLOAD_BASE_URL="${MODEL_DOWNLOAD_BASE_URL:-https://huggingface.co}"
SKIP_EXISTING_MODELS="${SKIP_EXISTING_MODELS:-1}"

die() {
  echo "错误：$1" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || die "缺少 git"

detect_comfy_root() {
  if [[ -n "$COMFY_ROOT" ]]; then
    [[ -d "$COMFY_ROOT" ]] || die "ComfyUI 目录不存在：$COMFY_ROOT"
  elif [[ -d "/workspace/runpod-slim/ComfyUI" ]]; then
    COMFY_ROOT="/workspace/runpod-slim/ComfyUI"
  elif [[ -d "/workspace/ComfyUI" ]]; then
    COMFY_ROOT="/workspace/ComfyUI"
  else
    die "找不到 ComfyUI 根目录"
  fi

  if [[ -z "$CUSTOM_NODES_DIR" ]]; then
    CUSTOM_NODES_DIR="$COMFY_ROOT/custom_nodes"
  fi

  if [[ -z "$COMFY_VENV_ACTIVATE" && -f "$COMFY_ROOT/.venv-cu128/bin/activate" ]]; then
    COMFY_VENV_ACTIVATE="$COMFY_ROOT/.venv-cu128/bin/activate"
  fi
}

ensure_python() {
  if [[ -n "$COMFY_VENV_ACTIVATE" ]]; then
    # shellcheck disable=SC1090
    source "$COMFY_VENV_ACTIVATE"
  fi

  command -v "$PYTHON_BIN" >/dev/null 2>&1 || die "缺少 Python：$PYTHON_BIN"
}

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

load_model_specs() {
  if [[ -n "$MODEL_SPECS_FILE" && -f "$MODEL_SPECS_FILE" ]]; then
    cat "$MODEL_SPECS_FILE"
    return
  fi

  if [[ -n "$MODEL_SPECS" ]]; then
    printf '%s
' "$MODEL_SPECS"
  fi
}

download_models_if_needed() {
  local specs
  specs="$(load_model_specs)"

  if [[ -z "$specs" ]]; then
    echo "==> 未配置 MODEL_SPECS / MODEL_SPECS_FILE，跳过 Hugging Face 模型下载"
    return
  fi

  command -v curl >/dev/null 2>&1 || die "缺少 curl"

  local models_dir="$COMFY_ROOT/models"
  mkdir -p "$models_dir"

  echo "==> 检查 Hugging Face 模型清单"

  while IFS='|' read -r target_path repo_id repo_file revision; do
    [[ -n "${target_path// }" ]] || continue
    [[ "$target_path" =~ ^# ]] && continue
    [[ -n "$repo_id" ]] || die "MODEL_SPECS 缺少 repo_id：$target_path"
    [[ -n "$repo_file" ]] || die "MODEL_SPECS 缺少 repo_file：$target_path"

    revision="${revision:-main}"

    local dest="$models_dir/$target_path"
    local tmp_dest="$dest.tmp"
    mkdir -p "$(dirname "$dest")"

    if [[ "$SKIP_EXISTING_MODELS" == "1" && -f "$dest" ]]; then
      echo "==> 已存在，跳过模型：$target_path"
      continue
    fi

    local url="$MODEL_DOWNLOAD_BASE_URL/$repo_id/resolve/$revision/$repo_file?download=1"
    local -a curl_args=(--fail --location --retry 3 --output "$tmp_dest")

    if [[ -n "$HF_TOKEN" ]]; then
      curl_args+=(-H "Authorization: Bearer $HF_TOKEN")
    fi

    echo "==> 下载模型：$target_path <- $repo_id/$repo_file@$revision"
    rm -f "$tmp_dest"
    curl "${curl_args[@]}" "$url"
    mv "$tmp_dest" "$dest"
  done <<< "$specs"
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
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local install_script="$script_dir/install_custom_node_deps.sh"
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
  if [[ -n "$COMFY_VENV_ACTIVATE" ]]; then
    nohup bash -lc "cd '$COMFY_ROOT' && source '$COMFY_VENV_ACTIVATE' && $PYTHON_BIN main.py --listen 0.0.0.0 --port 8188" > /workspace/comfyui.log 2>&1 &
  else
    nohup "$PYTHON_BIN" "$COMFY_ROOT/main.py" --listen 0.0.0.0 --port 8188 > /workspace/comfyui.log 2>&1 &
  fi
}

main() {
  detect_comfy_root
  ensure_python
  bridge_volume_paths
  download_models_if_needed
  [[ -d "$CUSTOM_NODES_DIR" ]] || die "custom_nodes 目录不存在：$CUSTOM_NODES_DIR"
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
  echo "  ComfyUI：$COMFY_ROOT"
}

main "$@"
