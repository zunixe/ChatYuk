import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import '../../utils.dart';
import 'package:path_provider/path_provider.dart';

/// Nama file cache = hash FNV-1a **64-bit** dari serverPath, hex 16 digit.
///
/// P1 (2026-10-11): dulu 32-bit → tabrakan mengikuti birthday paradox
/// (terukur ~10 tabrakan / 300k key). Karena path storage Supabase versioned
/// per-upload (jumlah file terus tumbuh), ini bisa membuat MEDIA TERTUKAR
/// (avatar A tampil sebagai B). 64-bit → tabrakan praktis nol.
///
/// Pakai BigInt agar aritmetika 64-bit tak overflow (Dart int = 64-bit,
/// FNV-1a butuh wrap 2^64; perkalian 64-bit penuh melampaui itu).
/// Murni & top-level: dipakai `MediaDiskCache`, `VideoFileCache`, `VideoPrefetch`.
String mediaCacheFileName(String serverPath) {
  final mask = (BigInt.one << 64) - BigInt.one;
  var h = BigInt.parse('cbf29ce484222325', radix: 16); // offset basis 64-bit
  final prime = BigInt.parse('100000001b3', radix: 16);
  for (final c in serverPath.codeUnits) {
    h = h ^ BigInt.from(c);
    h = (h * prime) & mask;
  }
  return h.toRadixString(16).padLeft(16, '0');
}

/// Hash FNV-1a 64-bit (hex 16 digit) dari string apa pun — untuk kunci
/// turunan (mis. `galb64:` dari base64, `poster_bmp_` dari path) TANPA
/// "hash atas hash" (dulu `'galb64:${base64.hashCode}'` → hash 32-bit yang
/// sudah bisa tabrakan, lalu di-hash lagi = ruang tabrakan makin besar).
String hashKey64(String s) => mediaCacheFileName(s);

/// Apakah kuota terlampaui (perlu buang LRU)? Murni & testable. Dipakai
/// `MediaDiskCache` dan `VideoFileCache`.
bool mediaQuotaExceeded(int total, int incoming, int maxBytes) =>
    total + incoming > maxBytes;

/// Cache DISK untuk semua media dari Supabase Storage (avatar, galeri
/// profil, voice) — sumber kebenaran lokal.
///
/// Aturan: load dari disk (instan, tanpa network); update = tulis ke
/// server + tulis ke disk; RAM hanya render-cache sesaat.
///
/// Filename = hash FNV-1a dari serverPath (path Supabase versioned per
/// upload) → media baru = file baru, tidak pernah konflik cache lama.
/// Index `index.json` menyimpan {serverPath: lastAccess} untuk LRU.
///
/// Kuota: [maxBytes] LRU — file terlama akses dihapus saat penuh
/// (voice & galeri path-nya unik per item, butuh batas ukuran).
class MediaDiskCache {
  MediaDiskCache._();
  static final MediaDiskCache instance = MediaDiskCache._();

  static const _dirName = 'media_cache';
  static const _indexName = 'index.json';
  /// Kuota 250MB — cukup galeri + voice tanpa memenuhi storage.
  static const int maxBytes = 250 * 1024 * 1024;
  /// P3b: batas jumlah entri index (cegah index.json membengkak).
  static const int _maxIndexEntries = 5000;

  final Map<String, DateTime> _index = {};
  bool _indexLoaded = false;
  String? _docs;

  /// True bila prewarm sudah jalan — readSync aman dipakai.
  bool get isReady => _docs != null;

  /// Tunggu prewarm siap, terbatas [timeout] — supaya pemanggil tidak
  /// memvonis disk-miss (lalu fetch network sia-sia) saat boot.
  Future<void> waitReady(
      {Duration timeout = const Duration(seconds: 1)}) async {
    if (_docs != null) return;
    final sw = Stopwatch()..start();
    while (_docs == null && sw.elapsed < timeout) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  String _fileName(String serverPath) => mediaCacheFileName(serverPath);

  String _pathFor(String serverPath) =>
      '$_docs/$_dirName/${_fileName(serverPath)}';

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    _docs = docs.path;
    final d = Directory('$_docs/$_dirName');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<void> _loadIndex() async {
    if (_indexLoaded) return;
    _indexLoaded = true;
    try {
      final f = File('$_docs/$_dirName/$_indexName');
      if (!f.existsSync()) return;
      final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      map.forEach((k, v) {
        final t = DateTime.tryParse('$v');
        if (t != null) {
          _index[k] = t;
          // Bangun peta balik filename → serverPath saat load, supaya LRU
          // (_enforceQuota) bisa mengurutkan file berdasar akses terakhir
          // tanpa perlu listing isi index lagi.
          _fileNameToPath[_fileName(k)] = k;
        }
      });
    } catch (e) {
      dlog('[MediaDisk] index load error: $e');
    }
  }

  Timer? _saveDebounce;

  /// Tulis index ter-coalesce (maks 1 tulis per 2 dtk) — dulu tiap
  /// read/write memicu tulis index.json sinkron dengan flush.
  void _scheduleSaveIndex() {
    if (_saveDebounce?.isActive == true) return;
    _saveDebounce = Timer(const Duration(seconds: 2), () {
      _saveDebounce = null;
      unawaited(_saveIndex());
    });
  }

  Future<void> _saveIndex() async {
    try {
      final f = File('$_docs/$_dirName/$_indexName');
      // Async write — index bisa besar (250 MB cache) dan writeSync+flush
      // di main isolate berisiko jank UI.
      await f.writeAsString(
        jsonEncode(_index.map((k, v) => MapEntry(k, v.toIso8601String()))),
        flush: true,
      );
    } catch (e) {
      dlog('[MediaDisk] index save error: $e');
    }
  }

  /// Warm-up SEBELUM widget pertama render — simpan documents path supaya
  /// [readSync] (sinkron) bisa dipakai kapan pun setelah ini (anti-blink).
  Future<void> prewarm() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      _docs = docs.path;
      final d = Directory('$_docs/$_dirName');
      if (!d.existsSync()) d.createSync(recursive: true);
      await _loadIndex();
    } catch (e) {
      dlog('[MediaDisk] prewarm error: $e');
    }
  }

  Future<Uint8List?> read(String serverPath) async {
    if (serverPath.isEmpty) return null;
    try {
      await _dir();
      await _loadIndex();
      final f = File(_pathFor(serverPath));
      if (!f.existsSync()) return null;
      _index[serverPath] = DateTime.now();
      _fileNameToPath[_fileName(serverPath)] = serverPath;
      _scheduleSaveIndex();
      return f.readAsBytesSync();
    } catch (e) {
      dlog('[MediaDisk] read error: $e');
      return null;
    }
  }

  /// Baca SINKRON (file kecil seperti avatar) — foto tampil pada frame
  /// pertama tanpa async. Wajib [prewarm] pernah dipanggil sebelumnya.
  Uint8List? readSync(String serverPath) {
    if (serverPath.isEmpty || _docs == null) return null;
    try {
      final f = File(_pathFor(serverPath));
      if (!f.existsSync()) return null;
      // Update LRU di readSync (dulu cuma read yang update — cache panas
      // yang dibaca sinkron tidak pernah "disentuh" → LRU salah hapus).
      _index[serverPath] = DateTime.now();
      _fileNameToPath[_fileName(serverPath)] = serverPath;
      _scheduleSaveIndex();
      return f.readAsBytesSync();
    } catch (e) {
      dlog('[MediaDisk] readSync error: $e');
      return null;
    }
  }

  /// Baca BANYAK path PARALEL (async, non-blocking) — untuk daftar panjang
  /// (mis. 200 thumb galeri grup). Dulu loop `readSync` = 200 stat + 200 baca
  /// file di UI thread → stall. Ini pakai `read()` async → tak blok frame.
  /// Return map serverPath → bytes (hanya yang HIT disk).
  Future<Map<String, Uint8List>> readManyAsync(List<String> paths) async {
    final out = <String, Uint8List>{};
    if (paths.isEmpty) return out;
    final results = await Future.wait(paths.map((p) async {
      final b = await read(p);
      return MapEntry(p, b);
    }));
    for (final e in results) {
      final b = e.value;
      if (b != null && b.isNotEmpty) out[e.key] = b;
    }
    return out;
  }

  /// File lokal untuk suatu serverPath (null jika belum ter-cache) —
  /// dipakai pemutar audio yang butuh DeviceFileSource.
  Future<File?> fileFor(String serverPath) async {
    if (serverPath.isEmpty) return null;
    await _dir();
    final f = File(_pathFor(serverPath));
    return f.existsSync() ? f : null;
  }

  Future<void> write(String serverPath, Uint8List bytes) async {
    if (serverPath.isEmpty || bytes.isEmpty) return;
    try {
      await _dir();
      await _loadIndex();
      // P2b (2026-10-11): `_enforceQuota` TIDAK tiap write — dulu d.list()
      // SELURUH direktori (bisa ribuan file) tiap menulis 1 file → makin
      // lambat seiring cache membesar. Sekarang: throttle (min 30 dtk antar
      // audit) ATAU jadwalkan bila total terlacak mendekati kuota. _totalBytes
      // dipelihara agar tak perlu list tiap kali.
      await _maybeEnforceQuota(bytes.length);
      final f = File(_pathFor(serverPath));
      await f.writeAsBytes(bytes, flush: true);
      _index[serverPath] = DateTime.now();
      _fileNameToPath[_fileName(serverPath)] = serverPath;
      _totalBytes += bytes.length;
      // P3b: cap JUMLAH entri index (bukan byte) → `index.json` tak membengkak
      // (path versioned per-upload menumpuk). Buang entri terlama dari INDEX
      // saja; file-nya dibersihkan oleh LRU byte (_enforceQuota).
      if (_index.length > _maxIndexEntries) {
        final removeCount = _index.length - _maxIndexEntries;
        final oldest = _index.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        for (var i = 0; i < removeCount; i++) {
          final k = oldest[i].key;
          _index.remove(k);
          _fileNameToPath.remove(_fileName(k));
        }
      }
      _scheduleSaveIndex();
    } catch (e) {
      dlog('[MediaDisk] write error: $e');
    }
  }

  // ── P2b: throttle audit kuota ──
  int _totalBytes = 0;
  DateTime? _lastQuotaCheck;
  static const Duration _quotaInterval = Duration(seconds: 30);

  /// Audit kuota ter-throttle: jalan bila (a) belum pernah, (b) sudah lewat
  /// [_quotaInterval], atau (c) total terlacak + incoming > kuota (urgen).
  Future<void> _maybeEnforceQuota(int incoming) async {
    final now = DateTime.now();
    final urgent = _totalBytes + incoming > maxBytes;
    final stale = _lastQuotaCheck == null ||
        now.difference(_lastQuotaCheck!) >= _quotaInterval;
    if (!urgent && !stale) return;
    _lastQuotaCheck = now;
    _totalBytes = await _enforceQuota(incoming);
  }

  /// LRU: hapus file dengan akses terlama sampai ada ruang untuk [incoming].
  /// Return total bytes tersisa (untuk pelacakan `_totalBytes`).
  Future<int> _enforceQuota(int incoming) async {
    try {
      final d = Directory('$_docs/$_dirName');
      var total = 0;
      final files = <(File, int)>[];
      await for (final f in d.list()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        if (name == _indexName) continue;
        final len = f.lengthSync();
        total += len;
        files.add((f, len));
      }
      if (!mediaQuotaExceeded(total, incoming, maxBytes)) return total;
      final byName = {
        for (final (f, len) in files) f.uri.pathSegments.last: (f, len),
      };
      final names = byName.keys.toList()
        ..sort((a, b) => (_index[_pathOf(a)] ?? DateTime(2000))
            .compareTo(_index[_pathOf(b)] ?? DateTime(2000)));
      for (final name in names) {
        if (total + incoming <= maxBytes) break;
        final entry = byName[name];
        if (entry == null) continue;
        try {
          await entry.$1.delete();
          total -= entry.$2;
        } catch (_) {}
      }
      final existing = byName.keys.toSet();
      _index.removeWhere((k, v) => !existing.contains(_fileName(k)));
      _fileNameToPath.removeWhere((name, path) => !existing.contains(name));
      _scheduleSaveIndex();
      return total;
    } catch (e) {
      dlog('[MediaDisk] quota error: $e');
      return 0;
    }
  }

  /// Rekonstruksi serverPath dari filename hash — butuh index terbalik.
  final Map<String, String> _fileNameToPath = {};
  String? _pathOf(String fileName) => _fileNameToPath[fileName];

  /// Daftarkan pemetaan path → filename (dipanggil tiap write/read index).
  void _track(String serverPath) =>
      _fileNameToPath[_fileName(serverPath)] = serverPath;

  /// Hapus semua file media yang TIDAK ada di [activePaths] — dipakai
  /// avatar (path versioned per upload → versi lama jadi sampah).
  Future<void> keepOnly(Set<String> activePaths) async {
    try {
      for (final p in activePaths) {
        _track(p);
      }
      final active = activePaths.map(_fileName).toSet();
      final d = Directory('$_docs/$_dirName');
      await for (final f in d.list()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        if (name == _indexName) continue;
        if (!active.contains(name)) {
          try {
            await f.delete();
          } catch (_) {}
          _index.removeWhere((k, v) => _fileName(k) == name);
        }
      }
      // Bersihkan juga index terbalik untuk file yang sudah dihapus.
      _fileNameToPath.removeWhere((name, path) => !active.contains(name));
      _scheduleSaveIndex();
    } catch (e) {
      dlog('[MediaDisk] keepOnly error: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      final d = Directory('$_docs/$_dirName');
      if (d.existsSync()) await d.delete(recursive: true);
      _index.clear();
      _fileNameToPath.clear();
      _indexLoaded = false;
    } catch (_) {}
  }
}
