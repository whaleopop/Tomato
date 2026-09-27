@echo off
rem Thin wrapper: sets cache env vars, activates the venv and forwards all args to generate.py.
rem Usage: tools\ai_models\generate.bat --prompt "cute broccoli warrior" [--name broccoli] [...]
setlocal
if "%ROYALTIM_AI_ROOT%"=="" set "ROYALTIM_AI_ROOT=D:\royaltim-ai"
set "HF_HOME=%ROYALTIM_AI_ROOT%\hf_cache"
set "PIP_CACHE_DIR=%ROYALTIM_AI_ROOT%\pip_cache"
set "TORCH_HOME=%ROYALTIM_AI_ROOT%\torch_cache"
set "U2NET_HOME=%ROYALTIM_AI_ROOT%\u2net"
set "HF_HUB_DISABLE_SYMLINKS_WARNING=1"
set "PYTHONIOENCODING=utf-8"
if not exist "%ROYALTIM_AI_ROOT%\venv\Scripts\python.exe" (
    echo ERROR: venv not found in %ROYALTIM_AI_ROOT%\venv - run: powershell -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
    exit /b 2
)
call "%ROYALTIM_AI_ROOT%\venv\Scripts\activate.bat"
python "%~dp0generate.py" %*
exit /b %ERRORLEVEL%
