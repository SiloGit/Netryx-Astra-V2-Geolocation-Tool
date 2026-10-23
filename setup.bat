@echo off
:: ===================================================================
::  Netryx Astra V2 - Windows setup. Double-click to run.
::  Safe to run again: finished steps are skipped.
:: ===================================================================
echo.
echo ===================================================
echo   Netryx Astra V2 - Windows Setup
echo ===================================================
echo.

set "NETRYX_DIR=%~dp0"
cd /d "%NETRYX_DIR%"
set "LOG=%NETRYX_DIR%installer.log"
type nul > "%LOG%"

:: --- Python 3.10-3.12 with Tk (the app's window needs Tk) ---------
:: Prefer the "py" launcher, which finds any installed version, so a
:: newer default Python (3.13+) on PATH doesn't block setup.
set "PYEXE="
for %%V in (3.12 3.11 3.10) do (
    if not defined PYEXE (
        py -%%V -c "import tkinter" >nul 2>&1 && set "PYEXE=py -%%V"
    )
)
if not defined PYEXE (
    python -c "import sys, tkinter; sys.exit(0 if (3,10) <= sys.version_info[:2] <= (3,12) else 1)" >nul 2>&1 && set "PYEXE=python"
)
if not defined PYEXE (
    echo [ERROR] Netryx needs Python 3.10, 3.11 or 3.12.
    echo         Install Python 3.12 from https://www.python.org/downloads/windows/
    echo         and keep "tcl/tk and IDLE" ticked during install.
    echo         Then double-click setup.bat again.
    pause
    exit /b 1
)
echo [OK] Using Python via: %PYEXE%

git --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Git not found. Download it from https://git-scm.com and run setup again.
    pause
    exit /b 1
)
echo [OK] Git found

set "HAS_NVIDIA="
nvidia-smi >nul 2>&1
if not errorlevel 1 (
    set "HAS_NVIDIA=1"
    echo [OK] NVIDIA GPU detected
    where nvcc >nul 2>&1
    if errorlevel 1 echo [INFO] CUDA Toolkit ^(nvcc^) not found: MASt3R will use a slower fallback. Optional.
)

:: --- Virtual environment (rebuilt if made with an unsuitable Python) ---
if exist "venv\Scripts\python.exe" (
    venv\Scripts\python.exe -c "import sys, tkinter; sys.exit(0 if (3,10) <= sys.version_info[:2] <= (3,12) else 1)" >nul 2>&1
    if errorlevel 1 (
        echo [SETUP] Existing venv uses an unsuitable Python; recreating it...
        rmdir /s /q venv
    )
)
if not exist "venv\Scripts\python.exe" (
    echo [SETUP] Creating virtual environment...
    %PYEXE% -m venv venv
    if errorlevel 1 (
        echo [ERROR] Could not create the virtual environment.
        pause
        exit /b 1
    )
)
set "VPY=%NETRYX_DIR%venv\Scripts\python.exe"
echo [OK] Virtual environment ready

:: --- PyTorch ---------------------------------------------------------
echo [SETUP] Installing PyTorch ^(this can take a few minutes^)...
"%VPY%" -m pip install --upgrade pip -q
if defined HAS_NVIDIA (
    "%VPY%" -m pip install -q torch==2.6.0 torchvision==0.21.0 --index-url https://download.pytorch.org/whl/cu124
) else (
    "%VPY%" -m pip install -q torch==2.6.0 torchvision==0.21.0
)
if errorlevel 1 (
    echo [ERROR] PyTorch failed to install. See the messages above.
    pause
    exit /b 1
)

echo [SETUP] Installing Python dependencies...
"%VPY%" -m pip install -q -r requirements.txt
if errorlevel 1 (
    echo [ERROR] Dependencies failed to install. See the messages above.
    pause
    exit /b 1
)
echo [OK] Dependencies installed

:: --- MASt3R (cloned next to this folder) ---------------------------
set "MAST3R_DIR=%NETRYX_DIR%..\mast3r"
if exist "%MAST3R_DIR%\mast3r\model.py" (
    echo [OK] MASt3R already present
) else (
    echo [SETUP] Downloading MASt3R...
    git clone --recursive https://github.com/naver/mast3r.git "%MAST3R_DIR%"
)
"%VPY%" -m pip install -q -r "%MAST3R_DIR%\requirements.txt"
"%VPY%" -m pip install -q -r "%MAST3R_DIR%\dust3r\requirements.txt"
echo [OK] MASt3R ready

:: --- Model weights (optional here: the app downloads them on first use) ---
echo [SETUP] Downloading MegaLoc model weights ^(first time only^)...
"%VPY%" -c "import torch; torch.hub.load('gmberton/MegaLoc', 'get_trained_model', trust_repo=True)" >>"%LOG%" 2>&1
if errorlevel 1 (echo [WARN] MegaLoc download failed; the app will retry on first run) else (echo [OK] MegaLoc ready)

:: The folder is passed through the environment: a path ending in "\"
:: can't be written inside a Python string literal.
echo [SETUP] Downloading MASt3R model weights ^(~1.2 GB, first time only^)...
"%VPY%" -c "import sys,os; p=os.path.abspath(os.environ['MAST3R_DIR']); sys.path[:0]=[p, os.path.join(p,'dust3r'), os.path.join(p,'dust3r','croco')]; from mast3r.model import AsymmetricMASt3R; AsymmetricMASt3R.from_pretrained('naver/MASt3R_ViTLarge_BaseDecoder_512_catmlpdpt_metric')" >>"%LOG%" 2>&1
if errorlevel 1 (echo [WARN] MASt3R weights download failed; the app will retry on first run) else (echo [OK] MASt3R weights ready)

set "HUB_DIR=%USERPROFILE%\.cache\torch\hub\gmberton_VPR-methods-evaluation_master"
if exist "%HUB_DIR%" (
    echo [OK] MixVPR code already present
) else (
    if not exist "%USERPROFILE%\.cache\torch\hub" mkdir "%USERPROFILE%\.cache\torch\hub"
    git clone -q https://github.com/gmberton/VPR-methods-evaluation.git "%HUB_DIR%" >>"%LOG%" 2>&1
    if errorlevel 1 (echo [WARN] MixVPR download failed ^(only needed for the MixVPR encoder^)) else (echo [OK] MixVPR installed)
)

if not exist "netryx_data\megaloc_parts" mkdir "netryx_data\megaloc_parts"
if not exist "netryx_data\indexes" mkdir "netryx_data\indexes"

:: Triton (torch.compile) is not supported on Windows
setx TORCH_COMPILE_DISABLE "1" >nul
set TORCH_COMPILE_DISABLE=1

echo.
echo ===================================================
echo   Setup complete!
echo.
echo   To start Netryx, double-click run.bat
echo ===================================================
pause
