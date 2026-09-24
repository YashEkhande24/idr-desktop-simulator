@echo off
setlocal enabledelayedexpansion
title IDR Super-Architecture Navigator - SIH 2026

echo =====================================================================
echo   AI-ENHANCED INTELLIGENT DEAD RECKONING (IDR) NAVIGATION SYSTEM
echo   Smart India Hackathon (SIH) 2026 - Production Mobile & Server Platform
echo =====================================================================
echo.
echo Select an option:
echo   --- Pure C++ Mobile Tier (Android NDK NativeActivity) ---
echo   [1] Build Pure C++ Release APK (cpp_mobile_app\android\build\outputs\apk)
echo   [2] Install & Launch Pure C++ App on Connected Phone (adb install)
echo   [3] Run C++ Core Microsecond Benchmark (cpp_mobile_app\python\benchmark_cpp.py)
echo.
echo   --- Flutter Mobile Tier (Dart / Flutter Reference App) ---
echo   [4] Run IDR in Google Chrome (Desktop / Web Demo)
echo   [5] Run IDR on Connected Android Phone / Emulator
echo   [6] Build Standalone Production Release Flutter APK
echo   [7] Run Flutter Mobile Test Suite (flutter test)
echo.
echo   --- Workstation Server & Benchmark Tier (Python) ---
echo   [8] Start IDR Workstation Computation Server (ws://0.0.0.0:8765)
echo   [9] Run Headless IO-VNBD Benchmark (python -m idr_simulation.benchmark)
echo   [10] Run Python Algorithmic & Math Test Suite (pytest tests/test_idr.py)
echo   [11] Check Environment (flutter doctor, ndk, python packages)
echo   [0] Exit
echo.

set /p choice="Enter option (0-11) [Default 1]: "
if "%choice%"=="" set choice=1

if "%choice%"=="1" (
    echo.
    echo Building Pure C++ Standalone Release Android APK with NDK 27...
    cd cpp_mobile_app\android
    call gradlew.bat assembleRelease
    cd ..\..
    echo.
    echo Build complete!
    goto done
)

if "%choice%"=="2" (
    echo.
    echo Installing Pure C++ IDR APK onto connected device...
    adb install -r cpp_mobile_app\android\build\outputs\apk\release\android-release-unsigned.apk
    echo Launching Pure C++ NativeActivity...
    adb shell am start -n com.sih2026.idr.purecpp/android.app.NativeActivity
    goto done
)

if "%choice%"=="3" (
    echo.
    echo Running C++ vs Python Microsecond Latency Benchmark...
    python cpp_mobile_app\python\benchmark_cpp.py
    goto done
)

if "%choice%"=="4" (
    echo.
    echo Starting IDR in Google Chrome...
    flutter run -d chrome
    goto done
)

if "%choice%"=="5" (
    echo.
    echo Launching Flutter App on Android device...
    flutter run -d android
    goto done
)

if "%choice%"=="6" (
    echo.
    echo Building Release Android Flutter APK...
    flutter build apk --release
    goto done
)

if "%choice%"=="7" (
    echo.
    echo Running Flutter Mobile Unit & Algorithmic Test Suite...
    flutter test
    goto done
)

if "%choice%"=="8" (
    echo.
    echo Starting IDR Workstation Computation Server...
    python -m idr_simulation.server
    goto done
)

if "%choice%"=="9" (
    echo.
    echo Running Headless IO-VNBD Benchmark...
    python -m idr_simulation.benchmark
    goto done
)

if "%choice%"=="10" (
    echo.
    echo Running Python Mathematical & Algorithmic Test Suite...
    python -m pytest tests/test_idr.py -v
    goto done
)

if "%choice%"=="11" (
    echo.
    echo Checking Flutter environment...
    flutter doctor
    echo.
    echo Checking Python packages...
    pip list
    goto done
)

:done
pause
