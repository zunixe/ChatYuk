import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils.dart';

/// Cache ASPEK (w/h) foto chat per messageId — persisten lintas sesi.
///
/// Kenapa: `MessageModel` chat tidak menyimpan dimensi, jadi saat cold start
/// bubble foto belum tahu aspek → placeholder mulai KOTAK (persegi) lalu
/// berubah ke aspek asli setelah thumb ter-decode = lompatan ukuran (terasa
/// "kedip"). Dengan menyimpan aspek yang pernah diketahui, frame pertama
/// sudah memakai ukuran final → nol lompatan.
///
/// Bounded (FIFO 500) & dibersihkan saat logout/akun berganti.
class PhotoAspectCache {
  PhotoAspectCache._();
  static final PhotoAspectCache instance = PhotoAspectCache._();

  static const String _prefKey = 'chat_photo_aspect_v1';
  static const int _cap = 500;

  final Map<String, double> _aspect = {};
  SharedPreferences? _prefs;
  Timer? _saveDebounce;
  bool _dirty = false;

  /// Muat peta aspek tersimpan (dipanggil sekali saat bootstrap).
  Future<void> prewarm() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_prefKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      map.forEach((k, v) {
        final d = (v is num) ? v.toDouble() : double.tryParse('$v');
        if (d != null && d > 0) _aspect['$k'] = d;
      });
    } catch (e) {
      dlog('[PhotoAspectCache] prewarm error: $e');
    }
  }

  /// Aspek tersimpan untuk [messageId], atau null bila belum pernah diketahui.
  double? aspectOf(String messageId) {
    if (messageId.isEmpty) return null;
    final a = _aspect[messageId];
    return (a != null && a > 0) ? a : null;
  }

  /// Simpan aspek hasil decode (hanya bila valid).
  void remember(String messageId, int width, int height) {
    if (messageId.isEmpty || width <= 0 || height <= 0) return;
    final a = width / height;
    if (!a.isFinite || a <= 0) return;
    if (_aspect[messageId] == a) return;
    _aspect.remove(messageId);
    _aspect[messageId] = a;
    while (_aspect.length > _cap) {
      _aspect.remove(_aspect.keys.first);
    }
    _dirty = true;
    // Persist HANYA setelah prewarm (produksi memanggil prewarm saat boot).
    // Tanpa prewarm (mis. widget test) → memori saja, TANPA Timer tertinggal.
    if (_prefs == null) return;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), _flush);
  }

  Future<void> _flush() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_prefKey, jsonEncode(_aspect));
    } catch (e) {
      dlog('[PhotoAspectCache] save error: $e');
    }
  }

  /// Tulis segera (mis. saat app background / tampil ke disk).
  Future<void> flushNow() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    return _flush();
  }

  /// Bersihkan (logout / ganti akun) — termasuk data tersimpan.
  Future<void> clear() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _aspect.clear();
    _dirty = false;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.remove(_prefKey);
    } catch (_) {}
  }

  @visibleForTesting
  int get length => _aspect.length;
}
