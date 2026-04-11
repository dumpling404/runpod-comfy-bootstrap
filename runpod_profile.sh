#!/bin/bash
# Single config file for RunPod bootstrap.
# Non-secret defaults live here.
# Secret values like RUNPOD_SECRET_HG_TOKEN must still be injected from the Pod environment.

export COMFY_ROOT="${COMFY_ROOT:-/workspace/runpod-slim/ComfyUI}"
export CUSTOM_NODES_DIR="${CUSTOM_NODES_DIR:-$COMFY_ROOT/custom_nodes}"
export PYTHON_BIN="${PYTHON_BIN:-python3}"
export RESTART_COMFYUI_AFTER_SYNC="${RESTART_COMFYUI_AFTER_SYNC:-1}"
export PIP_INSTALL_ARGS="${PIP_INSTALL_ARGS:-}"
export RUNPOD_VOLUME_ROOT="${RUNPOD_VOLUME_ROOT:-/runpod-volume}"
export QWEN_NODES_PATCH_URL="${QWEN_NODES_PATCH_URL:-https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/main/fixed-textencode-node/nodes_qwen.v2.py}"

export MODEL_SPECS="${MODEL_SPECS:-$(cat <<'EOF'
checkpoints/waiIllustriousSDXL_v160.safetensors|highscoregames12018/checkpoint-collection-Main|waiIllustriousSDXL_v160.safetensors|main
checkpoints/Qwen-Rapid-AIO-NSFW-v23.safetensors|Phr00t/Qwen-Image-Edit-Rapid-AIO|v23/Qwen-Rapid-AIO-NSFW-v23.safetensors|main
vae/sdxl_vae.safetensors|stabilityai/sdxl-vae|sdxl_vae.safetensors|main
controlnet/controlnet_union_sdxl.safetensors|xinsir/controlnet-union-sdxl-1.0|diffusion_pytorch_model.safetensors|main
ultralytics/bbox/face_yolov8m.pt|Bingsu/adetailer|face_yolov8m.pt|main
EOF
)}"

export CUSTOM_NODE_SPECS="${CUSTOM_NODE_SPECS:-$(cat <<'EOF'
ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager.git|main
ComfyUI-Impact-Pack|https://github.com/ltdrdata/ComfyUI-Impact-Pack.git|Main
ComfyUI-Impact-Subpack|https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git|main
ComfyUI-KJNodes|https://github.com/kijai/ComfyUI-KJNodes.git|main
comfyui_controlnet_aux|https://github.com/Fannovel16/comfyui_controlnet_aux.git|main
EOF
)}"

# Private LoRA bundle.
# Leave RUNPOD_SECRET_HG_TOKEN out of git; inject it via Pod env if you want these to download.
export PRIVATE_LORA_REPO="${PRIVATE_LORA_REPO:-dumpling404/mylora}"
export PRIVATE_LORA_REF="${PRIVATE_LORA_REF:-main}"
export PRIVATE_LORA_SUBDIR="${PRIVATE_LORA_SUBDIR:-loras}"

# LoRA 文件列表。新增或删除 LoRA 只改这里，不动 runpod_bootstrap.sh。
export PRIVATE_LORA_FILES="${PRIVATE_LORA_FILES:-"
xieyan_v1.safetensors
oda-non_IL.safetensors
realism_lora_by_stable_yogi_v3_lite.safetensors
urban_womens_style.safetensors
"}"
