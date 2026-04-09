#!/bin/bash
# RunPod ComfyUI bootstrap.
# Single execution script:
# 1. source runpod_profile.sh
# 2. detect ComfyUI root
# 3. bridge volume paths when present
# 4. sync all custom nodes from profile
# 5. download all models from profile
# 6. install Python dependencies for every custom node
# 7. restart ComfyUI if enabled

set -euo pipefail

COMFY_ROOT="${COMFY_ROOT:-}"
CUSTOM_NODES_DIR="${CUSTOM_NODES_DIR:-}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
RESTART_COMFYUI_AFTER_SYNC="${RESTART_COMFYUI_AFTER_SYNC:-0}"
PIP_INSTALL_ARGS="${PIP_INSTALL_ARGS:-}"
RUNPOD_VOLUME_ROOT="${RUNPOD_VOLUME_ROOT:-/runpod-volume}"
COMFY_VENV_ACTIVATE="${COMFY_VENV_ACTIVATE:-}"
QWEN_NODES_PATCH_URL="${QWEN_NODES_PATCH_URL:-}"
PRIVATE_LORA_REPO="${PRIVATE_LORA_REPO:-}"
PRIVATE_LORA_REF="${PRIVATE_LORA_REF:-main}"
PRIVATE_LORA_SUBDIR="${PRIVATE_LORA_SUBDIR:-loras}"
RUNPOD_SECRET_HG_TOKEN="${RUNPOD_SECRET_HG_TOKEN:-}"
MODEL_SPECS="${MODEL_SPECS:-}"
MODEL_DOWNLOAD_BASE_URL="${MODEL_DOWNLOAD_BASE_URL:-https://huggingface.co}"
SKIP_EXISTING_MODELS="${SKIP_EXISTING_MODELS:-1}"
CUSTOM_NODE_SPECS="${CUSTOM_NODE_SPECS:-}"
SKIP_EXISTING_CUSTOM_NODES="${SKIP_EXISTING_CUSTOM_NODES:-1}"
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_FILE="${PROFILE_FILE:-$BOOTSTRAP_DIR/runpod_profile.sh}"

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
  if [[ -n "$MODEL_SPECS" ]]; then
    printf '%s\n' "$MODEL_SPECS"
    return
  fi
}

load_custom_node_specs() {
  if [[ -n "$CUSTOM_NODE_SPECS" ]]; then
    printf '%s\n' "$CUSTOM_NODE_SPECS"
    return
  fi
}

append_private_lora_specs() {
  [[ -n "$PRIVATE_LORA_REPO" ]] || return
  [[ -n "$RUNPOD_SECRET_HG_TOKEN" ]] || die "PRIVATE_LORA_REPO 已配置，但缺少 RUNPOD_SECRET_HG_TOKEN"

  printf '%s|%s|%s/%s|%s\n' \
    'loras/xieyan_v1.safetensors' "$PRIVATE_LORA_REPO" "$PRIVATE_LORA_SUBDIR" 'xieyan_v1.safetensors' "$PRIVATE_LORA_REF"
  printf '%s|%s|%s/%s|%s\n' \
    'loras/oda-non_IL.safetensors' "$PRIVATE_LORA_REPO" "$PRIVATE_LORA_SUBDIR" 'oda-non_IL.safetensors' "$PRIVATE_LORA_REF"
}

sync_custom_nodes_if_needed() {
  local specs
  specs="$(load_custom_node_specs)"

  if [[ -z "$specs" ]]; then
    echo "==> 未配置 CUSTOM_NODE_SPECS，跳过 custom_nodes 拉取"
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
    echo "==> 未配置 MODEL_SPECS，跳过模型下载"
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
      if [[ -n "$RUNPOD_SECRET_HG_TOKEN" ]]; then
        curl_args+=(-H "Authorization: Bearer $RUNPOD_SECRET_HG_TOKEN")
      fi
    fi

    echo "==> 下载模型：$target_path <- $desc"
    rm -f "$tmp_dest"
    curl "${curl_args[@]}" "$url"
    mv "$tmp_dest" "$dest"
  done <<< "$specs"
}

apply_qwen_nodes_patch() {
  [[ -n "$QWEN_NODES_PATCH_URL" ]] || return
  command -v curl >/dev/null 2>&1 || die "缺少 curl"

  local target="$COMFY_ROOT/comfy_extras/nodes_qwen.py"
  local tmp_target="$target.tmp"

  echo "==> 应用 Qwen nodes 补丁"
  rm -f "$tmp_target"
  curl --fail --location --retry 3 --output "$tmp_target" "$QWEN_NODES_PATCH_URL"
  "$PYTHON_BIN" - <<'PATCHCHECK' "$tmp_target"
import ast
import sys
ast.parse(open(sys.argv[1], 'r', encoding='utf-8').read())
PATCHCHECK
  mv "$tmp_target" "$target"
}

install_node_deps() {
  local req install_py

  [[ -d "$CUSTOM_NODES_DIR" ]] || die "custom_nodes 目录不存在：$CUSTOM_NODES_DIR"

  mapfile -d '' REQUIREMENT_FILES < <(find "$CUSTOM_NODES_DIR" -mindepth 2 -maxdepth 2 -name requirements.txt -print0 | sort -z)
  if [[ ${#REQUIREMENT_FILES[@]} -eq 0 ]]; then
    echo "==> 没有找到 requirements.txt"
  else
    echo "==> 安装 custom node requirements"
    for req in "${REQUIREMENT_FILES[@]}"; do
      echo "   - $(basename "$(dirname "$req")")"
      "$PYTHON_BIN" -m pip install $PIP_INSTALL_ARGS -r "$req"
    done
  fi

  mapfile -d '' INSTALL_FILES < <(find "$CUSTOM_NODES_DIR" -mindepth 2 -maxdepth 2 -name install.py -print0 | sort -z)
  if [[ ${#INSTALL_FILES[@]} -eq 0 ]]; then
    echo "==> 没有找到 install.py"
  else
    echo "==> 执行 custom node install.py"
    for install_py in "${INSTALL_FILES[@]}"; do
      echo "   - $(basename "$(dirname "$install_py")")"
      "$PYTHON_BIN" "$install_py"
    done
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

print_asset_summary() {
  local checkpoints_dir="$COMFY_ROOT/models/checkpoints"
  local loras_dir="$COMFY_ROOT/models/loras"

  echo
  echo "==> 资产摘要"

  if [[ -d "$checkpoints_dir" ]]; then
    echo "  checkpoints:"
    find "$checkpoints_dir" -maxdepth 1 -type f | sort | sed 's#^#    - #'
  else
    echo "  checkpoints: <missing>"
  fi

  if [[ -d "$loras_dir" ]]; then
    echo "  loras:"
    find "$loras_dir" -maxdepth 1 -type f | sort | sed 's#^#    - #'
  else
    echo "  loras: <missing>"
  fi
}

main() {
  if [[ -f "$PROFILE_FILE" ]]; then
    echo "==> source profile: $PROFILE_FILE"
    # shellcheck disable=SC1090
    source "$PROFILE_FILE"
  fi
  detect_comfy_root
  ensure_python
  bridge_volume_paths
  sync_custom_nodes_if_needed
  download_models_if_needed
  [[ -d "$CUSTOM_NODES_DIR" ]] || die "custom_nodes 目录不存在：$CUSTOM_NODES_DIR"
  install_node_deps
  apply_qwen_nodes_patch

  mkdir -p /workspace/archive/output "$COMFY_ROOT/input" "$COMFY_ROOT/output"

  if [[ "$RESTART_COMFYUI_AFTER_SYNC" == "1" ]]; then
    restart_comfyui
  else
    echo "==> 跳过重启 ComfyUI（RESTART_COMFYUI_AFTER_SYNC=$RESTART_COMFYUI_AFTER_SYNC）"
  fi

  print_asset_summary

  echo
  echo "完成："
  echo "  ComfyUI：$COMFY_ROOT"
  echo "  Python：$PYTHON_BIN"
}

main "$@"
