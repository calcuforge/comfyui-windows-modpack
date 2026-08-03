@echo off
setlocal
set "ROOT=%~dp0"

if not exist "%ROOT%python_comfyui\Scripts\python.exe" goto :init
if not exist "%ROOT%ComfyUI\main.py" goto :init
if not exist "%ROOT%ffmpeg\bin\ffmpeg.exe" goto :init
goto :start

:init
echo Init environment not found. First run will execute init.bat automatically
echo Init includes environment setup and model downloads, may take hours
echo.
call "%ROOT%init.bat"
if errorlevel 1 ( echo Init failed, check errors above & pause & exit /b 1 )

:start
REM Isolated interpreters for Qwen3-TTS / Qwen3-ASR (used by the custom nodes)
set "QWEN_VENV_PYTHON=%ROOT%python_qwentts\Scripts\python.exe"
set "QWEN_ASR_VENV_PYTHON=%ROOT%python_qwenasr\Scripts\python.exe"

REM HuggingFace mirror (faster in China)
set "HF_ENDPOINT=https://hf-mirror.com"
set "HF_HUB_ENABLE_HF_XET=0"
set "HF_HUB_DISABLE_XET=1"

REM WanVideoWrapper VRAM cache cap (same as Docker image)
set "CACHE_RAM=46.5"

REM FFmpeg shipped in the package (installed by init.bat into %ROOT%ffmpeg\bin)
if exist "%ROOT%ffmpeg\bin" set "PATH=%ROOT%ffmpeg\bin;%PATH%"

cd /d "%ROOT%ComfyUI"
echo Starting ComfyUI... browser will open http://127.0.0.1:8188 once the server is ready
start "" /b powershell -NoProfile -Command "for($i=0;$i -lt 60;$i++){ try{ $r=Invoke-WebRequest -Uri 'http://127.0.0.1:8188/queue' -TimeoutSec 3 -UseBasicParsing; if($r.StatusCode -eq 200 -and $r.Content -match 'queue_running'){ Start-Process 'http://127.0.0.1:8188'; break } }catch{}; Start-Sleep -Seconds 5 }"
"%ROOT%python_comfyui\Scripts\python.exe" main.py --listen 127.0.0.1 --port 8188
echo.
echo ComfyUI exited
pause
