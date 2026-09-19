import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'call_ui.dart';
import 'call_ui_channel.dart';

export 'call_ui.dart';

/// Buat implementasi [CallUi] sesuai platform.
///
/// Hanya Android yang punya jembatan native (ConnectionService). iOS/web/
/// desktop memakai [CallUiStub] — perilaku = layar panggilan Dart yang sudah
/// ada, sehingga kode tetap kompilasi di semua platform.
///
/// Di unit test, `defaultTargetPlatform`/`Platform.isAndroid` tidak reliable
/// di host — inject mock [CallUi] langsung ke `CallProvider(callUi: ...)`.
CallUi createCallUi() {
  if (!kIsWeb && Platform.isAndroid) {
    return CallUiChannel.instance;
  }
  return CallUiStub();
}
