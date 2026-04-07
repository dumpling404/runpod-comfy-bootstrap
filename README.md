# runpod-comfy-bootstrap

Bootstrap scripts for running official `runpod/comfyui` Pods with persistent `models/` and `custom_nodes/` on a mounted volume.

## What this repo does

- sync your bootstrap repo into the Pod
- install Python dependencies for existing `custom_nodes`
- install `ComfyUI-Impact-Subpack` if needed
- optionally restart ComfyUI after setup

## Files

- `runpod_bootstrap.sh`
  Main Pod bootstrap script.
- `install_custom_node_deps.sh`
  Scans `custom_nodes/*/requirements.txt` and installs dependencies.

## Intended workflow

1. Start an official `runpod/comfyui` Pod.
2. Mount a persistent volume so `models/` and `custom_nodes/` survive Pod recreation.
3. Copy or clone this repo into the Pod.
4. Run:

```bash
bash runpod_bootstrap.sh
```

If you want ComfyUI to restart automatically after setup:

```bash
RESTART_COMFYUI_AFTER_SYNC=1 bash runpod_bootstrap.sh
```

## Important assumptions

- `models/` and `custom_nodes/` are already on the mounted volume.
- This repo is for Pod/bootstrap orchestration, not business workflows.
- Output browsing should usually stay local; the volume is mainly for heavy persistent assets.

## Main environment variables

```bash
NSFW_IP_REPO_URL=https://github.com/dumpling404/nsfw-ip.git
NSFW_IP_REF=prod
REPO_DIR=/opt/nsfw-ip
COMFY_ROOT=/workspace/ComfyUI
CUSTOM_NODES_DIR=/workspace/ComfyUI/custom_nodes
PYTHON_BIN=python3
PIP_INSTALL_ARGS=
RESTART_COMFYUI_AFTER_SYNC=0
```

## Notes

- `custom_nodes` on the volume do not make dependencies magically available.
- Every new Pod / new image / new node update still needs a dependency install pass.
- `ComfyUI-Impact-Subpack` is required for `UltralyticsDetectorProvider`.
