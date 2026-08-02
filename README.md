# ComfyUI Windows 整合包 / ComfyUI Windows Modpack

基于 Docker 镜像 `comfyui_with_nodes.Dockerfile` 移植的 Windows 解压即用整合包。
A Windows extract-and-run modpack ported from the `comfyui_with_nodes.Dockerfile` Docker image.

包含 / Includes: ComfyUI 主程序、48 个 custom_nodes、SageAttention（源码编译）、Qwen3-TTS / Qwen3-ASR 独立运行环境、全套模型自动下载。

---

## 目录结构 / Directory Layout

```
comfyui-windows-modpack/
├── init.bat                    # 初始化脚本 (venv / ComfyUI / 节点 / SageAttention / 模型)
├── run.bat                     # 一键启动脚本 (首次运行自动调用 init.bat)
├── qwen3_asr_requirements.txt  # Qwen3-ASR 独立环境依赖清单
├── README.md                   # 本文档
├── init.log                    # 初始化运行日志 (由 init.bat 自动生成, 控制台与日志同时输出)
├── python_comfyui/             # ComfyUI 主环境 (venv, 由 init.bat 生成)
├── python_qwentts/             # Qwen3-TTS 独立环境 (venv, 由 init.bat 生成)
├── python_qwenasr/             # Qwen3-ASR 独立环境 (venv, 由 init.bat 生成)
├── SageAttention/              # SageAttention 源码 (由 init.bat 生成)
└── ComfyUI/                    # ComfyUI 主程序 + custom_nodes + models (由 init.bat 生成)
```

## 系统要求 / System Requirements

| 项目 / Item | 要求 / Requirement |
|---|---|
| 系统 / OS | Windows 10/11 64 位 (64-bit) |
| 显卡 / GPU | NVIDIA 显卡，建议 Ampere (30系) 及以上 |
| 显存 / VRAM | 建议 12GB+（视模型而定） |
| Python | 3.13（必需，与 Docker 镜像一致；脚本检测不到 3.13 会提示安装） |
| Git | https://git-scm.com/download/win |
| CUDA Toolkit | 12.8+（**仅 SageAttention 源码编译需要**，可选，有 nvcc 则编译、否则尝试预编译包） |
| VS Build Tools | C++ 桌面开发工作负载（仅 SageAttention 源码编译需要） |
| 磁盘空间 / Disk | 环境约 20GB + 模型 80GB+（可跳过模型下载，见 FAQ） |

## 快速开始 / Quick Start

1. 解压整合包到任意目录（路径建议不含中文与空格）
   Extract the package to any folder (avoid non-ASCII characters and spaces in the path).
2. 双击 `run.bat` —— 首次运行会自动执行 `init.bat` 完成初始化（耗时较长，含模型下载）
   Double-click `run.bat` — first run automatically executes `init.bat` (takes a while, includes model downloads).
   或先手动双击 `init.bat` 完成初始化，再双击 `run.bat`。
   Or run `init.bat` manually first, then `run.bat`.
3. 浏览器自动打开 `http://127.0.0.1:8188` 即完成。
   Browser opens `http://127.0.0.1:8188` automatically.

## init.bat 做了什么 / What init.bat does

| 步骤 / Step | 内容 / Content |
|---|---|
| 0 | 检查 Git / Python 3.14 / NVIDIA 显卡 (nvidia-smi) / nvcc |
| 1 | 用系统 Python 创建 3 个独立 venv：`python_comfyui`、`python_qwentts`、`python_qwenasr` |
| 2 | 克隆 ComfyUI 源码 |
| 3 | 安装 PyTorch (cu130，阿里云镜像，失败自动回退官方源) + ComfyUI requirements |
| 4 | 克隆 48 个 custom_nodes 并逐个安装其 requirements（Qwen3-TTS/ASR 除外，独立安装） |
| 5 | Qwen3-TTS 独立环境：soundfile + ComfyUI-Qwen3-TTS 依赖（qwen-tts 等） |
| 6 | Qwen3-ASR 独立环境：qwen-asr / modelscope / transformers==4.57.6 等 |
| 7 | 编译安装 SageAttention（自动检测 GPU 计算能力，CUDA_ARCH 对应；无 nvcc 则回退 pip 预编译包） |
| 8 | 下载全部模型（Qwen-Image / Wan2.2 / LTX-2.3 / Z-Image / Stable-Audio-3 / Qwen3-TTS / Qwen3-ASR / IndexTTS-2 等，已存在的自动跳过，可中断后重跑续传） |

所有步骤均可重复运行，已完成的部分自动跳过（幂等）。All steps are idempotent — re-running skips what's done.

日志：init.bat 的全部输出（含 stderr）会同时写入根目录 `init.log`（UTF-8 编码），控制台同步显示。脚本消息为英文，因 cmd.exe 无法可靠解析 .bat 中的中文（中文说明见本文档）。
Logging: every line init.bat prints (including stderr) is teed to `init.log` (UTF-8) while the console shows it live. Script messages are English because cmd.exe cannot reliably parse Chinese inside .bat files; the Chinese docs are right here.

三个独立环境的缘由（与 Docker 一致）：
Three separate venvs (same as Docker): qwen-tts 依赖 `transformers==4.57.3`，而 qwen-asr 依赖 `transformers==4.57.6`，版本互斥，必须隔离。节点通过 `QWEN_VENV_PYTHON` / `QWEN_ASR_VENV_PYTHON` 环境变量（run.bat 中设置）找到各自的解释器。

## 常见问题 / FAQ

**Q1: 下载太慢 / 失败？**
脚本已默认使用 `HF_ENDPOINT=https://hf-mirror.com`（国内镜像）和清华 PyPI 源，与 Docker 镜像一致。Git 克隆失败会自动切换 ghfast.top / ghproxy 代理重试。失败项在重新运行 `init.bat` 后自动续传。

**Q2: 不想下载全部模型？**
两种方式（等价）：
- 命令行参数：`init.bat --no-models`，只搭建环境不下载模型
- 编辑 `init.bat` 顶部，将 `set "SKIP_MODEL_DOWNLOAD=0"` 改为 `1`

之后可手动执行第 8 步需要的下载命令。

**Q3: pynini 安装失败？**
pynini 在 Windows 上无官方预编译包，属正常现象。Qwen3-TTS 不依赖 pynini，可正常使用。

**Q4: SageAttention 编译失败？**
需要 CUDA Toolkit 12.8+（含 nvcc）和 VS Build Tools（C++ 工作负载）。不安装也能运行 ComfyUI，仅影响长视频等场景的注意力加速。脚本会自动尝试 pip 预编译包作为回退。

**Q5: 显存不足？**
修改 `run.bat` 中的 `CACHE_RAM=46.5`（WanVideoWrapper 缓存限制）为显卡显存的一半左右，例如 12GB 显存设为 6。

**Q6: 修改端口？**
修改 `run.bat` 中的 `--port 8188` 与浏览器地址。

**Q7: 重新分发整合包？**
删掉 `ComfyUI/`、`python_*/`、`SageAttention/` 目录后即可压缩为可分发的纯净包，接收方解压双击 `run.bat` 即可。

---

## English / 说明 (English)

Ported from the Docker image built by `docker/comfyui/comfyui_with_nodes.Dockerfile`. The init script (`init.bat`) creates three isolated venvs (`python_comfyui`, `python_qwentts`, `python_qwenasr`) because qwen-tts and qwen-asr pin mutually exclusive transformers versions (4.57.3 vs 4.57.6), clones ComfyUI + 48 custom nodes, builds SageAttention from source with auto-detected CUDA architecture (falls back to pip wheel if nvcc is absent), and downloads the full model set from `hf-mirror.com` with resume support.

Environment variables set by `run.bat`: `QWEN_VENV_PYTHON`, `QWEN_ASR_VENV_PYTHON` (used by the Qwen3-TTS/ASR nodes to locate their interpreters), `HF_ENDPOINT` (mirror), and `CACHE_RAM` (WanVideoWrapper VRAM cache cap).

Notes:
- Python 3.13 is required (same as the Docker image, which uses python3.13). The script refuses to run if 3.13 is not found (`py -3.13`, falling back to a `python` on PATH that reports 3.13).
- PyTorch cu130 is installed via the Aliyun wheel mirror first, falling back to the official `download.pytorch.org/whl/cu130` index, then the default index.
- `pynini` has no Windows wheels — installation is best-effort and skipped with a warning; Qwen3-TTS works without it.
- All steps are resumable: re-running `init.bat` skips existing venvs, clones, installed packages, and downloaded models.
