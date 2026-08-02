@echo off
chcp 65001 >nul
setlocal
set "ROOT=%~dp0"

if not exist "%ROOT%python_comfyui\Scripts\python.exe" goto :init
if not exist "%ROOT%ComfyUI\main.py" goto :init
goto :start

:init
echo 未检测到初始化环境, 首次运行将自动执行 init.bat
echo 初始化包含环境搭建与模型下载, 可能耗时数小时, 请耐心等待
echo.
call "%ROOT%init.bat"
if errorlevel 1 ( echo 初始化失败, 请检查上方错误信息 & pause & exit /b 1 )

:start
REM Qwen3-TTS / Qwen3-ASR 独立解释器路径 (节点通过环境变量调用)
set "QWEN_VENV_PYTHON=%ROOT%python_qwentts\Scripts\python.exe"
set "QWEN_ASR_VENV_PYTHON=%ROOT%python_qwenasr\Scripts\python.exe"

REM HuggingFace 镜像 (国内加速)
set "HF_ENDPOINT=https://hf-mirror.com"
set "HF_HUB_ENABLE_HF_XET=0"
set "HF_HUB_DISABLE_XET=1"

REM WanVideoWrapper 显存缓存限制 (与Docker镜像一致)
set "CACHE_RAM=46.5"

cd /d "%ROOT%ComfyUI"
echo 启动 ComfyUI... 8秒后自动打开浏览器 http://127.0.0.1:8188
start "" /b cmd /c "%SystemRoot%\System32\timeout.exe /t 8 /nobreak >nul & start http://127.0.0.1:8188"
"%ROOT%python_comfyui\Scripts\python.exe" main.py --listen 127.0.0.1 --port 8188
echo.
echo ComfyUI 已退出
pause
