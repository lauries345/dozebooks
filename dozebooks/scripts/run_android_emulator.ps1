<# 
  run_android_emulator.ps1 (Flutter-first device selection)
  Runs a Flutter app on an Android emulator (or phone) from PowerShell.

  Examples:
    .\scripts\run_android_emulator.ps1
    .\scripts\run_android_emulator.ps1 -AvdName "Pixel_7a_API_35"
    .\scripts\run_android_emulator.ps1 -ProjectPath "C:\path\to\app" -PreferEmulator:$false

  Notes:
    - Requires at least one AVD (Android Studio > Device Manager).
    - Flutter must be on PATH (or set $env:FLUTTER_ROOT).
#>

[CmdletBinding()]
param(
  # Defaults to the folder containing this script
  [string]$ProjectPath = (Split-Path -Parent $PSCommandPath),

  # If not provided, script will pick the first available AVD
  [string]$AvdName,

  # Skip `flutter pub get`
  [switch]$SkipPubGet,

  # Prefer launching/using an emulator when possible
  [switch]$PreferEmulator = $true
)

# ------------------------- Helpers -----------------------------------------

function Fail($msg) { Write-Host "[ERROR] $msg"; exit 1 }
function Info($msg) { Write-Host "$msg" }
function Get-Exe([string]$path) { if (Test-Path $path) { (Resolve-Path $path).Path } else { $null } }

function Detect-AndroidSdk {
  $candidates = @(
    $env:ANDROID_SDK_ROOT,
    $env:ANDROID_HOME,
    (Join-Path $env:LOCALAPPDATA "Android\Sdk"),
    (Join-Path $env:ProgramFiles "Android\Sdk"),
    (Join-Path ${env:ProgramFiles(x86)} "Android\Sdk")
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

  foreach ($c in $candidates) {
    $emu = Get-Exe (Join-Path $c "emulator\emulator.exe")
    $adb = Get-Exe (Join-Path $c "platform-tools\adb.exe")
    if ($emu -and $adb) { return [PSCustomObject]@{ Sdk=$c; Emulator=$emu; Adb=$adb } }
  }
  return $null
}

function Ensure-Flutter {
  $flutterExe = "flutter"
  try { & $flutterExe --version 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { return $flutterExe } } catch {}
  if ($env:FLUTTER_ROOT) {
    $candidate = Join-Path $env:FLUTTER_ROOT "bin\flutter.bat"
    if (Test-Path $candidate) { return $candidate }
  }
  Fail "Flutter not found. Add Flutter to PATH or set FLUTTER_ROOT."
}

function List-Avds($emulatorExe) {
  $txt = (@(& $emulatorExe -list-avds) | Out-String)
  ($txt -split "`r?`n" | ForEach-Object { $_.Trim() }) | Where-Object { $_ -ne "" }
}

function Start-Emulator-And-Wait($emulatorExe, $adbExe, $avdName) {
  if (-not $avdName) { Fail "No AVD name provided and none detected as running." }
  Info "Starting emulator: $avdName"
  $args = @("-avd", $avdName, "-netdelay", "none", "-netspeed", "full")
  $proc = Start-Process -FilePath $emulatorExe -ArgumentList $args -PassThru
  if (-not $proc) { Fail "Failed to launch emulator." }

  # Wait for an emulator-* device to show as 'device'
  $deadline = (Get-Date).AddMinutes(5)
  $emulatorId = $null
  do {
    Start-Sleep -Seconds 2
    $txt = (@(& $adbExe devices) | Out-String)
    $lines = $txt -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch "^List of devices" }
    $emulators = $lines | Where-Object { $_ -match "^emulator-\d+\s+device$" }
    if ($emulators.Count -gt 0) {
      $first = $emulators | Select-Object -First 1
      $emulatorId = ($first -split "\s+")[0]
    }
  } while (-not $emulatorId -and (Get-Date) -lt $deadline)

  if (-not $emulatorId) { Fail "Emulator did not appear in 'adb devices' within 5 minutes." }

  # Wait for Android boot to finish
  Info "Waiting for Android to finish booting..."
  & $adbExe -s $emulatorId wait-for-device | Out-Null

  $bootDeadline = (Get-Date).AddMinutes(5)
  $ready = $false
  do {
    Start-Sleep -Seconds 2
    $boot  = (@(& $adbExe -s $emulatorId shell getprop sys.boot_completed) | Out-String).Trim()
    $boot2 = (@(& $adbExe -s $emulatorId shell getprop dev.bootcomplete)   | Out-String).Trim()
    $ready = ($boot -eq "1" -or $boot2 -eq "1")
  } while (-not $ready -and (Get-Date) -lt $bootDeadline)

  if (-not $ready) { Fail "Android did not finish booting in time." }

  # Wake/unlock
  & $adbExe -s $emulatorId shell input keyevent 82 2>$null | Out-Null
  return $emulatorId
}

function Get-FlutterAndroidDevices($flutterExe) {
  # Use Flutter's JSON to avoid mis-parsing device ids
  $json = & $flutterExe devices --machine 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $json) { return @() }
  $arr = $null
  try { $arr = $json | ConvertFrom-Json } catch { return @() }
  if (-not $arr) { return @() }
  # Keep only Android devices (emulators or physical)
  return $arr | Where-Object { $_.platform -like "android*" -or $_.targetPlatform -like "android*" }
}

function Pick-FlutterAndroidDevice($flutterExe, [switch]$preferEmu) {
  $devs = Get-FlutterAndroidDevices $flutterExe
  if (-not $devs -or $devs.Count -eq 0) { return $null }
  $emu = $devs | Where-Object { ($_.name -match "emulator|AVD|Android\s+SDK") -or ($_.id -match "^emulator-") }
  $pick = if ($preferEmu -and $emu) { $emu | Select-Object -First 1 } else { $devs | Select-Object -First 1 }
  return $pick.id
}

# --------------------------- Main ------------------------------------------

Push-Location $ProjectPath
try {
  Info "=== Android SDK autodetect ==="
  $sdk = Detect-AndroidSdk
  if (-not $sdk) { Fail "Could not locate Android SDK with both emulator and adb. Set ANDROID_SDK_ROOT or ANDROID_HOME." }
  Info "SDK: $($sdk.Sdk)"
  Info "EMULATOR: $($sdk.Emulator)"
  Info "ADB: $($sdk.Adb)"

  $flutter = Ensure-Flutter
  Info "FLUTTER: $flutter"

  # 1) Try to pick an Android device that Flutter recognizes
  $deviceId = Pick-FlutterAndroidDevice $flutter $PreferEmulator

  # 2) If none, start an emulator and re-check
  if (-not $deviceId) {
    $avds = List-Avds $sdk.Emulator
    if (-not $avds -or $avds.Count -eq 0) { Fail "No AVDs found. Create one in Android Studio (Device Manager) before running this script." }
    if (-not $AvdName) { $AvdName = $avds | Select-Object -First 1 }
    Info "Using AVD: $AvdName"
    $emuSerial = Start-Emulator-And-Wait $sdk.Emulator $sdk.Adb $AvdName

    # Give Flutter a moment to enumerate the new device, then re-query
    Start-Sleep -Seconds 2
    $deviceId = Pick-FlutterAndroidDevice $flutter $PreferEmulator
  } else {
    Info "Using Android device recognized by Flutter: $deviceId"
  }

  if (-not $deviceId) {
    Fail "No Android devices recognized by Flutter. If a phone is connected, enable USB debugging. Otherwise create/start an AVD."
  }

  if (-not $SkipPubGet) {
    Info "Running: flutter pub get"
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { Fail "flutter pub get failed." }
  }

  Info "Running: flutter run -d $deviceId"
  & $flutter run -d $deviceId
  if ($LASTEXITCODE -ne 0) { Fail "flutter run failed." }
}
finally {
  Pop-Location
}
