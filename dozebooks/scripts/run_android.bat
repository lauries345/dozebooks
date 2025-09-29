@echo off
setlocal enabledelayedexpansion

REM --- Change to repo root (this script lives in scripts\) ---
pushd "%~dp0\.." || (echo [ERROR] Couldn't cd to repo root & exit /b 1)

echo Running Flutter app on Android phone...

REM --- Find adb (PATH, ANDROID_HOME/SDK_ROOT, Local AppData) ---
set "ADB=adb"
where adb >nul 2>&1
if errorlevel 1 (
  if exist "%ANDROID_HOME%\platform-tools\adb.exe" set "ADB=%ANDROID_HOME%\platform-tools\adb.exe"
  if exist "%ANDROID_SDK_ROOT%\platform-tools\adb.exe" set "ADB=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
  if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
)

"%ADB%" version >nul 2>&1 || (
  echo [ERROR] adb not found. Add platform-tools to PATH or set ANDROID_HOME/ANDROID_SDK_ROOT.
  popd
  exit /b 1
)

REM --- Ensure ADB server is running and device is ready ---
echo Starting ADB server...
"%ADB%" start-server >nul 2>&1
"%ADB%" wait-for-device >nul 2>&1

REM --- Pick first fully connected device (state = device) ---
set "SERIAL="
for /f "skip=1 tokens=1,2" %%A in ('"%ADB%" devices') do (
  if "%%B"=="device" (
     set "SERIAL=%%A"
     goto :found_device
  )
)

echo [ERROR] No Android device found (or not authorized).
echo Tips:
echo   - Enable USB debugging and accept the fingerprint prompt on the phone
echo   - Try: "%ADB%" kill-server ^&^& "%ADB%" start-server
popd
exit /b 2

:found_device
echo Using device !SERIAL!

REM --- Get Flutter deps (IMPORTANT: use CALL because flutter is a .bat) ---
call flutter pub get || (popd & exit /b 3)

REM --- Run on the selected device (use CALL here too) ---
call flutter run -d !SERIAL! --release
set "RC=%ERRORLEVEL%"

popd
exit /b %RC%
