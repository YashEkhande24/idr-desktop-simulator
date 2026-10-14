@echo off
setlocal enabledelayedexpansion
title Deploy IDR-Navigator to Google Cloud / Firebase Hosting
cd /d "%~dp0"

echo =====================================================================
echo    IDR-NAVIGATOR: GOOGLE CLOUD / FIREBASE HOSTING DEPLOYMENT
echo    Target Google Account: tempersoft2018@gmail.com
echo =====================================================================
echo.

:: 1. Verify Node and Firebase CLI
where firebase >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Firebase CLI not found in PATH.
    echo Please ensure Node.js is installed, or run: npm install -g firebase-tools
    echo.
    pause
    exit /b 1
)

echo [1/4] Checking Google Account Authentication...
echo Switching active account to tempersoft2018@gmail.com ...
call firebase login:use tempersoft2018@gmail.com >nul 2>&1

if %errorlevel% neq 0 (
    echo.
    echo [ACTION REQUIRED] You need to authorize tempersoft2018@gmail.com.
    echo A browser window will now open. Please sign in with:
    echo    tempersoft2018@gmail.com
    echo.
    pause
    call firebase login:add
)

echo.
echo [2/4] Authenticated successfully!
echo.

:: 2. Project Selection
set /p PROJECT_ID="Enter your Firebase/Google Cloud Project ID (e.g. idr-navigator-2026): "
if "%PROJECT_ID%"=="" (
    set PROJECT_ID=idr-navigator-2026
)

echo.
echo [3/4] Binding to project: !PROJECT_ID! ...
call firebase use !PROJECT_ID!

echo.
echo [4/4] Deploying website files to Google Cloud CDN...
call firebase deploy --only hosting
if %errorlevel% neq 0 (
    echo.
    echo =====================================================================
    echo    [DEPLOYMENT FAILED]
    echo    Firebase returned an error during deployment.
    echo =====================================================================
    echo.
    pause
    exit /b %errorlevel%
)

echo.
echo =====================================================================
echo    DEPLOYMENT SUCCESSFUL!
echo    Your presentation website is now live on Google Cloud:
echo    https://!PROJECT_ID!.web.app/
echo    https://!PROJECT_ID!.firebaseapp.com/
echo =====================================================================
echo.

start https://!PROJECT_ID!.web.app/
pause
