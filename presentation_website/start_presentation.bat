@echo off
title IDR-Navigator Presentation Website Server
cd /d "%~dp0"
echo =====================================================================
echo    IDR-NAVIGATOR: PRESENTATION WEBSITE & SHOWCASE SERVER
echo    Smart India Hackathon 2026 Submission Hub
echo =====================================================================
echo.
echo Starting local web server on port 8088...
echo Website URL: http://localhost:8088/
echo.
start http://localhost:8088/
python -m http.server 8088
pause
