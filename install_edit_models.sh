#!/usr/bin/env bash
# 安装 Rapid-AIO NSFW 单图编辑测试链到 RunPod / ComfyUI。
# 只保留当前实际要测的东西：
# 1. Qwen Rapid-AIO NSFW checkpoint
# 2. nodes_qwen v2 补丁
#
# 不安装官方 Qwen-Image-Edit GGUF，不安装 Z-Image-Edit。

set -euo pipefail

COMFY_ROOT="${COMFY_ROOT:-/workspace/runpod-slim/ComfyUI}"
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

main() {
  need_cmd curl
  need_cmd "$PYTHON_BIN"

  [[ -d "$COMFY_ROOT" ]] || die "ComfyUI 目录不存在：$COMFY_ROOT"
  mkdir -p "$COMFY_ROOT/models/checkpoints"

  echo "==> 下载 Qwen Rapid-AIO NSFW"
  download_file \
    "https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/main/v23/Qwen-Rapid-AIO-NSFW-v23.safetensors?download=1" \
    "$COMFY_ROOT/models/checkpoints/Qwen-Rapid-AIO-NSFW-v23.safetensors"

  echo "==> 应用 nodes_qwen v2 补丁"
  curl --fail --location --retry 3 --output "$COMFY_ROOT/comfy_extras/nodes_qwen.py" "$QWEN_NODES_PATCH_URL"
  "$PYTHON_BIN" - <<'PY' "$COMFY_ROOT/comfy_extras/nodes_qwen.py"
import ast
import sys
src = open(sys.argv[1], 'r', encoding='utf-8').read()
ast.parse(src)
if 'target_latent' not in src:
    raise SystemExit('nodes_qwen.py 校验失败：缺少 target_latent')
PY

  echo
  echo "完成："
  echo "  ComfyUI: $COMFY_ROOT"
  echo "  Rapid-AIO: models/checkpoints/Qwen-Rapid-AIO-NSFW-v23.safetensors"
  beep
}

main "$@"
