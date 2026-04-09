#!/usr/bin/env bash
# Full bootstrap for brand-new Pods.
# Goal: do a brute-force "install everything we expect" run
# without relying on skip flags or previous state.

set -euo pipefail

export SKIP_EXISTING_MODELS=0
export SKIP_EXISTING_CUSTOM_NODES=0
export RESTART_COMFYUI_AFTER_SYNC=1

echo "==> full bootstrap mode"
echo "   SKIP_EXISTING_MODELS=$SKIP_EXISTING_MODELS"
echo "   SKIP_EXISTING_CUSTOM_NODES=$SKIP_EXISTING_CUSTOM_NODES"
echo "   RESTART_COMFYUI_AFTER_SYNC=$RESTART_COMFYUI_AFTER_SYNC"

exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/runpod_bootstrap.sh"
