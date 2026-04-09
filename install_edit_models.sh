#!/usr/bin/env bash
# 安装当前可测的 edit 模型链到 RunPod / ComfyUI:
# 1. 官方 Qwen-Image-Edit GGUF
# 2. Qwen Rapid-AIO NSFW
#
# 注意：
# - Z-Image-Edit 官方权重当前未公开，本脚本不安装它
# - 默认 ComfyUI 路径是 /workspace/runpod-slim/ComfyUI，可用 COMFY_ROOT 覆盖

set -euo pipefail

COMFY_ROOT="${COMFY_ROOT:-/workspace/runpod-slim/ComfyUI}"
CUSTOM_NODES_DIR="${CUSTOM_NODES_DIR:-$COMFY_ROOT/custom_nodes}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
QWEN_NODES_PATCH_URL="${QWEN_NODES_PATCH_URL:-https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/main/fixed-textencode-node/nodes_qwen.v2.py}"

beep() {
  paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || echo -e '\a\a\a'
}

die() {
  echo "错误：$1" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

clone_or_update_repo() {
  local repo_url="$1"
  local dest="$2"
  local ref="${3:-main}"

  if [[ -d "$dest/.git" ]]; then
    echo "==> 更新仓库：$dest"
    git -C "$dest" fetch --tags origin
    git -C "$dest" checkout "$ref"
    if git -C "$dest" rev-parse --verify "origin/$ref" >/dev/null 2>&1; then
      git -C "$dest" reset --hard "origin/$ref"
    fi
    return
  fi

  echo "==> 拉取仓库：$repo_url -> $dest"
  rm -rf "$dest"
  git clone "$repo_url" "$dest"
  git -C "$dest" checkout "$ref"
  if git -C "$dest" rev-parse --verify "origin/$ref" >/dev/null 2>&1; then
    git -C "$dest" reset --hard "origin/$ref"
  fi
}

download_file() {
  local url="$1"
  local dest="$2"
  local tmp="${dest}.tmp"

  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]]; then
    echo "==> 已存在，跳过：$dest"
    return
  fi

  echo "==> 下载：$dest"
  rm -f "$tmp"
  curl --fail --location --retry 3 --output "$tmp" "$url"
  mv "$tmp" "$dest"
}

install_requirements_if_present() {
  local req="$1/requirements.txt"
  if [[ -f "$req" ]]; then
    echo "==> 安装依赖：$req"
    "$PYTHON_BIN" -m pip install -r "$req"
  fi
}

main() {
  need_cmd git
  need_cmd curl
  need_cmd "$PYTHON_BIN"

  [[ -d "$COMFY_ROOT" ]] || die "ComfyUI 目录不存在：$COMFY_ROOT"

  mkdir -p \
    "$CUSTOM_NODES_DIR" \
    "$COMFY_ROOT/models/checkpoints" \
    "$COMFY_ROOT/models/diffusion_models" \
    "$COMFY_ROOT/models/text_encoders" \
    "$COMFY_ROOT/models/vae" \
    "$COMFY_ROOT/models/unet" \
    "$COMFY_ROOT/models/clip"

  echo "==> 安装 ComfyUI-GGUF"
  clone_or_update_repo \
    "https://github.com/city96/ComfyUI-GGUF.git" \
    "$CUSTOM_NODES_DIR/ComfyUI-GGUF" \
    "main"
  install_requirements_if_present "$CUSTOM_NODES_DIR/ComfyUI-GGUF"

  echo "==> 下载官方 Qwen-Image-Edit GGUF"
  download_file \
    "https://huggingface.co/unsloth/Qwen-Image-Edit-2511-GGUF/resolve/main/qwen-image-edit-2511-Q4_K_M.gguf?download=1" \
    "$COMFY_ROOT/models/diffusion_models/qwen-image-edit-2511-Q4_K_M.gguf"
  download_file \
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors?download=1" \
    "$COMFY_ROOT/models/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"
  download_file \
    "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors?download=1" \
    "$COMFY_ROOT/models/vae/qwen_image_vae.safetensors"

  echo "==> 建立官方 Qwen-Image-Edit 兼容软链"
  ln -sfn ../diffusion_models/qwen-image-edit-2511-Q4_K_M.gguf \
    "$COMFY_ROOT/models/unet/qwen-image-edit-2511-Q4_K_M.gguf"
  ln -sfn ../text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors \
    "$COMFY_ROOT/models/clip/qwen_2.5_vl_7b_fp8_scaled.safetensors"

  echo "==> 下载 Qwen Rapid-AIO NSFW"
  download_file \
    "https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/main/v23/Qwen-Rapid-AIO-NSFW-v23.safetensors?download=1" \
    "$COMFY_ROOT/models/checkpoints/Qwen-Rapid-AIO-NSFW-v23.safetensors"

  echo "==> 应用 nodes_qwen v2 补丁"
  curl --fail --location --retry 3 --output "$COMFY_ROOT/comfy_extras/nodes_qwen.py" "$QWEN_NODES_PATCH_URL"
  "$PYTHON_BIN" - <<'PY' "$COMFY_ROOT/comfy_extras/nodes_qwen.py"
import ast
import sys
ast.parse(open(sys.argv[1], 'r', encoding='utf-8').read())
PY

  echo
  echo "完成："
  echo "  ComfyUI: $COMFY_ROOT"
  echo "  官方 Qwen Edit: models/diffusion_models/qwen-image-edit-2511-Q4_K_M.gguf"
  echo "  Rapid-AIO: models/checkpoints/Qwen-Rapid-AIO-NSFW-v23.safetensors"
  echo "  Z-Image-Edit: 官方权重未公开，未安装"
  beep
}

main "$@"
