# runpod-comfy-bootstrap

Bootstrap scripts for running official `runpod/comfyui` Pods with reusable `models/` and `custom_nodes/` bootstrap logic.

## What this repo does

- sync your bootstrap repo into the Pod
- sync default custom nodes from git into the mounted volume or local workspace
- download default public models from Hugging Face or direct URLs
- install Python dependencies for existing `custom_nodes`
- install `ComfyUI-Impact-Subpack` if needed
- install `onnxruntime` for `ComfyUI-Impact-Pack`
- optionally restart ComfyUI after setup

## Files

- `bootstrap_entry.sh`
  Thin entrypoint that updates this repo and delegates to `runpod_bootstrap.sh`.
- `runpod_bootstrap.sh`
  Main Pod bootstrap script.
- `install_custom_node_deps.sh`
  Scans `custom_nodes/*/requirements.txt` and installs dependencies.
- `manifests/model_specs.default.txt`
  Built-in default model manifest.
- `manifests/custom_node_specs.default.txt`
  Built-in default custom node manifest.

## Intended workflow

1. Start an official `runpod/comfyui` Pod.
2. Optionally mount a persistent volume if you want `models/` and `custom_nodes/` to survive Pod recreation.
3. Copy or clone this repo into the Pod.
4. Use this as RunPod Startup Command:

```bash
cd /workspace/runpod-comfy-bootstrap && bash bootstrap_entry.sh
```

5. Or run manually:

```bash
RESTART_COMFYUI_AFTER_SYNC=1 bash /workspace/runpod-comfy-bootstrap/runpod_bootstrap.sh
```

## Main environment variables

```bash
BOOTSTRAP_REPO_URL=https://github.com/dumpling404/runpod-comfy-bootstrap.git
BOOTSTRAP_REPO_REF=main
BOOTSTRAP_REPO_DIR=/workspace/runpod-comfy-bootstrap
COMFY_ROOT=/workspace/ComfyUI
CUSTOM_NODES_DIR=/workspace/ComfyUI/custom_nodes
PYTHON_BIN=python3
PIP_INSTALL_ARGS=
RESTART_COMFYUI_AFTER_SYNC=0
HF_TOKEN=hf_xxx_for_private_or_gated_repos
PRIVATE_LORA_REPO=dumpling404/mylora
PRIVATE_LORA_REF=main
PRIVATE_LORA_SUBDIR=loras
MODEL_SPECS_FILE=/workspace/model_specs.txt
DEFAULT_MODEL_SPECS_FILE=/workspace/runpod-comfy-bootstrap/manifests/model_specs.default.txt
MODEL_DOWNLOAD_BASE_URL=https://huggingface.co
SKIP_EXISTING_MODELS=1
CUSTOM_NODE_SPECS_FILE=/workspace/custom_node_specs.txt
DEFAULT_CUSTOM_NODE_SPECS_FILE=/workspace/runpod-comfy-bootstrap/manifests/custom_node_specs.default.txt
SKIP_EXISTING_CUSTOM_NODES=1
```

## Model manifest format

Supported forms:

```text
<target_path_under_models>|<repo_id>|<repo_file>|<revision_optional>
<target_path_under_models>|<direct_url>
```

Example:

```text
checkpoints/waiIllustriousSDXL_v160.safetensors|highscoregames12018/checkpoint-collection-Main|waiIllustriousSDXL_v160.safetensors|main
# loras/oda-non_IL.safetensors|https://civitai.com/api/download/models/1227393?type=Model&format=SafeTensor
```

Notes:

- `target_path_under_models` is relative to `ComfyUI/models/`
- private or gated HF repos need `HF_TOKEN`
- direct URLs bypass `HF_TOKEN`
- some sources such as Civitai may still require their own auth and should stay in a private override manifest
- existing files are skipped when `SKIP_EXISTING_MODELS=1`

## Custom node manifest format

```text
<directory_name>|<git_repo_url>|<ref_optional>
```

Example:

```text
ComfyUI-Manager|https://github.com/ltdrdata/ComfyUI-Manager.git|main
ComfyUI-Impact-Pack|https://github.com/ltdrdata/ComfyUI-Impact-Pack.git|Main
ComfyUI-KJNodes|https://github.com/kijai/ComfyUI-KJNodes.git|main
comfyui_controlnet_aux|https://github.com/Fannovel16/comfyui_controlnet_aux.git|main
```

## Built-in defaults

A fresh Pod can bootstrap without any custom manifest. Current defaults cover:

- `waiIllustriousSDXL_v160.safetensors`
- `sdxl_vae.safetensors`
- `controlnet_union_sdxl.safetensors`
- `face_yolov8m.pt`
- `ComfyUI-Manager`
- `ComfyUI-Impact-Pack`
- `ComfyUI-KJNodes`
- `comfyui_controlnet_aux`
- `ComfyUI-Impact-Subpack`
- `onnxruntime` for Impact-Pack

Private or unstable assets should not be hard-coded into the public defaults.

If you keep your own LoRAs in a private Hugging Face repo, set these Pod env vars:

```bash
HF_TOKEN=...
PRIVATE_LORA_REPO=dumpling404/mylora
PRIVATE_LORA_REF=main
PRIVATE_LORA_SUBDIR=loras
```

Then bootstrap will additionally pull:

- `loras/xieyan_v1.safetensors`
- `loras/oda-non_IL.safetensors`

from that private repo using `HF_TOKEN`.

## Public / private boundary

- This repo is public bootstrap only.
- Do not put private business repo paths into the RunPod Startup Command.
- Private prompt, workflow, story, and character repos should stay separate from this bootstrap layer.
