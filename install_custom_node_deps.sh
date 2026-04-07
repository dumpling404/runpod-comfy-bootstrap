#!/bin/bash
# 扫描并安装 ComfyUI custom_nodes 依赖
# 默认只自动执行 requirements.txt
# install.py 仅对白名单节点执行，避免误触发大下载

set -euo pipefail

COMFY_ROOT="${COMFY_ROOT:-/workspace/ComfyUI}"
CUSTOM_NODES_DIR="${CUSTOM_NODES_DIR:-$COMFY_ROOT/custom_nodes}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
PIP_INSTALL_ARGS="${PIP_INSTALL_ARGS:-}"

SAFE_INSTALL_NODES=(
  "ComfyUI-Impact-Pack"
)

beep() {
  paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || echo -e '\a\a\a'
}

die() {
  echo "错误：$1" >&2
  exit 1
}

[[ -d "$CUSTOM_NODES_DIR" ]] || die "custom_nodes 目录不存在：$CUSTOM_NODES_DIR"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || die "找不到 Python：$PYTHON_BIN"

echo "ComfyUI 根目录：$COMFY_ROOT"
echo "custom_nodes 目录：$CUSTOM_NODES_DIR"
echo

mapfile -d '' REQUIREMENT_FILES < <(find "$CUSTOM_NODES_DIR" -mindepth 2 -maxdepth 2 -name requirements.txt -print0 | sort -z)

if [[ ${#REQUIREMENT_FILES[@]} -eq 0 ]]; then
  echo "没有找到 requirements.txt，跳过依赖安装。"
else
  echo "找到 ${#REQUIREMENT_FILES[@]} 个 requirements.txt"
  for req in "${REQUIREMENT_FILES[@]}"; do
    node_dir="$(basename "$(dirname "$req")")"
    echo
    echo "==> 安装 $node_dir 依赖"
    "$PYTHON_BIN" -m pip install $PIP_INSTALL_ARGS -r "$req"
  done
fi

echo
echo "检查 install.py 白名单节点..."
for node in "${SAFE_INSTALL_NODES[@]}"; do
  install_py="$CUSTOM_NODES_DIR/$node/install.py"
  if [[ -f "$install_py" ]]; then
    echo "==> 执行 $node/install.py"
    "$PYTHON_BIN" "$install_py"
  fi
done

echo
echo "全部 custom node 依赖处理完成。"
beep
