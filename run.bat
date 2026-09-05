@echo off
setlocal enabledelayedexpansion
title AI-ML IDR Simulator - Smart India Hackathon

:: Always execute in repository root
cd /d "%~dp0"

:: -----------------------------------------------------------------------------
:: Detect Python Interpreter
:: -----------------------------------------------------------------------------
set "PYTHON_CMD="

:: 1. Check C:\Python312\python.exe
if exist "C:\Python312\python.exe" (
    "C:\Python312\python.exe" -c "import PySide6, pyqtgraph" >nul 2>&1
    if !errorlevel! equ 0 (
        set "PYTHON_CMD=C:\Python312\python.exe"
        goto :python_detected
    )
)

:: 2. Check py launcher for Python 3.12
py -3.12 -c "import PySide6, pyqtgraph" >nul 2>&1
if !errorlevel! equ 0 (
    set "PYTHON_CMD=py -3.12"
    goto :python_detected
)

:: 3. Check active virtual environment
if defined VIRTUAL_ENV (
    if exist "%VIRTUAL_ENV%\Scripts\python.exe" (
        "%VIRTUAL_ENV%\Scripts\python.exe" -c "import PySide6, pyqtgraph" >nul 2>&1
        if !errorlevel! equ 0 (
            set "PYTHON_CMD=%VIRTUAL_ENV%\Scripts\python.exe"
            goto :python_detected
        )
    )
)

:: 4. Check workspace .venv
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" -c "import PySide6, pyqtgraph" >nul 2>&1
    if !errorlevel! equ 0 (
        set "PYTHON_CMD=.venv\Scripts\python.exe"
        goto :python_detected
    )
)

:: 5. Check default system python
python -c "import PySide6, pyqtgraph" >nul 2>&1
if !errorlevel! equ 0 (
    set "PYTHON_CMD=python"
    goto :python_detected
)

:: 6. Fallback if dependencies not yet installed
if not defined PYTHON_CMD if exist "C:\Python312\python.exe" set "PYTHON_CMD=C:\Python312\python.exe"
if not defined PYTHON_CMD if exist ".venv\Scripts\python.exe" set "PYTHON_CMD=.venv\Scripts\python.exe"
if not defined PYTHON_CMD set "PYTHON_CMD=python"

:python_detected

:: -----------------------------------------------------------------------------
:: Command Line Argument Dispatch
:: -----------------------------------------------------------------------------
set "ARG=%~1"

if "%ARG%"=="" goto :interactive_mode

if /i "%ARG%"=="gui" goto :cli_gui
if /i "%ARG%"=="app" goto :cli_gui
if /i "%ARG%"=="start" goto :cli_gui
if /i "%ARG%"=="benchmark" goto :cli_benchmark
if /i "%ARG%"=="bench" goto :cli_benchmark
if /i "%ARG%"=="test" goto :cli_tests
if /i "%ARG%"=="tests" goto :cli_tests
if /i "%ARG%"=="train" goto :cli_train
if /i "%ARG%"=="install" goto :cli_install
if /i "%ARG%"=="help" goto :show_help
if /i "%ARG%"=="-h" goto :show_help
if /i "%ARG%"=="--help" goto :show_help
if /i "%ARG%"=="/?" goto :show_help

echo [!] Unknown argument: %ARG%
echo Run "run.bat help" for available commands.
exit /b 1

:: -----------------------------------------------------------------------------
:: CLI Dispatch Targets (Non-interactive)
:: -----------------------------------------------------------------------------
set "REST_ARGS="
for /f "tokens=1,* delims= " %%a in ("%*") do set "REST_ARGS=%%b"

:cli_gui
%PYTHON_CMD% -m idr_simulation.app %REST_ARGS%
exit /b %errorlevel%

:cli_benchmark
%PYTHON_CMD% -m idr_simulation.benchmark %REST_ARGS%
exit /b %errorlevel%

:cli_tests
%PYTHON_CMD% -m pytest tests/test_idr.py %REST_ARGS%
exit /b %errorlevel%

:cli_train
%PYTHON_CMD% -m idr_simulation.models.tcn_speed_engine --train %REST_ARGS%
exit /b %errorlevel%

:cli_install
%PYTHON_CMD% -m pip install -r requirements.txt %REST_ARGS%
exit /b %errorlevel%

:: -----------------------------------------------------------------------------
:: Interactive Menu Mode (Double-clicked or executed with no arguments)
:: -----------------------------------------------------------------------------
:interactive_mode
:menu
cls
echo ================================================================================
echo            AI-ML Intelligent Dead Reckoning (IDR) Desktop Simulator             
echo             Smart India Hackathon 2026  ^|  GNSS-Denied Navigation             
echo ================================================================================
echo  Python Interpreter: %PYTHON_CMD%
echo ================================================================================
echo.
echo   [1] Launch Desktop Simulator GUI (PySide6 + 2D/3D Cockpit)   [DEFAULT]
echo   [2] Run Headless Monte Carlo Benchmark
echo   [3] Run Automated Test Suite (pytest)
echo   [4] Retrain TCN Speed Engine and Export Weights (.pt, .onnx, .npz)
echo   [5] Install / Verify Dependencies (pip install -r requirements.txt)
echo   [6] Exit
echo.
echo ================================================================================
set "CHOICE=1"
set /p "CHOICE=Select an option [1-6, default=1]: "

if "%CHOICE%"=="1" goto :menu_gui
if "%CHOICE%"=="2" goto :menu_benchmark
if "%CHOICE%"=="3" goto :menu_tests
if "%CHOICE%"=="4" goto :menu_train
if "%CHOICE%"=="5" goto :menu_install
if "%CHOICE%"=="6" goto :exit_script

echo.
echo [!] Invalid selection "%CHOICE%". Please choose an option between 1 and 6.
timeout /t 2 >nul
goto :menu

:: -----------------------------------------------------------------------------
:: Interactive Menu Handlers
:: -----------------------------------------------------------------------------
:menu_gui
cls
echo ================================================================================
echo [*] Launching AI-ML IDR Simulator Desktop Cockpit...
echo ================================================================================
echo Command: %PYTHON_CMD% -m idr_simulation.app
echo.
%PYTHON_CMD% -m idr_simulation.app
if %errorlevel% neq 0 (
    echo.
    echo [!] Simulator exited with code %errorlevel%.
    pause
)
goto :menu

:menu_benchmark
cls
echo ================================================================================
echo [*] Running Headless Monte Carlo Benchmark...
echo ================================================================================
echo Command: %PYTHON_CMD% -m idr_simulation.benchmark --backend torch
echo.
%PYTHON_CMD% -m idr_simulation.benchmark --backend torch
if %errorlevel% neq 0 (
    echo.
    echo [!] Benchmark exited with code %errorlevel%.
)
echo.
pause
goto :menu

:menu_tests
cls
echo ================================================================================
echo [*] Running Automated Test Suite (pytest)...
echo ================================================================================
echo Command: %PYTHON_CMD% -m pytest tests/test_idr.py -v
echo.
%PYTHON_CMD% -m pytest tests/test_idr.py -v
if %errorlevel% neq 0 (
    echo.
    echo [!] Tests failed with code %errorlevel%.
)
echo.
pause
goto :menu

:menu_train
cls
echo ================================================================================
echo [*] Retraining 1D Causal TCN Speed Engine...
echo ================================================================================
echo Command: %PYTHON_CMD% -m idr_simulation.models.tcn_speed_engine --train --epochs 10 --runs 4
echo.
%PYTHON_CMD% -m idr_simulation.models.tcn_speed_engine --train --epochs 10 --runs 4
if %errorlevel% neq 0 (
    echo.
    echo [!] Training exited with code %errorlevel%.
)
echo.
pause
goto :menu

:menu_install
cls
echo ================================================================================
echo [*] Installing Dependencies from requirements.txt...
echo ================================================================================
echo Command: %PYTHON_CMD% -m pip install -r requirements.txt
echo.
%PYTHON_CMD% -m pip install -r requirements.txt
echo.
pause
goto :menu

:show_help
echo ================================================================================
echo   AI-ML Intelligent Dead Reckoning Simulator - CLI Helper
echo ================================================================================
echo.
echo Usage: run.bat [command] [options...]
echo.
echo Commands:
echo   gui              Launch the interactive PySide6 Desktop GUI (default)
echo   bench [args...]  Run headless Monte Carlo benchmark (e.g. run.bat bench --ablate)
echo   test [args...]   Run automated unit and integration tests (pytest)
echo   train [args...]  Retrain the 1D Causal TCN and export model weights
echo   install          Install required Python dependencies via pip
echo   help             Display this help message
echo.
echo If run with no arguments (or double-clicked), an interactive menu is displayed.
echo ================================================================================
exit /b 0

:exit_script
exit /b 0
