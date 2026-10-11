import 'package:flutter/material.dart';

import '../config/strings.dart';

/// Jembatan netral untuk NAVIGASI & DIALOG UI yang dibutuhkan lapisan bawah
/// (providers/services) TANPA import `screens/` (boundary: provider dilarang
/// import screens). Pola sama [AdminGate]: field diisi dari composition root
/// (`main.dart`); null = fitur terkait dilewati.
///
/// Contoh isi (di-wire di main.dart):
/// - [incomingCallBuilder] → `IncomingCallScreen` (call_provider).
/// - [topupSheet]           → `showTopupSheet` (points_provider).
class NavGate {
  NavGate._();

  /// Builder layar panggilan masuk. Dipanggil `call_provider` saat perlu
  /// membuka `IncomingCallScreen`. Null → tak navigasi (aman; sistem tetap
  /// punya UI panggilan native).
  static Widget Function({
    required String callId,
    required String callerUid,
    required String callType,
    required String chatId,
    bool autoAccept,
  })? incomingCallBuilder;

  /// Tampilkan sheet topup YukCoin. Diisi `main.dart` → `showTopupSheet`.
  /// Null → provider menampilkan snack "segera hadir" (fallback).
  static void Function(BuildContext context, S s)? topupSheet;
}
