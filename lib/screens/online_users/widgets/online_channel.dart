import 'package:flutter/material.dart';

import '../../../config/strings.dart';

/// Channel daftar Online — "Semua" vs "Teman". Konsep seperti channel
/// berlangganan; tinggal tambah nilai enum (mis. `business`) untuk ekspansi.
///
/// - [all]: tampilkan SEMUA user online (privasi presence tetap dijaga server).
/// - [friends]: hanya teman (mutual follow) yang tampil. User yang di-hide
///   tetap ikut aturan channel ini.
enum OnlineChannel {
  all,
  friends,
  /// BUKAN channel filter — item yang membuka halaman "Orang Sekitar".
  /// Ikut di dropdown channel supaya AppBar lebih rapi, tapi tidak dipersist
  /// dan tidak menyaring daftar (langsung navigasi).
  nearby;

  /// Channel yang benar-benar menyaring daftar (bukan aksi navigasi).
  bool get isFilter => this == all || this == friends;

  /// Label UI (bilingual via `S`).
  String label(S s) => switch (this) {
    OnlineChannel.all => s.filterAll,
    OnlineChannel.friends => s.filterFriends,
    OnlineChannel.nearby => s.nearbyTitle,
  };

  /// Ikon tombol — berubah sesuai channel aktif.
  IconData get icon => switch (this) {
    OnlineChannel.all => Icons.public_rounded,
    OnlineChannel.friends => Icons.people_alt_rounded,
    OnlineChannel.nearby => Icons.explore_outlined,
  };

  /// Nilai persist (prefs).
  String get wire => name;

  /// Parse aman dari prefs (fallback `all`). `nearby` bukan channel filter →
  /// tidak pernah dipulihkan sebagai channel aktif.
  static OnlineChannel fromWire(String? v) {
    for (final c in OnlineChannel.values) {
      if (c.isFilter && c.name == v) return c;
    }
    return OnlineChannel.all;
  }
}
