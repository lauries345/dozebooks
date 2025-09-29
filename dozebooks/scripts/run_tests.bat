@echo off
setlocal enabledelayedexpansion

REM --- Run from repo root (script lives in scripts/) ---
cd /d "%~dp0.."

echo Running Flutter tests...
flutter test --reporter expanded %*

set EXITCODE=%ERRORLEVEL%
if %EXITCODE% neq 0 (
  echo.
  echo Tests FAILED with exit code %EXITCODE%.
  exit /b %EXITCODE%
)

echo.
echo All tests PASSED.
exit /b 0
