#!/bin/bash
# 官方 runpod/comfyui 镜像的二次初始化脚本
# 作用：
# 1. 探测 ComfyUI 根目录
# 2. 桥接 volume 中的 models/custom_nodes
# 3. 同步默认 custom nodes
# 4. 下载默认公开模型
# 5. 安装 custom node 依赖与 Impact 配套依赖
# 6. 可选重启 ComfyUI

set -euo pipefail

COMFY_ROOT="${COMFY_ROOT:-}"
CUSTOM_NODES_DIR="${CUSTOM_NODES_DIR:-}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
RESTART_COMFYUI_AFTER_SYNC="${RESTART_COMFYUI_AFTER_SYNC:-0}"
PIP_INSTALL_ARGS="${PIP_INSTALL_ARGS:-}"
RUNPOD_VOLUME_ROOT="${RUNPOD_VOLUME_ROOT:-/runpod-volume}"
COMFY_VENV_ACTIVATE="${COMFY_VENV_ACTIVATE:-}"
HF_TOKEN="${HF_TOKEN:-}"
PRIVATE_LORA_REPO="${PRIVATE_LORA_REPO:-}"
PRIVATE_LORA_REF="${PRIVATE_LORA_REF:-main}"
PRIVATE_LORA_SUBDIR="${PRIVATE_LORA_SUBDIR:-loras}"
MODEL_SPECS="${MODEL_SPECS:-}"
MODEL_SPECS_FILE="${MODEL_SPECS_FILE:-}"
MODEL_DOWNLOAD_BASE_URL="${MODEL_DOWNLOAD_BASE_URL:-https://huggingface.co}"
SKIP_EXISTING_MODELS="${SKIP_EXISTING_MODELS:-1}"
CUSTOM_NODE_SPECS="${CUSTOM_NODE_SPECS:-}"
CUSTOM_NODE_SPECS_FILE="${CUSTOM_NODE_SPECS_FILE:-}"
SKIP_EXISTING_CUSTOM_NODES="${SKIP_EXISTING_CUSTOM_NODES:-1}"
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_MODEL_SPECS_FILE="${DEFAULT_MODEL_SPECS_FILE:-$BOOTSTRAP_DIR/manifests/model_specs.default.txt}"
DEFAULT_CUSTOM_NODE_SPECS_FILE="${DEFAULT_CUSTOM_NODE_SPECS_FILE:-$BOOTSTRAP_DIR/manifests/custom_node_specs.default.txt}"

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
  PYTHON_BIN="$(command -v "$PYTHON_BIN")"
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
    printf '%s\n' "$MODEL_SPECS"
    return
  fi

  if [[ -f "$DEFAULT_MODEL_SPECS_FILE" ]]; then
    cat "$DEFAULT_MODEL_SPECS_FILE"
  fi
}

load_custom_node_specs() {
  if [[ -n "$CUSTOM_NODE_SPECS_FILE" && -f "$CUSTOM_NODE_SPECS_FILE" ]]; then
    cat "$CUSTOM_NODE_SPECS_FILE"
    return
  fi

  if [[ -n "$CUSTOM_NODE_SPECS" ]]; then
    printf '%s\n' "$CUSTOM_NODE_SPECS"
    return
  fi

  if [[ -f "$DEFAULT_CUSTOM_NODE_SPECS_FILE" ]]; then
    cat "$DEFAULT_CUSTOM_NODE_SPECS_FILE"
  fi
}

append_private_lora_specs() {
  [[ -n "$PRIVATE_LORA_REPO" ]] || return

  printf '%s|%s|%s/%s|%s\n' \
    'loras/xieyan_v1.safetensors' "$PRIVATE_LORA_REPO" "$PRIVATE_LORA_SUBDIR" 'xieyan_v1.safetensors' "$PRIVATE_LORA_REF"
  printf '%s|%s|%s/%s|%s\n' \
    'loras/oda-non_IL.safetensors' "$PRIVATE_LORA_REPO" "$PRIVATE_LORA_SUBDIR" 'oda-non_IL.safetensors' "$PRIVATE_LORA_REF"
}

sync_custom_nodes_if_needed() {
  local specs
  specs="$(load_custom_node_specs)"

  if [[ -z "$specs" ]]; then
    echo "==> 未配置 CUSTOM_NODE_SPECS / CUSTOM_NODE_SPECS_FILE，跳过 custom_nodes 拉取"
    return
  fi

  mkdir -p "$CUSTOM_NODES_DIR"
  echo "==> 检查 custom_nodes 清单"

  while IFS='|' read -r node_dir repo_url repo_ref; do
    [[ -n "${node_dir// }" ]] || continue
    [[ "$node_dir" =~ ^# ]] && continue
    [[ -n "$repo_url" ]] || die "CUSTOM_NODE_SPECS 缺少 repo_url：$node_dir"

    repo_ref="${repo_ref:-main}"
    local dest="$CUSTOM_NODES_DIR/$node_dir"

    if [[ -d "$dest/.git" ]]; then
      echo "==> 更新 custom node：$node_dir@$repo_ref"
      git -C "$dest" fetch --tags origin
      git -C "$dest" checkout "$repo_ref"
      if git -C "$dest" rev-parse --verify "origin/$repo_ref" >/dev/null 2>&1; then
        git -C "$dest" reset --hard "origin/$repo_ref"
      fi
      continue
    fi

    if [[ -d "$dest" && "$SKIP_EXISTING_CUSTOM_NODES" == "1" ]]; then
      echo "==> 已存在目录，跳过 custom node：$node_dir"
      continue
    fi

    rm -rf "$dest"
    echo "==> 拉取 custom node：$node_dir <- $repo_url@$repo_ref"
    git clone "$repo_url" "$dest"
    git -C "$dest" checkout "$repo_ref"
    if git -C "$dest" rev-parse --verify "origin/$repo_ref" >/dev/null 2>&1; then
      git -C "$dest" reset --hard "origin/$repo_ref"
    fi
  done <<< "$specs"
}

download_models_if_needed() {
  local specs private_specs
  specs="$(load_model_specs)"
  private_specs="$(append_private_lora_specs || true)"

  if [[ -n "$private_specs" ]]; then
    specs="${specs:+$specs
}$private_specs"
  fi

  if [[ -z "$specs" ]]; then
    echo "==> 未配置 MODEL_SPECS / MODEL_SPECS_FILE，跳过模型下载"
    return
  fi

  command -v curl >/dev/null 2>&1 || die "缺少 curl"

  local models_dir="$COMFY_ROOT/models"
  mkdir -p "$models_dir"

  echo "==> 检查模型清单"

  while IFS='|' read -r target_path repo_id repo_file revision; do
    [[ -n "${target_path// }" ]] || continue
    [[ "$target_path" =~ ^# ]] && continue
    [[ -n "$repo_id" ]] || die "MODEL_SPECS 缺少 repo_id 或 direct_url：$target_path"

    revision="${revision:-main}"

    local dest="$models_dir/$target_path"
    local tmp_dest="$dest.tmp"
    mkdir -p "$(dirname "$dest")"

    if [[ "$SKIP_EXISTING_MODELS" == "1" && -f "$dest" ]]; then
      echo "==> 已存在，跳过模型：$target_path"
      continue
    fi

    local url=""
    local desc=""
    local -a curl_args=(--fail --location --retry 3 --output "$tmp_dest")

    if [[ "$repo_id" =~ ^https?:// ]]; then
      url="$repo_id"
      desc="$repo_id"
    else
      [[ -n "$repo_file" ]] || die "MODEL_SPECS 缺少 repo_file：$target_path"
      url="$MODEL_DOWNLOAD_BASE_URL/$repo_id/resolve/$revision/$repo_file?download=1"
      desc="$repo_id/$repo_file@$revision"
      if [[ -n "$HF_TOKEN" ]]; then
        curl_args+=(-H "Authorization: Bearer $HF_TOKEN")
      fi
    fi

    echo "==> 下载模型：$target_path <- $desc"
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

  if [[ -d "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack" ]]; then
    echo "==> 补装 Impact-Pack 运行依赖"
    "$PYTHON_BIN" -m pip install $PIP_INSTALL_ARGS onnxruntime
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
  sync_custom_nodes_if_needed
  download_models_if_needed
  [[ -d "$CUSTOM_NODES_DIR" ]] || die "custom_nodes 目录不存在：$CUSTOM_NODES_DIR"
  ensure_impact_subpack
  install_node_deps

  mkdir -p /workspace/archive/output "$COMFY_ROOT/input" "$COMFY_ROOT/output"

  if [[ "$RESTART_COMFYUI_AFTER_SYNC" == "1" ]]; then
    restart_comfyui
  else
    echo "==> 跳过重启 ComfyUI（RESTART_COMFYUI_AFTER_SYNC=$RESTART_COMFYUI_AFTER_SYNC）"
  fi

  echo
  echo "完成："
  echo "  ComfyUI：$COMFY_ROOT"
  echo "  Python：$PYTHON_BIN"
}

main "$@"
