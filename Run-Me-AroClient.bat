@echo off
setlocal ENABLEDELAYEDEXPANSION

:: Self-elevate to Administrator if not already
whoami /groups | findstr /C:"S-1-16-12288" >nul
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: Launch PowerShell orchestrator
set SCRIPT_DIR=%~dp0
set PS1=%SCRIPT_DIR%scripts\Setup-AroClient.ps1

if not exist "%PS1%" (
  echo [ERROR] PowerShell script not found: %PS1%
  echo Press any key to close...
  pause >nul
  exit /b 1
)

:: Interactive preset menu (optional)
echo.
echo Select preset (press Enter for AUTO):
echo   1 ^) lite     - minimal resource usage
echo   2 ^) standard - balanced
echo   3 ^) perf     - maximum
echo   4 ^) auto     - auto-detect (default)
set /p _CHOICE=Your choice [1-4, default=4]: 
if "%_CHOICE%"=="1" set ARO_PRESET=lite
if "%_CHOICE%"=="2" set ARO_PRESET=standard
if "%_CHOICE%"=="3" set ARO_PRESET=perf
if "%_CHOICE%"=="4" set ARO_PRESET=auto
if "%_CHOICE%"=="" set ARO_PRESET=auto
if not defined ARO_PRESET set ARO_PRESET=auto
echo [INFO] Using preset: %ARO_PRESET%

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set ERR=%ERRORLEVEL%
echo.
echo [INFO] Setup script exited with code %ERR%
echo Press any key to close this window...
pause >nul

endlocal
