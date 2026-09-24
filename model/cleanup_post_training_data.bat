@echo off
echo ======================================================================
echo Cleaning up Post-Training Datasets...
echo Target: model\datasets\post_training
echo ======================================================================

if exist "%~dp0datasets\post_training" (
    rmdir /s /q "%~dp0datasets\post_training"
    echo [OK] Successfully removed model\datasets\post_training directory.
) else (
    echo [INFO] Directory model\datasets\post_training does not exist. Nothing to clean.
)

echo Done.
pause
