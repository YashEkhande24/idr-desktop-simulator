@echo off
REM ==============================================================================
REM IDR-NeuroSpeed-TCN : One-Click Verification Launcher (Windows)
REM Smart India Hackathon (SIH 2026) Official Evaluation Script
REM ==============================================================================
echo.
echo ======================================================================
echo    Starting IDR-NeuroSpeed-TCN Model Verification Suite (SIH 2026)
echo ======================================================================
echo.

python test.py --plot --export results.json

echo.
echo Test run complete. Benchmark plots saved to eval_plots/ and results.json.
pause
