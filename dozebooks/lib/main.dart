library refactored_app;
import 'dart:async';
import 'dart:math';
import 'dart:io' show File, Directory, Platform;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart'; // <-- add this
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart'; // MPVLogLevel
part 'parts/OneScreenAudiobook.dart';
part 'parts/_OneScreenAudiobookState.dart';
part 'parts/_Book.dart';
part 'parts/_SettingsResult.dart';
part 'parts/_internals.dart';
part 'parts/_ui_helpers.dart';
part 'parts/_settings.dart';
part 'parts/_fades.dart';
part 'parts/_shuffle.dart';
part 'parts/_file_picking.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Silence MPV logs (desktop). On mobile this is ignored.
  JustAudioMediaKit.mpvLogLevel = MPVLogLevel.error;
  JustAudioMediaKit.ensureInitialized();

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'BookShuffle',
    themeMode: ThemeMode.dark, // <<< Force dark theme
    theme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      useMaterial3: true,
      brightness: Brightness.light,
    ),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      useMaterial3: true,
      brightness: Brightness.dark,
    ),
    home: const OneScreenAudiobook(),
  ));
}