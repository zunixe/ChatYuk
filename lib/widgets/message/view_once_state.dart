import 'dart:async';

import 'package:flutter/foundation.dart';

import 'image_decode_core.dart';

// ── View Once Image ──────────────────────────────────────────────────────────
enum ViewOnceState { idle, viewing, expired }

// Timer & state persist di luar widget lifecycle — ListView.builder recycle
// widget saat scroll, tapi timer harus terus jalan & state tidak boleh reset.
/// Durasi view-once efektif (detik): null/negatif = legacy 10 dtk,
/// 0 = sampai ditutup (mode 1x lihat), N = countdown N detik.
int resolveViewOnceSecs(int? raw) => raw == null || raw < 0 ? 10 : raw;

class ViewOnceTick {
  int left = 10;

  /// Total countdown detik untuk pesan ini (0 = tanpa timer, sampai ditutup).
  int totalSecs = 10;
  Timer? timer;
  final ValueNotifier<int> countdown = ValueNotifier<int>(10);
  ViewOnceState _state = ViewOnceState.idle;
  final ValueNotifier<ViewOnceState> stateNotifier =
      ValueNotifier<ViewOnceState>(ViewOnceState.idle);
  bool viewerOpen = false;
  DecodedImage? decoded;

  ViewOnceState get state => _state;
  set state(ViewOnceState s) {
    _state = s;
    stateNotifier.value = s;
  }

  void dispose() {
    timer?.cancel();
    countdown.dispose();
    stateNotifier.dispose();
  }
}

final viewOnceStates = <String, ViewOnceTick>{};

