#!/bin/bash
# Public RunPod profile.
# Keep non-secret bootstrap defaults here so the pod can source one file and run.
# Secret values like HF_TOKEN must still be injected from the Pod environment.

export COMFY_ROOT="${COMFY_ROOT:-/workspace/runpod-slim/ComfyUI}"
export CUSTOM_NODES_DIR="${CUSTOM_NODES_DIR:-$COMFY_ROOT/custom_nodes}"
export PYTHON_BIN="${PYTHON_BIN:-python3}"
export RESTART_COMFYUI_AFTER_SYNC="${RESTART_COMFYUI_AFTER_SYNC:-1}"
export PIP_INSTALL_ARGS="${PIP_INSTALL_ARGS:-}"
export RUNPOD_VOLUME_ROOT="${RUNPOD_VOLUME_ROOT:-/runpod-volume}"

export MODEL_SPECS="${MODEL_SPECS:-$(cat <<'EOF'
checkpoints/waiIllustriousSDXL_v160.safetensors|highscoregames12018/checkpoint-collection-Main|waiIllustriousSDXL_v160.safetensors|main
vae/sdxl_vae.safetensors|stabilityai/sdxl-vae|sdxl_vae.safetensors|main
controlnet/controlnet_union_sdxl.safetensors|xinsir/controlnet-union-sdxl-1.0|diffusion_pytorch_model.safetensors|main
ultralytics/bbox/face_yolov8m.pt|Bingsu/adetailer|face_yolov8m.pt|main
EOF
)}"

export CUSTOM_NODE_SPECS="${CUSTOM_NODE_SPECS:-$(cat <<'EOF'
ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager.git|main
ComfyUI-Impact-Pack|https://github.com/ltdrdata/ComfyUI-Impact-Pack.git|Main
ComfyUI-KJNodes|https://github.com/kijai/ComfyUI-KJNodes.git|main
comfyui_controlnet_aux|https://github.com/Fannovel16/comfyui_controlnet_aux.git|main
EOF
)}"

# Optional private LoRA bundle.
# Leave HF_TOKEN out of git; inject it via Pod env if you want these to download.
export PRIVATE_LORA_REPO="${PRIVATE_LORA_REPO:-dumpling404/mylora}"
export PRIVATE_LORA_REF="${PRIVATE_LORA_REF:-main}"
export PRIVATE_LORA_SUBDIR="${PRIVATE_LORA_SUBDIR:-loras}"

