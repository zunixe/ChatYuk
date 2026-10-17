import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils.dart';
import 'media_disk_cache.dart';

/// Cache POSTER foto chat — grid warna 8×8 (RGBA mentah, 256 byte) yang
/// dibaca SINKRON dan DILUKIS langsung (CustomPaint, lihat `PosterGrid`).
///
/// v2 (2026-10-17): dulu poster = JPEG 24px yang ditampilkan via
/// `Image.memory` → decode Flutter SELALU async → frame-1 tetap kosong lalu
/// poster muncul, lalu foto tajam = kedip ganda (terutama album 4 tile).
/// Grid piksel mentah tidak perlu decode sama sekali → frame-1 pasti bergambar.
///
/// Kenapa: foto chat terenkripsi → thumbnail asli harus di-DEKRIpsi (async),
/// jadi frame pertama bubble kosong (kotak) lalu foto "pop-in" = kedip —
/// terutama album multi-foto (4 tile muncul bergiliran). Poster kecil dibaca
/// sinkron saat `initState` → frame pertama SUDAH ada gambar (blur), lalu
/// foto tajam menggantikan dengan ukuran sama (tanpa lompatan/kedip).
///
/// PRIVASI (trade-off sadar): poster disimpan PLAIN (tanpa enkripsi) di
/// direktori privat app karena harus dibaca sinkron — [maxPx] × [maxPx]
/// piksel yang DI-BLUR, praktis tidak terbaca isinya. File hanya di dalam
/// sandbox app (tidak dapat diakses app lain tanpa root). Bounded + dibersihkan
/// saat logout.
class ChatPosterCache {
  ChatPosterCache._();
  static final ChatPosterCache instance = ChatPosterCache._();

  static const String _folderName = 'chat_posters_v2';
  static const String _legacyFolder = 'chat_posters_v1';

  /// Sisi grid poster (sel) & panjang byte RGBA yang valid.
  static const int gridSide = 8;
  static const int byteLength = gridSide * gridSide * 4;

  /// Lebar JPEG perantara saat membuat poster (native downscale → grid).
  static const int _maxPx = 24;

  /// Batas entri di memori (256 B/poster → ~77 KB).
  static const int _memCap = 300;

  final Map<String, Uint8List> _mem = {};
  String? _docs;

  /// Ukuran sisi poster (px) — dipakai generator.
  static int get maxPx => _maxPx;

  bool get isReady => _docs != null;

  Future<void> prewarm() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _docs = dir.path;
      final folder = Directory('$_docs/$_folderName');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      // Poster v1 (JPEG) tidak dipakai lagi → bersihkan sekali.
      final legacy = Directory('$_docs/$_legacyFolder');
      if (legacy.existsSync()) {
        unawaited(legacy.delete(recursive: true).then((_) {}, onError: (_) {}));
      }
    } catch (e) {
      dlog('[ChatPosterCache] prewarm error: $e');
    }
  }

  String _fileName(String messageId) => '${hashKey64(messageId)}.rgba';

  static bool isValid(Uint8List? b) => b != null && b.length == byteLength;

  /// Poster SINKRON (RAM → disk) — dipakai `initState` supaya frame pertama
  /// sudah bergambar. null bila belum ada (pemanggil pakai placeholder biasa).
  Uint8List? posterSync(String messageId) {
    if (messageId.isEmpty) return null;
    final mem = _mem[messageId];
    if (mem != null) return mem;
    final docs = _docs;
    if (docs == null) return null;
    try {
      final f = File('$docs/$_folderName/${_fileName(messageId)}');
      if (!f.existsSync()) return null;
      final bytes = f.readAsBytesSync();
      if (!isValid(bytes)) return null;
      _memPut(messageId, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _memPut(String messageId, Uint8List bytes) {
    final old = _mem.remove(messageId);
    if (old != null) _mem.remove(messageId);
    _mem[messageId] = bytes;
    while (_mem.length > _memCap) {
      _mem.remove(_mem.keys.first);
    }
  }

  /// Simpan poster (fire-and-forget tulis disk). Abaikan bila kosong.
  Future<void> save(String messageId, Uint8List bytes) async {
    if (messageId.isEmpty || !isValid(bytes)) return;
    _memPut(messageId, bytes);
    final docs = _docs;
    if (docs == null) return;
    try {
      final folder = Directory('$docs/$_folderName');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      final f = File('${folder.path}/${_fileName(messageId)}');
      await f.writeAsBytes(bytes, flush: false);
    } catch (e) {
      dlog('[ChatPosterCache] save error: $e');
    }
  }

  /// Hapus semua poster (logout / ganti akun).
  Future<void> clear() async {
    _mem.clear();
    try {
      final docs = _docs;
      if (docs == null) return;
      final d = Directory('$docs/$_folderName');
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }

  @visibleForTesting
  int get memLength => _mem.length;

  /// Test-only: kosongkan RAM (file disk tetap) untuk mensimulasikan COLD
  /// START — memastikan `posterSync` benar-benar membaca dari disk.
  @visibleForTesting
  void clearMemOnly() => _mem.clear();
}
