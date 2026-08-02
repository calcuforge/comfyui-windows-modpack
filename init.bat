@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM ============================================================
REM  ComfyUI Windows 整合包 - 初始化脚本
REM  逻辑移植自 docker/comfyui/comfyui_with_nodes.Dockerfile
REM  包含: 3个独立venv / ComfyUI / 48个custom_nodes / SageAttention / 模型下载
REM  初始化完成后, 双击 run.bat 即可启动
REM ============================================================

REM ==================== 配置 ====================
set "ROOT=%~dp0"
set "COMFYUI_DIR=%ROOT%ComfyUI"
set "NODES_DIR=%COMFYUI_DIR%\custom_nodes"
set "MODEL_DIR=%COMFYUI_DIR%\models"
set "VENV_COMFY=%ROOT%python_comfyui"
set "VENV_QWENTTS=%ROOT%python_qwentts"
set "VENV_QWENASR=%ROOT%python_qwenasr"

set "PIP_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple"
set "PIP_FLAGS=-i %PIP_INDEX% --disable-pip-version-check"
set "PYTORCH_MIRROR=https://mirrors.aliyun.com/pytorch-wheels/cu130"
set "GHFAST=https://ghfast.top/https://github.com"
set "GHPROXY=http://ghproxy.calcuforge.com:8080/https://github.com"

REM HuggingFace 镜像 (与Docker镜像一致, 国内加速)
set "HF_ENDPOINT=https://hf-mirror.com"
set "HF_HUB_ENABLE_HF_XET=0"
set "HF_HUB_DISABLE_XET=1"

REM hf 下载命令行 (huggingface_hub 附带)
set "HF_BIN=%VENV_COMFY%\Scripts\hf.exe"
if not exist "%HF_BIN%" set "HF_BIN=%VENV_COMFY%\Scripts\huggingface-cli.exe"

REM 设为 1 可跳过模型下载, 只搭建运行环境
set "SKIP_MODEL_DOWNLOAD=0"

REM ==================== 0. 基础环境检查 ====================
echo [0/8] 检查基础环境...

where git >nul 2>nul
if errorlevel 1 (
    echo [错误] 未检测到 Git, 请先安装 https://git-scm.com/download/win
    goto :fail
)

set "PY="
for /f "delims=" %%i in ('py -3.14 -c "import sys;print(sys.executable)" 2^>nul') do set "PY=%%i"
if not defined PY for /f "delims=" %%i in ('py -3.13 -c "import sys;print(sys.executable)" 2^>nul') do set "PY=%%i"
if not defined PY (
    for /f "delims=" %%i in ('python -c "import sys;v=sys.version_info;print(sys.executable) if (v.major,v.minor)>= (3,11) else None" 2^>nul') do set "PY=%%i"
)
if not defined PY (
    echo [错误] 未检测到 Python 3.11+, 请先安装 Python 3.14: https://www.python.org/downloads/
    echo        安装时请勾选 "Add python.exe to PATH", 或安装 py 启动器
    goto :fail
)
echo [0/8] Python: "%PY%"

set "SAGE_SKIP=1"
where nvidia-smi >nul 2>nul
if not errorlevel 1 (
    set "SAGE_SKIP=0"
    set "CUDA_ARCH="
    for /f "skip=1 tokens=*" %%i in ('nvidia-smi --query-gpu=compute_cap --format=csv 2^>nul') do set "CUDA_ARCH=%%i"
    if not defined CUDA_ARCH set "CUDA_ARCH=8.6"
    echo [0/8] NVIDIA GPU 计算能力: !CUDA_ARCH!
) else (
    echo [0/8] 未检测到 NVIDIA 显卡 (nvidia-smi), 将跳过 SageAttention 编译
)
where nvcc >nul 2>nul
if errorlevel 1 (
    echo [0/8] 未检测到 nvcc (CUDA Toolkit), SageAttention 将只尝试 pip 预编译包
    echo        如需源码编译, 请安装 CUDA Toolkit 12.8+: https://developer.nvidia.com/cuda-downloads
)

REM ==================== 1. 创建三个独立虚拟环境 ====================
echo [1/8] 创建虚拟环境 (python_comfyui / python_qwentts / python_qwenasr)...
"%PY%" -m venv "%VENV_COMFY%"
if errorlevel 1 ( echo [错误] 创建 python_comfyui 失败 & goto :fail )
"%PY%" -m venv "%VENV_QWENTTS%"
if errorlevel 1 ( echo [错误] 创建 python_qwentts 失败 & goto :fail )
"%PY%" -m venv "%VENV_QWENASR%"
if errorlevel 1 ( echo [错误] 创建 python_qwenasr 失败 & goto :fail )

set "PYCOM=%VENV_COMFY%\Scripts\python.exe"
set "PYTTS=%VENV_QWENTTS%\Scripts\python.exe"
set "PYASR=%VENV_QWENASR%\Scripts\python.exe"

for %%V in ("%VENV_COMFY%" "%VENV_QWENTTS%" "%VENV_QWENASR%") do (
    echo [1/8] 升级pip: %%~nxV
    "%%~V\Scripts\python.exe" -m pip install -q -i %PIP_INDEX% --upgrade pip
)

REM ==================== 2. 克隆 ComfyUI ====================
echo [2/8] 克隆 ComfyUI...
call :git_clone_root "comfyanonymous/ComfyUI" "%COMFYUI_DIR%"

REM ==================== 3. ComfyUI 基础依赖 ====================
echo [3/8] 安装 ComfyUI 基础依赖...
"%PYCOM%" -m pip install %PIP_FLAGS% -U setuptools wheel huggingface_hub

echo [3/8] 安装 PyTorch cu130 (阿里云镜像, 失败自动回退)...
"%PYCOM%" -m pip install %PIP_FLAGS% -f %PYTORCH_MIRROR% torch torchvision torchaudio
if errorlevel 1 (
    echo [3/8] 阿里云镜像失败, 回退官方 cu130 源...
    "%PYCOM%" -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130
)
if errorlevel 1 (
    echo [3/8] 官方 cu130 失败, 回退默认源...
    "%PYCOM%" -m pip install %PIP_FLAGS% torch torchvision torchaudio
)
if errorlevel 1 ( echo [错误] PyTorch 安装失败, 请检查网络 & goto :fail )

"%PYCOM%" -m pip install %PIP_FLAGS% ninja==1.11.1.4
if errorlevel 1 "%PYCOM%" -m pip install %PIP_FLAGS% ninja

echo [3/8] 安装 ComfyUI requirements.txt...
"%PYCOM%" -m pip install %PIP_FLAGS% -r "%COMFYUI_DIR%\requirements.txt"
if errorlevel 1 ( echo [错误] ComfyUI 依赖安装失败 & goto :fail )

REM ==================== 4. custom_nodes ====================
echo [4/8] 克隆 custom_nodes 并安装依赖...
call :git_clone "ltdrdata/ComfyUI-Manager"
call :git_clone "Suzie1/ComfyUI_Comfyroll_CustomNodes"
call :git_clone "city96/ComfyUI-GGUF"
call :git_clone "kijai/ComfyUI-KJNodes"
call :git_clone "pythongosssss/ComfyUI-Custom-Scripts"
call :git_clone "yolain/ComfyUI-Easy-Use"
call :git_clone "chflame163/ComfyUI_LayerStyle"
call :git_clone "rgthree/rgthree-comfy"
call :git_clone "Fannovel16/ComfyUI-Frame-Interpolation"
call :git_clone "orssorbit/ComfyUI-wanBlockswap"
call :git_clone "M1kep/ComfyLiterals"
call :git_clone "Kosinkadink/ComfyUI-VideoHelperSuite"
call :git_clone "stduhpf/ComfyUI-WanMoeKSampler" "WanMoeKSampler"
call :git_clone "kijai/ComfyUI-MelBandRoFormer"
call :git_clone "kijai/ComfyUI-GIMM-VFI"
call :git_clone "kijai/ComfyUI-WanVideoWrapper"
call :git_clone "lihaoyun6/ComfyUI-FlashVSR_Ultra_Fast"
call :git_clone "kijai/ComfyUI-MMAudio"
call :git_clone "phazei/ComfyUI-HunyuanVideo-Foley"
call :git_clone "ussoewwin/ComfyUI-QwenImageLoraLoader"
call :git_clone "Derfuu/Derfuu_ComfyUI_ModdedNodes"
call :git_clone "sipherxyz/comfyui-art-venture"
call :git_clone "jamesWalker55/comfyui-various"
call :git_clone "kadirnar/ComfyUI-Transformers"
call :git_clone "godmt/ComfyUI-List-Utils"
call :git_clone "glowcone/comfyui-string-converter"
call :git_clone "hgabha/WWAA-CustomNodes"
call :git_clone "TenStrip/10S-Comfy-nodes" "10S_Nodes"
call :git_clone "ChenDarYen/ComfyUI-NAG"
call :git_clone "ApolloLX/ComfyUI_Robot"
call :git_clone "kijai/ComfyUI-PromptRelay"
call :git_clone "AICoderTudou/ComfyUI-TT-Resolution_selector-Node"
call :git_clone "melMass/comfy_mtb"
call :git_clone "LAOGOU-666/Comfyui-Memory_Cleanup"
call :git_clone "WASasquatch/was-node-suite-comfyui"
call :git_clone "Comfy-Org/Nvidia_RTX_Nodes_ComfyUI"
call :git_clone "princepainter/ComfyUI-PainterI2V"
call :git_clone "princepainter/ComfyUI-PainteraI2V"
call :git_clone "princepainter/Comfyui-PainterAudioCut"
call :git_clone "princepainter/ComfyUI-PainterMultiF2V"
call :git_clone "niknah/audio-general-ComfyUI"
call :git_clone "ryanontheinside/ComfyUI_RyanOnTheInside"
call :git_clone "cubiq/ComfyUI_essentials"
call :git_clone "christian-byrne/audio-separation-nodes-comfyui"
call :git_clone "goohai/Goohaitools-comfyui"
call :git_clone "AsonZhang/ComfyUI_IndexTTS"
call :git_clone "AsonZhang/ComfyUI-Qwen3-TTS"
call :git_clone "AsonZhang/ComfyUI-Qwen3-ASR"

REM 安装各节点 requirements.txt (Qwen3-TTS/Qwen3-ASR 在独立venv中安装, 跳过)
for /d %%d in ("%NODES_DIR%\*") do (
    set "NODE=%%~nxd"
    if /i not "!NODE!"=="ComfyUI-Qwen3-TTS" if /i not "!NODE!"=="ComfyUI-Qwen3-ASR" (
        if exist "%%d\requirements.txt" (
            echo [4/8] 安装依赖: !NODE!
            "%PYCOM%" -m pip install %PIP_FLAGS% -r "%%d\requirements.txt"
            if errorlevel 1 echo [4/8] 警告: !NODE! 依赖安装失败, 已跳过
        )
    )
)

REM 与Docker镜像一致的附加包 (失败不影响使用)
"%PYCOM%" -m pip install %PIP_FLAGS% --upgrade pip setuptools wheel build wheel-stub >nul 2>&1
"%PYCOM%" -m pip install %PIP_FLAGS% nvidia-vfx
if errorlevel 1 echo [4/8] 警告: nvidia-vfx 安装失败 (非必需, 已跳过)

REM ==================== 5. Qwen3-TTS 独立环境 ====================
echo [5/8] 安装 Qwen3-TTS 独立环境...
"%PYTTS%" -m pip install %PIP_FLAGS% soundfile
echo [5/8] pynini: Windows 无官方预编译包, 尝试失败则跳过
"%PYTTS%" -m pip install %PIP_FLAGS% pynini --only-binary=:all:
if errorlevel 1 echo [5/8] 提示: pynini 在 Windows 不可用, 已跳过 (Qwen3-TTS 不依赖它)
"%PYTTS%" -m pip install %PIP_FLAGS% -r "%NODES_DIR%\ComfyUI-Qwen3-TTS\requirements.txt"
if errorlevel 1 (
    echo [警告] Qwen3-TTS 依赖安装失败, 请检查网络后重新运行本脚本
)

REM ==================== 6. Qwen3-ASR 独立环境 ====================
echo [6/8] 安装 Qwen3-ASR 独立环境...
"%PYASR%" -m pip install %PIP_FLAGS% -r "%ROOT%qwen3_asr_requirements.txt"
if errorlevel 1 (
    echo [警告] Qwen3-ASR 依赖安装失败, 请检查网络后重新运行本脚本
)

REM ==================== 7. 编译安装 SageAttention ====================
echo [7/8] 编译安装 SageAttention...
if "%SAGE_SKIP%"=="1" goto :sage_done
where nvcc >nul 2>nul
if errorlevel 1 (
    echo [7/8] 未检测到 nvcc, 尝试 pip 预编译包...
    "%PYCOM%" -m pip install %PIP_FLAGS% sageattention
    if errorlevel 1 echo [7/8] 警告: sageattention 预编译包不可用, 已跳过 (不影响 ComfyUI 运行)
    goto :sage_done
)
echo [7/8] 检测到 nvcc, 开始源码编译 SageAttention, CUDA_ARCH=!CUDA_ARCH! ...
"%PYCOM%" -m pip install %PIP_FLAGS% packaging
if not exist "%ROOT%SageAttention" (
    git clone --depth 1 "https://github.com/AsonZhang/SageAttention" "%ROOT%SageAttention" >nul 2>&1
    if errorlevel 1 git clone --depth 1 "%GHFAST%/AsonZhang/SageAttention" "%ROOT%SageAttention" >nul 2>&1
    if errorlevel 1 git clone --depth 1 "%GHPROXY%/AsonZhang/SageAttention" "%ROOT%SageAttention"
)
if not exist "%ROOT%SageAttention\setup.py" (
    echo [7/8] SageAttention 源码克隆失败, 已跳过
    goto :sage_done
)
cd /d "%ROOT%SageAttention"
set "EXT_PARALLEL=4"
set "MAX_JOBS=32"
set "NVCC_APPEND_FLAGS=--threads 16"
set "TORCH_CUDA_ARCH_LIST=!CUDA_ARCH!"
"%PYCOM%" setup.py install
if errorlevel 1 (
    echo [7/8] 源码编译失败, 尝试 pip 预编译包...
    "%PYCOM%" -m pip install %PIP_FLAGS% sageattention
)
cd /d "%ROOT%"
:sage_done

REM ==================== 8. 下载模型 ====================
echo [8/8] 下载模型 (已存在的自动跳过, 可随时中断, 重新运行继续)...
if "%SKIP_MODEL_DOWNLOAD%"=="1" goto :models_done

REM --- VAE ---
call :single_download "Comfy-Org/Qwen-Image_ComfyUI" "split_files/vae/qwen_image_vae.safetensors" "%MODEL_DIR%\vae" "qwen_image_vae.safetensors"
call :single_download "Comfy-Org/Wan_2.1_ComfyUI_repackaged" "split_files/vae/wan_2.1_vae.safetensors" "%MODEL_DIR%\vae" "wan_2.1_vae.safetensors"
call :single_download "Comfy-Org/z_image_turbo" "split_files/vae/ae.safetensors" "%MODEL_DIR%\vae" "ae.safetensors"
call :single_download "unsloth/LTX-2.3-GGUF" "vae/ltx-2.3-22b-dev_video_vae.safetensors" "%MODEL_DIR%\vae" "ltx-2.3-22b-dev_video_vae.safetensors"
call :single_download "unsloth/LTX-2.3-GGUF" "vae/ltx-2.3-22b-dev_audio_vae.safetensors" "%MODEL_DIR%\vae" "ltx-2.3-22b-dev_audio_vae.safetensors"

REM --- UNET / DIFFUSION / CHECKPOINTS ---
call :single_download "cardamonnl/Qwen-Image-Edit-2511-int8-convrot" "qwen_image_edit_2511_int8_convrot.safetensors" "%MODEL_DIR%\unet" "qwen_image_edit_2511_int8_convrot.safetensors"
call :single_download "Comfy-Org/z_image" "split_files/diffusion_models/z_image_bf16.safetensors" "%MODEL_DIR%\diffusion_models" "z_image_bf16.safetensors"
call :single_download "Winnougan/Wan2.2-INT8-Convrot" "wan2.2_i2v_high_noise_14B_int8_convrot.safetensors" "%MODEL_DIR%\diffusion_models" "wan2.2_i2v_high_noise_14B_int8_convrot.safetensors"
call :single_download "Winnougan/Wan2.2-INT8-Convrot" "wan2.2_i2v_low_noise_14B_int8_convrot.safetensors" "%MODEL_DIR%\diffusion_models" "wan2.2_i2v_low_noise_14B_int8_convrot.safetensors"
call :single_download "Kijai/LTX2.3_comfy" "diffusion_models/ltx-2.3-22b-distilled-1.1_transformer_only_int8_convrot.safetensors" "%MODEL_DIR%\diffusion_models" "ltx-2.3-22b-distilled-1.1_transformer_only_int8_convrot.safetensors"
call :single_download "Comfy-Org/stable-audio-3" "checkpoints/stable_audio_3_medium.safetensors" "%MODEL_DIR%\checkpoints" "stable_audio_3_medium.safetensors"

REM --- LORAS ---
call :single_download "lightx2v/Qwen-Image-Edit-2511-Lightning" "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors" "%MODEL_DIR%\loras" "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors"
call :single_download "lightx2v/Qwen-Image-Edit-2511-Lightning" "Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors" "%MODEL_DIR%\loras" "Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors"
call :single_download "alibaba-pai/Wan2.2-Fun-Reward-LoRAs" "Wan2.2-Fun-A14B-InP-high-noise-MPS.safetensors" "%MODEL_DIR%\loras" "Wan2.2-Fun-A14B-InP-high-noise-MPS.safetensors"
call :single_download "alibaba-pai/Wan2.2-Fun-Reward-LoRAs" "Wan2.2-Fun-A14B-InP-low-noise-HPS2.1.safetensors" "%MODEL_DIR%\loras" "Wan2.2-Fun-A14B-InP-low-noise-HPS2.1.safetensors"
call :single_download "UDCAI/Z-Image-Fun-Distill-ComfyUI" "Z-Image-Fun-Lora-Distill-8-Steps-2602_UDCAI_ComfyUI.safetensors" "%MODEL_DIR%\loras" "Z-Image-Fun-Lora-Distill-8-Steps-2602_UDCAI_ComfyUI.safetensors"
call :single_download "alibaba-pai/Z-Image-Fun-Lora-Distill" "Z-Image-Fun-Lora-Distill-4-Steps-2602-ComfyUI.safetensors" "%MODEL_DIR%\loras" "Z-Image-Fun-Lora-Distill-4-Steps-2602-ComfyUI.safetensors"
call :single_download "wangkanai/wan21-lightx2v-i2v-14b-480p" "loras/wan/wan21-lightx2v-i2v-14b-480p-cfg-step-distill-rank128-bf16.safetensors" "%MODEL_DIR%\loras" "wan21-lightx2v-i2v-14b-480p-cfg-step-distill-rank128-bf16.safetensors"
call :single_download "LiconStudio/VBVR-wan2.2-comfy-bf16" "VBVR-wan2.2-I2V-14B-high-SNR-Calibrated-Hybrid.safetensors" "%MODEL_DIR%\loras" "VBVR-wan2.2-I2V-14B-high-SNR-Calibrated-Hybrid.safetensors"
call :single_download "Kijai/WanVideo_comfy" "LoRAs/Stable-Video-Infinity/v2.0/SVI_v2_PRO_Wan2.2-I2V-A14B_HIGH_lora_rank_128_fp16.safetensors" "%MODEL_DIR%\loras" "SVI_v2_PRO_Wan2.2-I2V-A14B_HIGH_lora_rank_128_fp16.safetensors"
call :single_download "Kijai/WanVideo_comfy" "LoRAs/Stable-Video-Infinity/v2.0/SVI_v2_PRO_Wan2.2-I2V-A14B_LOW_lora_rank_128_fp16.safetensors" "%MODEL_DIR%\loras" "SVI_v2_PRO_Wan2.2-I2V-A14B_LOW_lora_rank_128_fp16.safetensors"
call :single_download "Kotajiro/LTX23-ruri_LoRA" "LTX23-ruri_R02.safetensors" "%MODEL_DIR%\loras" "LTX23-ruri_R02.safetensors"
call :single_download "Muapi/valiantcat-ltx-2.3-transition-lora" "valiantcat-ltx-2.3-transition-lora.safetensors" "%MODEL_DIR%\loras" "valiantcat-ltx-2.3-transition-lora.safetensors"
call :single_download "LiconStudio/Ltx2.3-VBVR-lora-I2V" "Ltx2.3-Licon-VBVR-I2V-240K-R32.safetensors" "%MODEL_DIR%\loras" "Ltx2.3-Licon-VBVR-I2V-240K-R32.safetensors"

REM --- TEXT ENCODERS ---
call :single_download "Comfy-Org/Qwen-Image_ComfyUI" "split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" "%MODEL_DIR%\text_encoders" "qwen_2.5_vl_7b_fp8_scaled.safetensors"
call :single_download "Comfy-Org/Wan_2.2_ComfyUI_Repackaged" "split_files/text_encoders/umt5_xxl_fp16.safetensors" "%MODEL_DIR%\text_encoders" "umt5_xxl_fp16.safetensors"
call :single_download "Comfy-Org/z_image" "split_files/text_encoders/qwen_3_4b.safetensors" "%MODEL_DIR%\text_encoders" "qwen_3_4b.safetensors"
call :single_download "GitMylo/LTX-2-comfy_gemma_fp8_e4m3fn" "gemma_3_12B_it_fp8_e4m3fn.safetensors" "%MODEL_DIR%\text_encoders" "gemma_3_12B_it_fp8_e4m3fn.safetensors"
call :single_download "unsloth/LTX-2.3-GGUF" "text_encoders/ltx-2.3-22b-dev_embeddings_connectors.safetensors" "%MODEL_DIR%\text_encoders" "ltx-2.3-22b-dev_embeddings_connectors.safetensors"
call :single_download "Kijai/LTX2.3_comfy" "text_encoders/ltx-2.3_text_projection_bf16.safetensors" "%MODEL_DIR%\text_encoders" "ltx-2.3_text_projection_bf16.safetensors"
call :single_download "Comfy-Org/stable-audio-3" "text_encoders/t5gemma_b_b_ul2.safetensors" "%MODEL_DIR%\text_encoders" "t5gemma_b_b_ul2.safetensors"
call :single_download "Comfy-Org/Qwen3.5" "text_encoders/qwen3.5_2b_bf16.safetensors" "%MODEL_DIR%\text_encoders" "qwen3.5_2b_bf16.safetensors"

REM --- TTS 组件 ---
call :single_download "nvidia/bigvgan_v2_22khz_80band_256x" "bigvgan_generator.pt" "%MODEL_DIR%\TTS\bigvgan_v2_22khz_80band_256x" "bigvgan_generator.pt"
call :single_download "nvidia/bigvgan_v2_22khz_80band_256x" "config.json" "%MODEL_DIR%\TTS\bigvgan_v2_22khz_80band_256x" "config.json"
call :single_download "funasr/campplus" "campplus_cn_common.bin" "%MODEL_DIR%\TTS\campplus" "campplus_cn_common.bin"
call :single_download "amphion/MaskGCT" "semantic_codec/model.safetensors" "%MODEL_DIR%\TTS\MaskGCT\semantic_codec" "model.safetensors"

REM --- 整目录模型 ---
call :single_download_folder "IndexTeam/IndexTTS-2" "%MODEL_DIR%\TTS\IndexTTS-2"
call :single_download_folder "facebook/w2v-bert-2.0" "%MODEL_DIR%\TTS\w2v-bert-2.0"
call :single_download_folder "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign" "%MODEL_DIR%\Qwen3-TTS\Qwen3-TTS-12Hz-1.7B-VoiceDesign"
call :single_download_folder "Qwen/Qwen3-TTS-12Hz-1.7B-Base" "%MODEL_DIR%\Qwen3-TTS\Qwen3-TTS-12Hz-1.7B-Base"
call :single_download_folder "Qwen/Qwen3-ASR-1.7B" "%MODEL_DIR%\Qwen3-ASR\Qwen3-ASR-1.7B"

REM --- 空目录占位 (与Docker镜像一致) ---
if not exist "%MODEL_DIR%\FlashVSR-v1.1" mkdir "%MODEL_DIR%\FlashVSR-v1.1"
if not exist "%MODEL_DIR%\transformers\TencentGameMate\chinese-wav2vec2-base" mkdir "%MODEL_DIR%\transformers\TencentGameMate\chinese-wav2vec2-base"
if not exist "%MODEL_DIR%\mmaudio\nvidia" mkdir "%MODEL_DIR%\mmaudio\nvidia"
if not exist "%MODEL_DIR%\prompt_generator" mkdir "%MODEL_DIR%\prompt_generator"
if not exist "%MODEL_DIR%\latent_upscale_models" mkdir "%MODEL_DIR%\latent_upscale_models"
if not exist "%MODEL_DIR%\model_patches" mkdir "%MODEL_DIR%\model_patches"
if not exist "%MODEL_DIR%\foley" mkdir "%MODEL_DIR%\foley"
if not exist "%MODEL_DIR%\omnivoice" mkdir "%MODEL_DIR%\omnivoice"

:models_done
echo.
echo ============================================================
echo  初始化全部完成!
echo  现在双击 run.bat 启动 ComfyUI
echo ============================================================
echo.
pause
exit /b 0

:fail
echo.
echo ============================================================
echo  初始化失败, 请根据上方错误信息处理后重新运行本脚本
echo ============================================================
pause
exit /b 1

REM ==================== 子程序 ====================

:git_clone_root
set "REPO=%~1"
set "DEST=%~2"
if exist "%DEST%\main.py" ( echo [2/8] 跳过: ComfyUI 已存在 & exit /b 0 )
if exist "%DEST%" rmdir /s /q "%DEST%"
echo [2/8] 克隆 %REPO% ...
git clone --depth 1 "https://github.com/%REPO%" "%DEST%" >nul 2>&1
if not errorlevel 1 exit /b 0
if exist "%DEST%" rmdir /s /q "%DEST%"
git clone --depth 1 "%GHFAST%/%REPO%" "%DEST%" >nul 2>&1
if not errorlevel 1 exit /b 0
if exist "%DEST%" rmdir /s /q "%DEST%"
git clone --depth 1 "%GHPROXY%/%REPO%" "%DEST%"
if errorlevel 1 ( echo [错误] ComfyUI 克隆失败 & goto :fail )
exit /b 0

:git_clone
set "REPO=%~1"
set "NAME=%~2"
if not defined NAME for %%a in ("%REPO%") do set "NAME=%%~nxa"
set "DEST=%NODES_DIR%\%NAME%"
if exist "%DEST%" (
    if exist "%DEST%\.git" ( echo [4/8] 跳过: %NAME% 已存在 & exit /b 0 )
    rmdir /s /q "%DEST%"
)
echo [4/8] 克隆 %REPO% ...
git clone --depth 1 "https://github.com/%REPO%" "%DEST%" >nul 2>&1
if not errorlevel 1 exit /b 0
if exist "%DEST%" rmdir /s /q "%DEST%"
git clone --depth 1 "%GHFAST%/%REPO%" "%DEST%" >nul 2>&1
if not errorlevel 1 exit /b 0
if exist "%DEST%" rmdir /s /q "%DEST%"
git clone --depth 1 "%GHPROXY%/%REPO%" "%DEST%"
if errorlevel 1 echo [4/8] 警告: 克隆失败 %REPO% (不影响其他节点)
exit /b 0

:single_download
set "REPO=%~1"
set "FILE=%~2"
set "TARGET_DIR=%~3"
set "TARGET_FILE=%~4"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"
if exist "%TARGET_DIR%\%TARGET_FILE%" ( echo [8/8] 跳过: %TARGET_FILE% 已存在 & exit /b 0 )
for /l %%i in (1,1,5) do (
    echo [8/8] 下载 %%i/5: %REPO% / %FILE%
    "%HF_BIN%" download "%REPO%" "%FILE%" --local-dir "%TARGET_DIR%"
    if not errorlevel 1 exit /b 0
    echo [8/8] 下载失败, 30秒后重试...
    %SystemRoot%\System32\timeout.exe /t 30 /nobreak >nul
)
echo [8/8] 失败: %REPO% / %FILE%
exit /b 0

:single_download_folder
set "REPO=%~1"
set "TARGET_DIR=%~2"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"
if exist "%TARGET_DIR%\*" ( echo [8/8] 跳过: %~nx2 已存在 & exit /b 0 )
for /l %%i in (1,1,5) do (
    echo [8/8] 下载 %%i/5 目录: %REPO%
    "%HF_BIN%" download "%REPO%" --local-dir "%TARGET_DIR%"
    if not errorlevel 1 exit /b 0
    echo [8/8] 下载失败, 30秒后重试...
    %SystemRoot%\System32\timeout.exe /t 30 /nobreak >nul
)
echo [8/8] 失败: %REPO%
exit /b 0
