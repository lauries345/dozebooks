# Running on Android

## Prerequisites
- **Developer options** and **USB debugging** enabled on the phone.
- **Android platform-tools** installed (ADB available on PATH).
- Trust dialog accepted when connecting the device via USB.

## Check connected devices
flutter devices
Example output:
Found 4 connected devices:
  SM S931U1 (mobile) • RFCY41FVY4Z • android-arm64  • Android 15 (API 35)
  Windows (desktop)  • windows     • windows-x64    • Microsoft Windows [Version 10.0.19045.6332]
  Chrome (web)       • chrome      • web-javascript • Google Chrome 140.0.7339.129
  Edge (web)         • edge        • web-javascript • Microsoft Edge 134.0.3124.83

## Run the app on your phone
Use the device ID shown in the list above (in this case `RFCY41FVY4Z`):
flutter run -d RFCY41FVY4Z

## Useful variants
- **Hot reload/restart**:  
  While running, press `r` (reload) or `R` (restart) in the terminal.
- **Specify entrypoint file**:
  flutter run -d RFCY41FVY4Z -t lib/main.dart
- **Profile mode**:
  flutter run -d RFCY41FVY4Z --profile
- **Release mode**:
  flutter run -d RFCY41FVY4Z --release

## Troubleshooting
- If the phone shows as *unauthorized*:  
  Revoke USB debugging authorizations on the device, reconnect, and accept the RSA prompt.
- If ADB is missing:  
  Install [Android SDK Platform Tools](https://developer.android.com/studio/releases/platform-tools) and add them to your PATH.
- If Gradle/build issues occur:
  flutter doctor --android-licenses
  flutter clean
  flutter pub get
