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

/// State view-once per messageId (countdown/kunci). GLOBAL (lintas screen)
/// karena viewer & bubble berbagi tick yang sama.
///
/// BOUNDED (R4/R6): dulu tumbuh per pesan view-once dibuka tanpa batas
/// (dibersihkan hanya saat expired via remove(id)) → sesi lama menumpuk
/// ViewOnceTick. Cap FIFO: entri TERTUA dibuang saat melebihi. Aman: entri
/// yang SEDANG dibuka tak pernah jadi "tertua" (baru dimasukkan), dan
/// pembuangan tak menyentuh objek yang dipegang widget (bubble cek
/// `identical` sebelum pakai — lihat view_once_image.dart:130).
final viewOnceStates = <String, ViewOnceTick>{};

/// Batas jumlah state view-once di memori.
const int viewOnceStatesMax = 100;

/// Daftarkan [tick] untuk [id] dengan cap FIFO. Mengembalikan objek yang
/// dipakai (existing bila ada, atau yang baru).
ViewOnceTick putViewOnceState(String id, ViewOnceTick tick) {
  final existing = viewOnceStates[id];
  if (existing != null) return existing;
  if (viewOnceStates.length >= viewOnceStatesMax) {
    viewOnceStates.remove(viewOnceStates.keys.first);
  }
  viewOnceStates[id] = tick;
  return tick;
}

