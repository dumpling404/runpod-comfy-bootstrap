# runpod-comfy-bootstrap

目标就两件事：

- `runpod_profile.sh`
  唯一配置清单。把要装的 custom nodes、models、私有 LoRA 源都写这里。
- `runpod_bootstrap.sh`
  唯一执行脚本。读取 `runpod_profile.sh`，然后一次性把节点、依赖、模型、LoRA、ComfyUI 都处理完。

`bootstrap_entry.sh` 只是 RunPod Startup Command 的薄入口，用来先更新仓库再执行 `runpod_bootstrap.sh`。

## 当前行为

执行 `runpod_bootstrap.sh` 时会：

1. 探测 `ComfyUI` 根目录
2. 如果有 volume 就桥接 `models/` 和 `custom_nodes/`
3. 按 `runpod_profile.sh` 拉齐全部 custom nodes
4. 按 `runpod_profile.sh` 下载全部 models
5. 安装每个 custom node 的 `requirements.txt`
6. 执行每个 custom node 的 `install.py`
7. 补装 `onnxruntime`
8. 按配置重启 ComfyUI

## 启动方式

RunPod Startup Command:

```bash
cd /workspace/runpod-comfy-bootstrap && bash bootstrap_entry.sh
```

手动执行：

```bash
bash /workspace/runpod-comfy-bootstrap/runpod_bootstrap.sh
```

云端单独补齐 edit 模型链：

```bash
bash /workspace/runpod-comfy-bootstrap/install_edit_models.sh
```

## 关键环境变量

```bash
BOOTSTRAP_REPO_URL=https://github.com/dumpling404/runpod-comfy-bootstrap.git
BOOTSTRAP_REPO_REF=main
BOOTSTRAP_REPO_DIR=/workspace/runpod-comfy-bootstrap
PROFILE_FILE=/workspace/runpod-comfy-bootstrap/runpod_profile.sh
COMFY_ROOT=/workspace/runpod-slim/ComfyUI
CUSTOM_NODES_DIR=/workspace/runpod-slim/ComfyUI/custom_nodes
PYTHON_BIN=python3
PIP_INSTALL_ARGS=
RESTART_COMFYUI_AFTER_SYNC=1
RUNPOD_SECRET_HG_TOKEN=hf_xxx_for_private_or_gated_repos
PRIVATE_LORA_REPO=dumpling404/mylora
PRIVATE_LORA_REF=main
PRIVATE_LORA_SUBDIR=loras
MODEL_DOWNLOAD_BASE_URL=https://huggingface.co
SKIP_EXISTING_MODELS=1
SKIP_EXISTING_CUSTOM_NODES=1
```

## 清单格式

`MODEL_SPECS`:

```text
<target_path_under_models>|<repo_id>|<repo_file>|<revision_optional>
<target_path_under_models>|<direct_url>
```

`CUSTOM_NODE_SPECS`:

```text
<directory_name>|<git_repo_url>|<ref_optional>
```

## 私有 LoRA

如果 `PRIVATE_LORA_REPO` 不为空，就会额外拉：

- `loras/xieyan_v1.safetensors`
- `loras/oda-non_IL.safetensors`

这时必须提供：

```bash
RUNPOD_SECRET_HG_TOKEN=...
```

## 边界

- 这个仓库只负责 Pod 环境恢复
- 私有 prompt / workflow / story 不进这个仓库
