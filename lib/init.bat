@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  ComfyUI Windows Modpack - init script
REM  Ported from docker/comfyui/comfyui_with_nodes.Dockerfile
REM  Steps: 3 isolated venvs / ComfyUI / 46 custom_nodes /
REM         SageAttention build / model downloads
REM  After init completes, double-click run.bat to start.
REM  NOTE: batch files must stay ASCII-only (cmd.exe cannot
REM  reliably parse UTF-8 Chinese in .bat files).
REM ============================================================

REM ==================== Logging (all output also written to init.log) ====================
for %%i in ("%~dp0..") do set "ROOT=%%~fi\"
if "%1"=="--tee" goto :main
powershell -NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::GetEncoding([Console]::OutputCodePage); Add-Content -LiteralPath \"%~dp0init.log\" -Encoding utf8 -Value \"================================================\"; Add-Content -LiteralPath \"%~dp0init.log\" -Encoding utf8 -Value (\"[ \" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + \" ] init.bat started\"); cmd /d /c \"\"%~f0\"\" --tee %* 2>&1 | ForEach-Object { $t=$_.ToString(); $t; $t | Out-File -LiteralPath \"%~dp0init.log\" -Append -Encoding utf8 }; exit $LASTEXITCODE"
set "ERR=%errorlevel%"
echo.
echo Init log saved to: %~dp0init.log
pause
exit /b %ERR%

:main
REM ==================== Config ====================
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

REM git timeout protection (proxies can hang silently; fail fast and retry next mirror)
set "GIT_HTTP_LOW_SPEED_LIMIT=1000"
set "GIT_HTTP_LOW_SPEED_TIME=60"
set "GIT_HTTP_CONNECT_TIMEOUT=30"

REM HuggingFace mirror (same as Docker image, faster in China)
set "HF_ENDPOINT=https://hf-mirror.com"
set "HF_HUB_ENABLE_HF_XET=0"
set "HF_HUB_DISABLE_XET=1"

REM hf CLI (shipped with huggingface_hub)
set "HF_BIN=%VENV_COMFY%\Scripts\hf.exe"
if not exist "%HF_BIN%" set "HF_BIN=%VENV_COMFY%\Scripts\huggingface-cli.exe"

REM Set to 1 to skip model downloads, or pass --no-models on the command line
set "SKIP_MODEL_DOWNLOAD=0"
for %%a in (%*) do if /i "%%a"=="--no-models" set "SKIP_MODEL_DOWNLOAD=1"

REM ==================== 0. Environment check ====================
echo [0/8] Checking environment...

where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Git not found. Install it first: https://git-scm.com/download/win
    goto :fail
)

set "PY="
for /f "delims=" %%i in ('py -3.13 -c "import sys;print(sys.executable)" 2^>nul') do set "PY=%%i"
if not defined PY (
    for /f "delims=" %%i in ('python -c "import sys;v=sys.version_info;print(sys.executable) if (v.major,v.minor)==(3,13) else None" 2^>nul') do set "PY=%%i"
)
if not defined PY (
    echo [ERROR] Python 3.13 not found. Install Python 3.13: https://www.python.org/downloads/
    echo        During install, check "Add python.exe to PATH" or install the py launcher
    goto :fail
)
echo [0/8] Python 3.13: "%PY%"

set "SAGE_SKIP=1"
where nvidia-smi >nul 2>nul
if not errorlevel 1 (
    set "SAGE_SKIP=0"
    set "CUDA_ARCH="
    for /f "skip=1 tokens=*" %%i in ('nvidia-smi --query-gpu=compute_cap --format=csv 2^>nul') do set "CUDA_ARCH=%%i"
    if not defined CUDA_ARCH set "CUDA_ARCH=8.6"
    echo [0/8] NVIDIA GPU compute capability: !CUDA_ARCH!
) else (
    echo [0/8] No NVIDIA GPU found ^(nvidia-smi missing^), SageAttention build will be skipped
)
where nvcc >nul 2>nul
if errorlevel 1 (
    echo [0/8] nvcc ^(CUDA Toolkit^) not found, SageAttention will only try the pip wheel
    echo        To build from source, install CUDA Toolkit 12.8+: https://developer.nvidia.com/cuda-downloads
)

REM ==================== 1. Create three isolated venvs ====================
echo [1/8] Creating venvs (python_comfyui / python_qwentts / python_qwenasr)...
"%PY%" -m venv "%VENV_COMFY%"
if errorlevel 1 ( echo [ERROR] Failed to create python_comfyui & goto :fail )
"%PY%" -m venv "%VENV_QWENTTS%"
if errorlevel 1 ( echo [ERROR] Failed to create python_qwentts & goto :fail )
"%PY%" -m venv "%VENV_QWENASR%"
if errorlevel 1 ( echo [ERROR] Failed to create python_qwenasr & goto :fail )

set "PYCOM=%VENV_COMFY%\Scripts\python.exe"
set "PYTTS=%VENV_QWENTTS%\Scripts\python.exe"
set "PYASR=%VENV_QWENASR%\Scripts\python.exe"

for %%V in ("%VENV_COMFY%" "%VENV_QWENTTS%" "%VENV_QWENASR%") do (
    echo [1/8] Upgrading pip: %%~nxV
    "%%~V\Scripts\python.exe" -m pip install -q -i %PIP_INDEX% --upgrade pip
)

REM ==================== 2. Clone ComfyUI ====================
echo [2/8] Cloning ComfyUI...
call :git_clone_root "comfyanonymous/ComfyUI" "%COMFYUI_DIR%"

REM ==================== 3. ComfyUI core dependencies ====================
echo [3/8] Installing ComfyUI core dependencies...
"%PYCOM%" -m pip install %PIP_FLAGS% -U setuptools wheel huggingface_hub

echo [3/8] Installing PyTorch cu130 (Aliyun mirror, auto fallback)...
"%PYCOM%" -m pip install %PIP_FLAGS% -f %PYTORCH_MIRROR% torch torchvision torchaudio
if errorlevel 1 (
    echo [3/8] Aliyun mirror failed, falling back to official cu130 index...
    "%PYCOM%" -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu130
)
if errorlevel 1 (
    echo [3/8] Official cu130 failed, falling back to default index...
    "%PYCOM%" -m pip install %PIP_FLAGS% torch torchvision torchaudio
)
if errorlevel 1 ( echo [ERROR] PyTorch install failed, check your network & goto :fail )

"%PYCOM%" -m pip install %PIP_FLAGS% ninja==1.11.1.4
if errorlevel 1 "%PYCOM%" -m pip install %PIP_FLAGS% ninja

echo [3/8] Installing ComfyUI requirements.txt...
"%PYCOM%" -m pip install %PIP_FLAGS% -r "%COMFYUI_DIR%\requirements.txt"
if errorlevel 1 ( echo [ERROR] ComfyUI dependency install failed & goto :fail )

REM ==================== 4. Custom nodes ====================
echo [4/8] Cloning custom_nodes and installing their dependencies...
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
call :git_clone "Derfuu/Derfuu_ComfyUI_ModdedNodes"
call :git_clone "sipherxyz/comfyui-art-venture"
call :git_clone "jamesWalker55/comfyui-various"
call :git_clone "kadirnar/ComfyUI-Transformers"
call :git_clone "godmt/ComfyUI-List-Utils"
call :git_clone "glowcone/comfyui-string-converter"
call :git_clone "hgabha/WWAA-CustomNodes"
call :git_clone "TenStrip/10S-Comfy-nodes" "10S_Nodes"
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

REM Install each node's requirements.txt (Qwen3-TTS/Qwen3-ASR are installed in their own venvs)
REM pip-internal git clones (e.g. git+https deps) can crawl on direct github,
REM so rewrite github URLs to the ghfast proxy while pip runs
set "GIT_CONFIG_COUNT=1"
set "GIT_CONFIG_KEY_0=url.https://ghfast.top/https://github.com/.insteadOf"
set "GIT_CONFIG_VALUE_0=https://github.com/"
for /d %%d in ("%NODES_DIR%\*") do (
    set "NODE=%%~nxd"
    if /i not "!NODE!"=="ComfyUI-Qwen3-TTS" if /i not "!NODE!"=="ComfyUI-Qwen3-ASR" (
        if exist "%%d\requirements.txt" (
            echo [4/8] Installing dependencies: !NODE!
            REM strip already-installed git+ deps: pip re-clones them on every run otherwise
            set "REQ_TMP="
            findstr /b "git+" "%%d\requirements.txt" >nul 2>&1
            if not errorlevel 1 (
                set "REQ_TMP=%TEMP%\comfyui_req_!NODE!.txt"
                type "%%d\requirements.txt" > "!REQ_TMP!"
                for /f "usebackq eol=# delims=" %%p in ("%%d\requirements.txt") do (
                    set "PKG=%%p"
                    if "!PKG:~0,4!"=="git+" (
                        for %%s in ("!PKG!") do set "LAST=%%~nxs"
                        for /f "delims=@" %%s in ("!LAST!") do set "LAST=%%s"
                        "%PYCOM%" -m pip list --format=freeze 2>nul | findstr /i /c:"!LAST!" >nul
                        if not errorlevel 1 (
                            echo [4/8] Skip already-installed git dep: !LAST!
                            findstr /v /c:"!PKG!" "!REQ_TMP!" > "!REQ_TMP!.tmp"
                            move /y "!REQ_TMP!.tmp" "!REQ_TMP!" >nul
                        )
                    )
                )
            )
            if defined REQ_TMP (
                "%PYCOM%" -m pip install %PIP_FLAGS% -r "!REQ_TMP!"
                del "!REQ_TMP!" >nul 2>&1
            ) else (
                "%PYCOM%" -m pip install %PIP_FLAGS% -r "%%d\requirements.txt"
            )
            if errorlevel 1 (
                echo [4/8] WARNING: batch install failed for !NODE!, retrying package by package...
                for /f "usebackq eol=# delims=" %%p in ("%%d\requirements.txt") do (
                    set "PKG=%%p"
                    REM skip git+ deps here: pip re-clones them every time, and the batch step already handled them
                    if not "!PKG:~0,4!"=="git+" (
                        "%PYCOM%" -m pip install %PIP_FLAGS% "%%p" >nul 2>&1
                        if errorlevel 1 echo [4/8] WARNING: skipped !NODE! dep: %%p
                    )
                )
            )
        )
    )
)
set "GIT_CONFIG_COUNT="

REM Extra packages from the Docker image (failure is non-fatal)
"%PYCOM%" -m pip install %PIP_FLAGS% --upgrade pip setuptools wheel build wheel-stub >nul 2>&1
"%PYCOM%" -m pip install %PIP_FLAGS% nvidia-vfx
if errorlevel 1 echo [4/8] WARNING: nvidia-vfx install failed (optional, skipped)

REM ==================== 5. Qwen3-TTS isolated venv ====================
echo [5/8] Installing Qwen3-TTS isolated venv...
"%PYTTS%" -m pip install %PIP_FLAGS% soundfile
echo [5/8] pynini: no official Windows wheel, trying and skipping on failure
"%PYTTS%" -m pip install %PIP_FLAGS% pynini --only-binary=:all:
if errorlevel 1 echo [5/8] NOTE: pynini unavailable on Windows, skipped (Qwen3-TTS does not depend on it)
"%PYTTS%" -m pip install %PIP_FLAGS% -r "%NODES_DIR%\ComfyUI-Qwen3-TTS\requirements.txt"
if errorlevel 1 (
    echo [WARNING] Qwen3-TTS dependency install failed, re-run this script after fixing network
)

REM ==================== 6. Qwen3-ASR isolated venv ====================
echo [6/8] Installing Qwen3-ASR isolated venv...
"%PYASR%" -m pip install %PIP_FLAGS% -r "%ROOT%lib\qwen3_asr_requirements.txt"
if errorlevel 1 (
    echo [WARNING] Qwen3-ASR dependency install failed, re-run this script after fixing network
)

REM ==================== 7. Build and install SageAttention ====================
echo [7/8] Building SageAttention...
if "%SAGE_SKIP%"=="1" goto :sage_done
where nvcc >nul 2>nul
if errorlevel 1 (
    echo [7/8] nvcc not found, trying the pip wheel...
    "%PYCOM%" -m pip install %PIP_FLAGS% sageattention
    if errorlevel 1 echo [7/8] WARNING: sageattention wheel unavailable, skipped ^(ComfyUI still works^)
    goto :sage_done
)
echo [7/8] nvcc found, building from source, CUDA_ARCH=!CUDA_ARCH! ...
"%PYCOM%" -m pip install %PIP_FLAGS% packaging
if not exist "%ROOT%SageAttention" (
    git clone --depth 1 "https://github.com/AsonZhang/SageAttention" "%ROOT%SageAttention" >nul 2>&1
    if errorlevel 1 git clone --depth 1 "%GHFAST%/AsonZhang/SageAttention" "%ROOT%SageAttention" >nul 2>&1
    if errorlevel 1 git clone --depth 1 "%GHPROXY%/AsonZhang/SageAttention" "%ROOT%SageAttention"
)
if not exist "%ROOT%SageAttention\setup.py" (
    echo [7/8] SageAttention source clone failed, skipped
    goto :sage_done
)
cd /d "%ROOT%SageAttention"
set "EXT_PARALLEL=4"
set "MAX_JOBS=32"
set "NVCC_APPEND_FLAGS=--threads 16"
set "TORCH_CUDA_ARCH_LIST=!CUDA_ARCH!"
"%PYCOM%" setup.py install
if errorlevel 1 (
    echo [7/8] Source build failed, trying the pip wheel...
    "%PYCOM%" -m pip install %PIP_FLAGS% sageattention
)
cd /d "%ROOT%"
:sage_done

REM ==================== FFmpeg (installed into the project folder) ====================
echo [ffmpeg] Checking FFmpeg...
if exist "%ROOT%ffmpeg\bin\ffmpeg.exe" (
    echo [ffmpeg] Already installed: %ROOT%ffmpeg\bin
    goto :ffmpeg_done
)
echo [ffmpeg] Downloading FFmpeg build (~200MB, github with proxy fallback)...
set "FFMPEG_ZIP=%ROOT%ffmpeg_tmp.zip"
curl -L --retry 2 --connect-timeout 30 --max-time 1800 -o "%FFMPEG_ZIP%" "https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip" >nul 2>&1
if errorlevel 1 curl -L --retry 2 --connect-timeout 30 --max-time 1800 -o "%FFMPEG_ZIP%" "%GHFAST%/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip" >nul 2>&1
if errorlevel 1 curl -L --retry 2 --connect-timeout 30 --max-time 1800 -o "%FFMPEG_ZIP%" "%GHPROXY%/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip" >nul 2>&1
if errorlevel 1 (
    echo [ffmpeg] WARNING: FFmpeg download failed, skipped
    goto :ffmpeg_done
)
echo [ffmpeg] Extracting...
powershell -NoProfile -Command "Expand-Archive -LiteralPath \"%FFMPEG_ZIP%\" -DestinationPath \"%ROOT%ffmpeg_tmp\" -Force"
if errorlevel 1 (
    echo [ffmpeg] WARNING: FFmpeg extract failed, skipped
    goto :ffmpeg_done
)
if not exist "%ROOT%ffmpeg\bin" mkdir "%ROOT%ffmpeg\bin"
for /d %%d in ("%ROOT%ffmpeg_tmp\*") do (
    if exist "%%d\bin\ffmpeg.exe" (
        move /y "%%d\bin\ffmpeg.exe" "%ROOT%ffmpeg\bin\" >nul
        move /y "%%d\bin\ffprobe.exe" "%ROOT%ffmpeg\bin\" >nul
        move /y "%%d\bin\ffplay.exe" "%ROOT%ffmpeg\bin\" >nul
    )
)
del "%FFMPEG_ZIP%" >nul 2>&1
rmdir /s /q "%ROOT%ffmpeg_tmp" >nul 2>&1
if exist "%ROOT%ffmpeg\bin\ffmpeg.exe" (
    echo [ffmpeg] Installed: %ROOT%ffmpeg\bin\ffmpeg.exe
) else (
    echo [ffmpeg] WARNING: ffmpeg.exe not found after extract, skipped
)
:ffmpeg_done

REM ==================== 8. Download models ====================
echo [8/8] Downloading models (existing files are skipped, safe to interrupt and re-run)...
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

REM --- TTS components ---
call :single_download "nvidia/bigvgan_v2_22khz_80band_256x" "bigvgan_generator.pt" "%MODEL_DIR%\TTS\bigvgan_v2_22khz_80band_256x" "bigvgan_generator.pt"
call :single_download "nvidia/bigvgan_v2_22khz_80band_256x" "config.json" "%MODEL_DIR%\TTS\bigvgan_v2_22khz_80band_256x" "config.json"
call :single_download "funasr/campplus" "campplus_cn_common.bin" "%MODEL_DIR%\TTS\campplus" "campplus_cn_common.bin"
call :single_download "amphion/MaskGCT" "semantic_codec/model.safetensors" "%MODEL_DIR%\TTS\MaskGCT\semantic_codec" "model.safetensors"

REM --- Whole-folder models ---
call :single_download_folder "IndexTeam/IndexTTS-2" "%MODEL_DIR%\TTS\IndexTTS-2"
call :single_download_folder "facebook/w2v-bert-2.0" "%MODEL_DIR%\TTS\w2v-bert-2.0"
call :single_download_folder "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign" "%MODEL_DIR%\Qwen3-TTS\Qwen3-TTS-12Hz-1.7B-VoiceDesign"
call :single_download_folder "Qwen/Qwen3-TTS-12Hz-1.7B-Base" "%MODEL_DIR%\Qwen3-TTS\Qwen3-TTS-12Hz-1.7B-Base"
call :single_download_folder "Qwen/Qwen3-ASR-1.7B" "%MODEL_DIR%\Qwen3-ASR\Qwen3-ASR-1.7B"

REM --- Placeholder empty dirs (same as Docker image) ---
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
echo  Init completed!
echo  Now double-click run.bat to start ComfyUI
echo ============================================================
echo.
pause
exit /b 0

:fail
echo.
echo ============================================================
echo  Init failed. Fix the errors above and re-run this script
echo ============================================================
pause
exit /b 1

REM ==================== Subroutines ====================

:git_clone_root
set "REPO=%~1"
set "DEST=%~2"
if exist "%DEST%\main.py" ( echo [2/8] Skip: ComfyUI already exists & exit /b 0 )
if exist "%DEST%" rmdir /s /q "%DEST%"
echo [2/8] Cloning %REPO% ...
git clone --depth 1 "https://github.com/%REPO%" "%DEST%" >nul 2>&1
if not errorlevel 1 exit /b 0
if exist "%DEST%" rmdir /s /q "%DEST%"
git clone --depth 1 "%GHFAST%/%REPO%" "%DEST%" >nul 2>&1
if not errorlevel 1 exit /b 0
if exist "%DEST%" rmdir /s /q "%DEST%"
git clone --depth 1 "%GHPROXY%/%REPO%" "%DEST%"
if errorlevel 1 ( echo [ERROR] Failed to clone ComfyUI & goto :fail )
exit /b 0

:git_clone
set "REPO=%~1"
set "NAME=%~2"
if not defined NAME for %%a in ("%REPO%") do set "NAME=%%~nxa"
set "DEST=%NODES_DIR%\%NAME%"
if exist "%DEST%" (
    if exist "%DEST%\.git" ( echo [4/8] Skip: %NAME% already exists & exit /b 0 )
    rmdir /s /q "%DEST%"
)
echo [4/8] Cloning %REPO% ...
git clone --depth 1 "https://github.com/%REPO%" "%DEST%" >nul 2>&1
if not errorlevel 1 exit /b 0
if exist "%DEST%" rmdir /s /q "%DEST%"
git clone --depth 1 "%GHFAST%/%REPO%" "%DEST%" >nul 2>&1
if not errorlevel 1 exit /b 0
if exist "%DEST%" rmdir /s /q "%DEST%"
git clone --depth 1 "%GHPROXY%/%REPO%" "%DEST%"
if errorlevel 1 echo [4/8] WARNING: failed to clone %REPO% (other nodes unaffected)
exit /b 0

:single_download
set "REPO=%~1"
set "FILE=%~2"
set "TARGET_DIR=%~3"
set "TARGET_FILE=%~4"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"
if exist "%TARGET_DIR%\%TARGET_FILE%" ( echo [8/8] Skip: %TARGET_FILE% already exists & exit /b 0 )
for /l %%i in (1,1,5) do (
    echo [8/8] Downloading %%i/5: %REPO% / %FILE%
    "%HF_BIN%" download "%REPO%" "%FILE%" --local-dir "%TARGET_DIR%"
    if not errorlevel 1 (
        REM hf CLI keeps the repo-relative path under --local-dir, so move the
        REM file to the flat target name expected by ComfyUI
        set "FILE_WIN=!FILE:/=\!"
        if not exist "%TARGET_DIR%\%TARGET_FILE%" (
            if exist "%TARGET_DIR%\!FILE_WIN!" (
                move /y "%TARGET_DIR%\!FILE_WIN!" "%TARGET_DIR%\%TARGET_FILE%" >nul
            )
        )
        if exist "%TARGET_DIR%\%TARGET_FILE%" exit /b 0
    )
    echo [8/8] Download failed, retrying in 30 seconds...
    %SystemRoot%\System32\timeout.exe /t 30 /nobreak >nul
)
echo [8/8] FAILED: %REPO% / %FILE%
exit /b 0

:single_download_folder
set "REPO=%~1"
set "TARGET_DIR=%~2"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"
if exist "%TARGET_DIR%\*" ( echo [8/8] Skip: %~nx2 non-empty & exit /b 0 )
for /l %%i in (1,1,5) do (
    echo [8/8] Downloading %%i/5 folder: %REPO%
    "%HF_BIN%" download "%REPO%" --local-dir "%TARGET_DIR%"
    if not errorlevel 1 exit /b 0
    echo [8/8] Download failed, retrying in 30 seconds...
    %SystemRoot%\System32\timeout.exe /t 30 /nobreak >nul
)
echo [8/8] FAILED: %REPO%
exit /b 0
