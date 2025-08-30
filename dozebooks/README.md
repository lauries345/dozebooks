# DozeBooks (Flutter) — MVP Skeleton

A cross‑platform audiobook player (Android + iOS) focused on **M4B playback**, **smart no‑repeat shuffle**, **sleep timer with fade + extend**, and **public‑domain discovery (LibriVox)**. Includes scaffolding for **one‑time unlock ($4.99)** and **banner ads**.

## Quick Start

1) Install Flutter (stable), Android Studio/Xcode toolchains.
2) Create a new Flutter project anywhere on your machine:
   ```bash
   flutter create doze_books
   cd doze_books
   ```
3) Replace the generated `lib/` and `pubspec.yaml` with the ones in this zip:
   - Copy the **lib/** folder here
   - Overwrite **pubspec.yaml**
4) Install dependencies:
   ```bash
   flutter pub get
   ```
5) iOS: enable **Background Modes → Audio, AirPlay, and Picture in Picture**.
   - In Xcode → Runner target → Signing & Capabilities → + Capability → Background Modes → check “Audio, AirPlay, and Picture in Picture”
6) Android: ensure the app targets SDK 34+; Flutter defaults are fine.
7) Run:
   ```bash
   flutter run
   ```

## Notes

- **M4B support**: handled by platform players (ExoPlayer/AVPlayer) via `just_audio`.
- **Background & media controls**: powered by `audio_service` + `just_audio`.
- **Downloads**: simple HTTP download via `dio` (MVP); consider background isolate / plugins later.
- **Premium**: stubbed with `in_app_purchase`. Wire real product IDs in both stores.
- **Ads**: `google_mobile_ads` banner widget used on Discover page when not premium.

## Roadmap (after MVP)

- Chapter parsing from MP4 atoms for M4B chapter list.
- Background downloads + pause/resume; Android `DownloadManager` and iOS background tasks.
- Cloud sync for positions (optional subscription later).
- Archive.org integration in Discover tab.
