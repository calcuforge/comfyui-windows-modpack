# ComfyUI Windows 整合包

基于 Docker 镜像 `comfyui_with_nodes.Dockerfile` 移植的 Windows 解压即用整合包。

[English documentation](README.md)

**包含：** ComfyUI 主程序、46 个 custom_nodes、SageAttention、Qwen3-TTS / Qwen3-ASR 独立运行环境、全套模型自动下载。

## 目录结构

```
comfyui-windows-modpack/
├── init.bat                    # 初始化脚本 (venv / ComfyUI / 节点 / SageAttention / 模型)
├── run.bat                     # 一键启动脚本 (首次运行自动调用 init.bat)
├── qwen3_asr_requirements.txt  # Qwen3-ASR 独立环境依赖清单
├── README.md                   # 英文文档
├── README.zh-CN.md             # 本文档（中文）
├── init.log                    # 初始化运行日志 (由 init.bat 自动生成, 控制台与日志同时输出)
├── python_comfyui/             # ComfyUI 主环境 (venv, 由 init.bat 生成)
├── python_qwentts/             # Qwen3-TTS 独立环境 (venv, 由 init.bat 生成)
├── python_qwenasr/             # Qwen3-ASR 独立环境 (venv, 由 init.bat 生成)
├── SageAttention/              # SageAttention 源码 (由 init.bat 生成)
├── ffmpeg/                     # FFmpeg 可执行文件, 随包自带 (由 init.bat 生成)
└── ComfyUI/                    # ComfyUI 主程序 + custom_nodes + models (由 init.bat 生成)
```

## 系统要求

| 项目 | 要求 |
|---|---|
| 系统 | Windows 10/11 64 位 |
| 显卡 | NVIDIA 显卡，建议 Ampere (30系) 及以上 |
| 显存 | 建议 12GB+（视模型而定） |
| Python | **3.13（必需，与 Docker 镜像一致；脚本检测不到 3.13 会提示安装）** |
| Git | https://git-scm.com/download/win |
| CUDA Toolkit | 12.8+（**仅 SageAttention 源码编译需要**，可选，无 nvcc 则回退预编译包） |
| VS Build Tools | C++ 桌面开发工作负载（仅 SageAttention 源码编译需要） |
| 磁盘空间 | 环境约 20GB + 模型 80GB+（可跳过模型下载，见 FAQ） |

## 快速开始

1. 解压整合包到任意目录（路径建议不含中文与空格）。
2. 双击 `run.bat` —— 首次运行会自动执行 `init.bat` 完成初始化（耗时较长，含模型下载）。
   或先手动双击 `init.bat` 完成初始化，再双击 `run.bat`。
3. 浏览器在**服务就绪后**自动打开 `http://127.0.0.1:8188`（启动器轮询端口，无固定延迟）。

## init.bat 做了什么

| 步骤 | 内容 |
|---|---|
| 0 | 检查 Git / Python 3.13 / NVIDIA 显卡 (nvidia-smi) / nvcc |
| 1 | 用系统 Python 创建 3 个独立 venv：`python_comfyui`、`python_qwentts`、`python_qwenasr` |
| 2 | 克隆 ComfyUI 源码 |
| 3 | 安装 PyTorch (cu130，阿里云镜像，失败自动回退官方源) + ComfyUI requirements |
| 4 | 克隆 46 个 custom_nodes 并逐个安装其 requirements（Qwen3-TTS/ASR 除外，独立安装） |
| 5 | Qwen3-TTS 独立环境：soundfile + ComfyUI-Qwen3-TTS 依赖（qwen-tts 等） |
| 6 | Qwen3-ASR 独立环境：qwen-asr / modelscope / transformers==4.57.6 等 |
| 7 | 编译安装 SageAttention（自动检测 GPU 计算能力，CUDA_ARCH 对应；无 nvcc 则回退 pip 预编译包） |
| 7.5 | 下载 FFmpeg 到 `ffmpeg/`（BtbN win64 构建，github 直连 → ghfast → ghproxy 逐级回退） |
| 8 | 下载全部模型（Qwen-Image / Wan2.2 / LTX-2.3 / Z-Image / Stable-Audio-3 / Qwen3-TTS / Qwen3-ASR / IndexTTS-2 等，已存在的自动跳过，可中断后重跑续传） |

所有步骤均可重复运行，已完成的部分自动跳过（幂等）。

**日志：** init.bat 的全部输出（含 stderr）会同时写入根目录 `init.log`（UTF-8 编码），控制台同步显示。脚本消息为英文，因 cmd.exe 无法可靠解析 .bat 中的中文。

**三个独立环境的缘由（与 Docker 一致）：** qwen-tts 依赖 `transformers==4.57.3`，而 qwen-asr 依赖 `transformers==4.57.6`，版本互斥，必须隔离。节点通过 `QWEN_VENV_PYTHON` / `QWEN_ASR_VENV_PYTHON` 环境变量（run.bat 中设置）找到各自的解释器。

**FFmpeg：** init.bat 会把 FFmpeg（BtbN win64 构建）安装到项目内 `ffmpeg\bin`（约 200MB，已有则跳过）。run.bat 启动时把 `ffmpeg\bin` 前置到 PATH，所有节点（VideoHelperSuite、ffmpeg-python 等）均可直接使用，不依赖系统安装。

## 常见问题

**Q1: 下载太慢 / 失败？**
脚本已默认使用 `HF_ENDPOINT=https://hf-mirror.com`（国内镜像）和清华 PyPI 源，与 Docker 镜像一致。Git 克隆失败会自动切换 ghfast.top / ghproxy 代理重试；git 克隆带低速超时保护，代理挂起会快速失败而不是无限等待。失败项在重新运行 `init.bat` 后自动续传。

**Q2: 不想下载全部模型？**
两种方式（等价）：
- 命令行参数：`init.bat --no-models`，只搭建环境不下载模型
- 编辑 `init.bat` 顶部，将 `set "SKIP_MODEL_DOWNLOAD=0"` 改为 `1`

之后可手动下载需要的模型。

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

## 补充说明

- **Python 3.13 为必需版本**（与 Docker 镜像一致）。检测方式：`py -3.13`，回退检查 PATH 上的 `python` 是否为 3.13。
- PyTorch cu130 安装链路：阿里云镜像 → 官方 `download.pytorch.org/whl/cu130` → 默认源，逐级回退。
- deepspeed（IndexTTS 节点的依赖）在 Windows 上无法编译。脚本对失败的节点依赖会逐包重试、跳过无法构建的包——IndexTTS 节点可正常加载使用。
- 已移除 ComfyUI-NAG（与最新 ComfyUI 不兼容）与 ComfyUI-QwenImageLoraLoader 节点。
- 所有步骤可断点续跑：重跑 `init.bat` 会跳过已存在的 venv、克隆、已装依赖和已下载模型。
