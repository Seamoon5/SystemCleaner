@echo off
setlocal
title SystemCleaner
color 0A

set "FOLDER=%~dp0"
set "SCRIPT=%FOLDER%clean-windows.ps1"

:menu
cls
echo ============================================
echo            SystemCleaner - Menu
echo ============================================
echo.
echo   1. Scan only (see junk, delete nothing)
echo   2. Clean - pick what to clean
echo   3. Clean everything safe
echo   4. Preview what a full clean would remove
echo   5. Run every day at 09:00 automatically
echo      (missed at 09:00? it runs when you start the PC)
echo   6. Stop the automatic daily run
echo   7. View the cleaner log
echo   8. Clean at every startup (only if today's not
echo      cleaned yet - smart, no wasted work)
echo   9. Stop the startup clean
echo   0. Exit
echo.
echo ============================================
set "choice="
set /p choice="Type a number and press Enter: "

if "%choice%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Scan
    goto done
)
if "%choice%"=="2" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Clean
    goto done
)
if "%choice%"=="3" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Clean -All
    goto done
)
if "%choice%"=="4" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Clean -All -DryRun
    goto done
)
if "%choice%"=="5" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Schedule
    goto done
)
if "%choice%"=="6" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RemoveSchedule
    goto done
)
if "%choice%"=="7" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$L=\"%FOLDER%SystemCleaner-windows.log\"; if (Test-Path $L) { Get-Content $L -Tail 50 } else { Write-Host 'No log yet - run a clean first.' -ForegroundColor Yellow }"
    goto done
)
if "%choice%"=="8" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Startup
    goto done
)
if "%choice%"=="9" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -RemoveStartup
    goto done
)
if "%choice%"=="0" (
    exit /b
)
echo Invalid choice, try again.
timeout /t 2 >nul
goto menu

:done
echo.
echo Press any key to go back to the menu...
pause >nul
goto menu