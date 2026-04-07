#!/bin/bash
# 极薄启动入口：
# 1. 拉取/更新 public bootstrap repo
# 2. 执行 runpod_bootstrap.sh
# 3. 其余逻辑都交给 repo 脚本维护

set -euo pipefail

BOOTSTRAP_REPO_URL="${BOOTSTRAP_REPO_URL:-https://github.com/dumpling404/runpod-comfy-bootstrap.git}"
BOOTSTRAP_REPO_REF="${BOOTSTRAP_REPO_REF:-main}"
BOOTSTRAP_REPO_DIR="${BOOTSTRAP_REPO_DIR:-/workspace/runpod-comfy-bootstrap}"

die() {
  echo "错误：$1" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || die "缺少 git"

sync_bootstrap_repo() {
  if [[ ! -d "$BOOTSTRAP_REPO_DIR/.git" ]]; then
    echo "==> clone bootstrap repo"
    rm -rf "$BOOTSTRAP_REPO_DIR"
    git clone "$BOOTSTRAP_REPO_URL" "$BOOTSTRAP_REPO_DIR"
  fi

  echo "==> update bootstrap repo: $BOOTSTRAP_REPO_REF"
  git -C "$BOOTSTRAP_REPO_DIR" fetch --tags origin
  git -C "$BOOTSTRAP_REPO_DIR" checkout "$BOOTSTRAP_REPO_REF"

  if git -C "$BOOTSTRAP_REPO_DIR" rev-parse --verify "origin/$BOOTSTRAP_REPO_REF" >/dev/null 2>&1; then
    git -C "$BOOTSTRAP_REPO_DIR" reset --hard "origin/$BOOTSTRAP_REPO_REF"
  fi
}

main() {
  sync_bootstrap_repo

  [[ -f "$BOOTSTRAP_REPO_DIR/runpod_bootstrap.sh" ]] || die "找不到 runpod_bootstrap.sh"

  exec bash "$BOOTSTRAP_REPO_DIR/runpod_bootstrap.sh"
}

main "$@"
