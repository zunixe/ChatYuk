import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../../utils.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/message_model.dart';
import '../../services/storage_photo_service.dart';
import 'message_store.dart';


// Top-level function untuk compute() â€” decrypt string tunggal (foto) di background
Future<String?> _decStr(Map<String, dynamic> args) async {
  try {
    final encoded = args['encoded'] as String;
    final keyBytes = (args['keyBytes'] as List<dynamic>).cast<int>();
    final key = SecretKey(List<int>.from(keyBytes));
    final aes = AesGcm.with256bits();
    final payload =
        jsonDecode(utf8.decode(base64Decode(encoded))) as Map<String, dynamic>;
    final box = SecretBox(
      base64Decode(payload['c'] as String),
      nonce: base64Decode(payload['n'] as String),
      mac: Mac(base64Decode(payload['m'] as String)),
    );
    final clear = await aes.decrypt(box, secretKey: key);
    return utf8.decode(clear);
  } catch (_) {
    return null;
  }
}

// Top-level function untuk compute() â€” decrypt BANYAK foto sekaligus dalam
// SATU isolate. Baca file + decrypt di background; hasil Map<messageId, b64>.
// Jauh lebih cepat daripada decrypt satu-satu (tiap call spawn isolate baru).
Future<Map<String, String>?> _decBatch(Map<String, dynamic> args) async {
  try {
    final paths = (args['paths'] as Map).cast<String, String>();
    final keyBytes = (args['keyBytes'] as List<dynamic>).cast<int>();
    final key = SecretKey(List<int>.from(keyBytes));
    final aes = AesGcm.with256bits();
    final result = <String, String>{};
    await Future.wait(
      paths.entries.map((e) async {
        try {
          final f = File(e.value);
          if (!await f.exists()) return;
          final encoded = await f.readAsString();
          final payload =
              jsonDecode(utf8.decode(base64Decode(encoded)))
                  as Map<String, dynamic>;
          final box = SecretBox(
            base64Decode(payload['c'] as String),
            nonce: base64Decode(payload['n'] as String),
            mac: Mac(base64Decode(payload['m'] as String)),
          );
          final clear = await aes.decrypt(box, secretKey: key);
          result[e.key] = utf8.decode(clear);
        } catch (_) {}
      }),
    );
    return result;
  } catch (_) {
    return null;
  }
}

/// Cache pesan lokal ter-enkripsi (AES-GCM).
/// Kunci AES disimpan aman di Android Keystore via flutter_secure_storage.
/// Data pesan disimpan di shared_preferences dalam bentuk base64 ciphertext.
class MessageCache {
  MessageCache._();
  static final MessageCache instance = MessageCache._();

  static const _keyPrefix = 'chat_cache_v2_';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final _aes = AesGcm.with256bits();

  // In-memory cache: sekali decrypt, buka ulang chat tidak perlu decrypt lagi.
  // Dibatasi 30 chat â€” LRU sederhana, buang yang paling lama saat penuh.
  final Map<String, List<MessageModel>> _memCache = {};
  // PERF: 30 → 8. Tiap entri = seluruh pesan satu chat TERMASUK `imageData`
  // base64 foto (bisa ~2MB/foto). 30 chat berisi foto bisa menahan ratusan MB
  // → GC storm → "ngetik ngelag setelah app dipakai lama" (restart normal lagi
  // karena cache ini kosong). 8 chat cukup untuk yang sering dibuka, hemat
  // memori drastis; chat lain tetap dibaca dari disk (SQLite) saat dibuka.
  static const _memCacheMax = 8;

  SecretKey? _key;

  Future<SecretKey>? _keyFuture;

  Future<SecretKey> _getKey() async {
    if (_key != null) return _key!;
    // Kalau _loadKey gagal (mis. secure-storage belum siap), JANGAN simpan
    // future yang gagal — future gagal "teracun" selamanya dan semua call
    // berikutnya ikut throw (persistensi pesan rusak sepanjang sesi).
    // Reset supaya call berikutnya mencoba lagi.
    try {
      _keyFuture ??= _loadKey();
      return await _keyFuture!;
    } catch (e) {
      _keyFuture = null;
      _key = null;
      rethrow;
    }
  }

  Future<SecretKey> _loadKey() async {
    const keyId = 'chatyuk_msg_key_v1';
    final existing = await _storage.read(key: keyId);
    if (existing != null && existing.isNotEmpty) {
      _key = SecretKey(base64Decode(existing));
    } else {
      final newKey = await _aes.newSecretKey();
      await _storage.write(
        key: keyId,
        value: base64Encode(await newKey.extractBytes()),
      );
      _key = newKey;
    }
    return _key!;
  }

  Future<String> _encrypt(String plain, SecretKey key) async {
    final iv = _aes.newNonce();
    final secretBox = await _aes.encrypt(
      utf8.encode(plain),
      secretKey: key,
      nonce: iv,
    );
    final payload = {
      'n': base64Encode(secretBox.nonce),
      'c': base64Encode(secretBox.cipherText),
      'm': base64Encode(secretBox.mac.bytes),
    };
    return base64Encode(utf8.encode(jsonEncode(payload)));
  }

  Future<String> _decrypt(String encoded, SecretKey key) async {
    final payload =
        jsonDecode(utf8.decode(base64Decode(encoded))) as Map<String, dynamic>;
    final box = SecretBox(
      base64Decode(payload['c'] as String),
      nonce: base64Decode(payload['n'] as String),
      mac: Mac(base64Decode(payload['m'] as String)),
    );
    final clear = await _aes.decrypt(box, secretKey: key);
    return utf8.decode(clear);
  }

  /// Enkripsi string apa pun (dipakai juga oleh PhotoCache untuk file foto).
  Future<String> encryptString(String plain) async {
    final key = await _getKey();
    return _encrypt(plain, key);
  }

  /// Dekripsi string hasil encryptString.
  Future<String> decryptString(String encoded) async {
    final key = await _getKey();
    return _decrypt(encoded, key);
  }

  /// Dekripsi di background isolate â€” untuk PhotoCache supaya buka chat
  /// tidak freeze saat decrypt banyak foto sekaligus.
  Future<String?> decryptStringAsync(String encoded) async {
    try {
      final key = await _getKey();
      final keyBytes = await key.extractBytes();
      return await compute(_decStr, {'encoded': encoded, 'keyBytes': keyBytes});
    } catch (_) {
      return null;
    }
  }

  /// Dekripsi BANYAK foto dalam SATU isolate (baca file + decrypt).
  /// paths = Map<messageId, pathFileEnkripsi> â†’ hasil Map<messageId, b64>.
  Future<Map<String, String>?> decryptMany(Map<String, String> paths) async {
    try {
      if (paths.isEmpty) return {};
      final key = await _getKey();
      final keyBytes = await key.extractBytes();
      return await compute(_decBatch, {'paths': paths, 'keyBytes': keyBytes});
    } catch (_) {
      return null;
    }
  }

  /// Simpan daftar pesan untuk sebuah chat (key = chatId/roomId).
  /// Kirim list kosong untuk menghapus cache chat tersebut.
  /// imageData di-strip (foto disimpan terpisah di PhotoCache) supaya
  /// cache pesan tetap kecil dan cepat dibaca.
  ///
  /// Layer disk = SQLite terenkripsi (MessageStore), bukan lagi blob prefs.
  ///
  /// PERF: penulisan disk (SQLCipher encrypt + tulis, bisa ratusan baris)
  /// DITUNDA ke microtask berikutnya — TIDAK memblok frame saat ini. Saat
  /// dipanggil dari `onCancel` stream (tutup chat), dulu tulis ini jatuh di
  /// frame transisi pop → "tutup chat ngelag". Memori (sinkron) tetap di-set
  /// segera supaya pembacaan berikutnya instan.
  Future<void> saveMessages(String chatKey, List<MessageModel> messages) async {
    _memCacheUpdate(chatKey, messages);
    // Salin ringan (strip imageData) SEKARANG (di frame pemanggil), lalu
    // tulis disk di microtask agar tidak berebut dengan transisi.
    final rows = messages
        .map((m) {
          final map = m.toMap();
          map['imageData'] = '';
          return MessageModel.fromMap(m.id, map);
        })
        .toList();
    await Future<void>.delayed(Duration.zero);
    try {
      await _ensureDb();
      if (rows.isEmpty) {
        await MessageStore.instance.clearChat(chatKey);
      } else {
        await MessageStore.instance.saveMessages(chatKey, rows);
      }
    } catch (e) {
      dlog('[MessageCache] saveMessages $chatKey ignored: $e');
    }
  }

  /// Buka DB SQLite dengan passphrase dari kunci AES secure storage.
  Future<void> _ensureDb() async {
    if (MessageStore.instance.isOpen) return;
    final key = await _getKey();
    await MessageStore.instance.open(base64Encode(await key.extractBytes()));
  }

  /// Warm-up saat bootstrap: buka DB + baca kunci lebih awal supaya buka
  /// chat pertama tidak menanggung latensi Keystore, dan sekalian purge
  /// sisa cache prefs format lama v2.
  Future<void> prewarmDb() async {
    try {
      await _ensureDb();
      // Purge sisa cache format prefs lama (pesan v2, list chat, objek
      // timeline/rooms) — semuanya kini tinggal di SQLite.
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs
          .getKeys()
          .where((k) =>
              k.startsWith(_keyPrefix) ||
              k.startsWith('chats_list_v1_') ||
              k.startsWith('obj_v1_'))
          .toList();
      for (final k in legacy) {
        await prefs.remove(k);
      }
    } catch (e) {
      // Jangan telan total — bantu diagnosa (terlihat di build debug/profile).
      dlog('[CACHE] prewarmDb gagal: $e');
    }
  }

  // â”€â”€ List private chat / timeline / rooms (persist antar restart app) â”€â”€â”€â”€â”€
  // Semua blob generik kini di tabel `kv` SQLite terenkripsi â€” bukan lagi
  // prefs+AES. API tidak berubah supaya call site (timeline, room, chat
  // list) tidak perlu disentuh.

  /// Snapshot in-memory list chat terakhir (per key) — supaya UI bisa
  /// membaca data (mis. `lastReadAt` untuk centang-2) TANPA await/decrypt:
  /// satu hop async yang hilang = centang-2 terisi sejak frame pertama.
  ///
  /// BOUNDED: dulu unbounded  key `chats_list_v1_<uid>` (per akun/device)
  /// + key lain menumpuk sepanjang sesi  memori naik terus (GC pressure =
  /// lag seiring waktu). FIFO evict kalau lewat cap (pola sama `_memRawObj`).
  final Map<String, List<Map<String, dynamic>>> _memRawList = {};
  static const _memRawListMax = 20;

  void _putMemRawList(String key, List<Map<String, dynamic>> rows) {
    _memRawList.remove(key);
    _memRawList[key] = rows;
    while (_memRawList.length > _memRawListMax) {
      _memRawList.remove(_memRawList.keys.first);
    }
  }

  Future<void> saveRawList(String key, List<Map<String, dynamic>> rows) async {
    try {
      if (rows.isEmpty) return;
      // Memori dulu (sinkron untuk pembaca berikutnya), lalu disk.
      _putMemRawList(key, List<Map<String, dynamic>>.of(rows));
      await _ensureDb();
      await MessageStore.instance.saveKv(key, jsonEncode(rows));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> loadRawList(String key) async {
    try {
      final mem = _memRawList[key];
      if (mem != null && mem.isNotEmpty) return mem;
      final json = await _loadKvSafe(key);
      if (json == null || json.isEmpty) return [];
      final list = jsonDecode(json) as List<dynamic>;
      final rows = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _putMemRawList(key, rows);
      return rows;
    } catch (_) {
      return [];
    }
  }

  /// Versi SINKRON: langsung dari memori, tanpa await. Kosong bila snapshot
  /// belum pernah dimuat di sesi ini (layar tetap menunggu jalur async).
  List<Map<String, dynamic>> peekRawList(String key) =>
      _memRawList[key] ?? const [];

  /// Muat list chat dari SQLite ke memori (dipanggil saat prewarm/bootstrap)
  /// supaya `peekRawList` sudah terisi begitu user membuka chat pertama.
  Future<void> preloadRawList(String key) async {
    try {
      if ((_memRawList[key]?.length ?? 0) > 0) return;
      await loadRawList(key);
    } catch (_) {}
  }

  Future<void> removeRawList(String key) async {
    try {
      await _ensureDb();
      await MessageStore.instance.removeKv(key);
    } catch (_) {}
  }

  // â”€â”€ Objek generic (timeline, rooms) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Memori objek (sinkron) — supaya `peekRawObj` bisa dipakai baca
  /// sebelum frame pertama (anti-glich: bintang/reaksi tampil instan).
  ///
  /// BOUNDED: key `starred:<chat>`/`reactions:<chat>` tumbuh per chat yang
  /// dibuka. Tanpa cap, sesi panjang menahan objek semua chat → memori naik
  /// terus (GC pressure = lag seiring waktu). FIFO evict kalau lewat cap.
  final Map<String, Map<String, dynamic>> _memRawObj = {};
  static const _memRawObjMax = 60;

  void _putMemRawObj(String key, Map<String, dynamic> obj) {
    if (obj.isEmpty) return;
    if (!_memRawObj.containsKey(key) && _memRawObj.length >= _memRawObjMax) {
      _memRawObj.remove(_memRawObj.keys.first);
    }
    _memRawObj[key] = obj;
  }

  Future<void> saveRawObj(String key, Map<String, dynamic> obj) async {
    try {
      if (obj.isEmpty) return;
      // Memori dulu (sinkron untuk pembaca berikutnya), lalu disk.
      _putMemRawObj(key, Map<String, dynamic>.of(obj));
      await _ensureDb();
      await MessageStore.instance.saveKv(key, jsonEncode(obj));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> loadRawObj(String key) async {
    try {
      final mem = _memRawObj[key];
      if (mem != null && mem.isNotEmpty) return mem;
      final json = await _loadKvSafe(key);
      if (json == null || json.isEmpty) return {};
      final obj = jsonDecode(json);
      if (obj is Map<String, dynamic>) {
        _putMemRawObj(key, obj);
        return obj;
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Versi SINKRON: langsung dari memori, tanpa await. Kosong bila snapshot
  /// belum pernah dimuat di sesi ini (pemanggil fallback ke jalur async).
  Map<String, dynamic> peekRawObj(String key) =>
      _memRawObj[key] ?? const {};

  /// Muat objek dari SQLite ke memori (dipanggil saat prewarm/bootstrap)
  /// supaya `peekRawObj` sudah terisi begitu user membuka chat pertama.
  Future<void> preloadRawObj(String key) async {
    try {
      if ((_memRawObj[key]?.isNotEmpty ?? false)) return;
      await loadRawObj(key);
    } catch (_) {}
  }

  /// Preload SEMUA objek ber-key awalan [prefix] ke memori sekaligus
  /// (mis. `starred:` per-chat) — supaya bintang tampil instan di cold start
  /// tanpa menunggu disk per-chat.
  Future<void> preloadObjPrefix(String prefix) async {
    try {
      await _ensureDb();
      final rows = await MessageStore.instance.loadKvPrefix(prefix);
      for (final e in rows.entries) {
        if (_memRawObj.containsKey(e.key)) continue;
        try {
          final obj = jsonDecode(e.value);
          if (obj is Map<String, dynamic>) _putMemRawObj(e.key, obj);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> removeRawObj(String key) async {
    try {
      await _ensureDb();
      await MessageStore.instance.removeKv(key);
    } catch (_) {}
  }

  Future<String?> _loadKvSafe(String key) async {
    await _ensureDb();
    return MessageStore.instance.loadKv(key);
  }

  /// Ambil pesan cache (null jika tidak ada).
  /// Fast path: mem-cache. Slow path: SQLite terenkripsi (satu query).
  ///
  /// DEDUPE IN-FLIGHT: beberapa pemanggil bisa minta chatKey SAMA bersamaan
  /// (StreamBuilder replay + preload + reload). Tanpa dedupe, SQLCipher
  /// men-serialize query-nya → tiap pemanggil menunggu lock (terukur 500-1300ms
  /// per query saat 3 panggilan konkuren untuk chat yang sama). Kini yang
  /// sedang jalan di-share → satu query saja.
  final Map<String, Future<List<MessageModel>>> _loadInflight = {};

  Future<List<MessageModel>> loadMessages(
    String chatKey, {
    DateTime? before,
  }) async {
    // Paging riwayat lebih lama TIDAK lewat mem-cache (hanya window terbaru).
    if (before == null) {
      final mem = _memCache[chatKey];
      if (mem != null) {
        _memCacheUpdate(chatKey, mem); // refresh urutan LRU
        return mem;
      }
      final running = _loadInflight[chatKey];
      if (running != null) return running;
    }
    final fut = _loadMessagesImpl(chatKey, before: before);
    if (before == null) {
      _loadInflight[chatKey] = fut;
      fut.whenComplete(() {
        if (identical(_loadInflight[chatKey], fut)) {
          _loadInflight.remove(chatKey);
        }
      });
    }
    return fut;
  }

  Future<List<MessageModel>> _loadMessagesImpl(
    String chatKey, {
    DateTime? before,
  }) async {
    try {
      final sw = Stopwatch()..start();
      await _ensureDb();
      final msgs = await MessageStore.instance.loadMessages(
        chatKey,
        before: before,
      );
      dlog(
        '[CACHE-TIME] $chatKey sqlite=${sw.elapsedMilliseconds}ms n=${msgs.length}',
      );
      if (before == null) _memCacheUpdate(chatKey, msgs);
      return msgs;
    } catch (e) {
      dlog('[MessageCache] loadMessages $chatKey error: $e');
      return [];
    }
  }

  // LRU sederhana: list kosong = hapus; saat penuh buang yang paling lama.
  //
  // PERF/HEAP: yang DISIMPAN di mem-cache adalah SALINAN yang sudah "dikurus" �?"
  // base64 foto full-res dibuang (diganti ''), path voice/video DIPERTAHANKAN.
  // Alasan: `saveMessages(cacheKey, _current)` mengirim list `_current` yang
  // SAMA (shared ref) dengan sesi aktif �?" kalau kita mutasi elemennya, sesi
  // hidup ikut rusak. Jadi kita bikin list BARU berisi `copyWith` yang sudah
  // dibuang base64-nya. Foto yang dibuang otomatis diisi ulang dari
  // `PhotoCache` (disk) lewat `_needsPhotoFill`/`loadPhotosAsync` saat chat
  // dibuka lagi (murah), sedangkan RAM turun drastis (tiap foto bisa ~2MB).
  void _memCacheUpdate(String chatKey, List<MessageModel> messages) {
    if (messages.isEmpty) {
      _memCache.remove(chatKey);
      return;
    }
    _memCache.remove(chatKey);
    _memCache[chatKey] = _slimForMem(messages);
    while (_memCache.length > _memCacheMax) {
      _memCache.remove(_memCache.keys.first);
    }
  }

  /// Salin list pesan untuk mem-cache dengan base64 FOTO dibuang ('').
  /// Hanya tipe foto (image/view_once/video_once) yang base64-nya di-strip;
  /// path storage (voice/video) dan teks tetap utuh �?" jangan sentuh, karena
  /// `imageData` polimorfik (base64 ATAU path). Bila tidak ada yang perlu
  /// dikurus, kembalikan list asli apa adanya (hindari alokasi sia-sia).
  List<MessageModel> _slimForMem(List<MessageModel> messages) {
    var changed = false;
    final out = <MessageModel>[];
    for (final m in messages) {
      final isPhoto = m.type == 'image' ||
          m.type == 'view_once' ||
          m.type == 'view_once_expired' ||
          m.type == 'video_once' ||
          m.type == 'video_once_expired';
      // Foto dengan base64 (bukan path storage) = kandidat strip.
      if (isPhoto &&
          m.imageData.isNotEmpty &&
          !StoragePhotoService.instance.isPath(m.imageData) &&
          !StoragePhotoService.instance.isVoicePath(m.imageData)) {
        out.add(m.copyWith(imageData: ''));
        changed = true;
      } else {
        out.add(m);
      }
    }
    return changed ? out : messages;
  }

  /// Baca pesan dari RAM TANPA async/decrypt — untuk emit frame-pertama
  /// instan saat buka chat (memori-first). Kosong bila chat belum di cache
  /// memori (setelah cold start) → pemanggil fallback ke `loadMessages`.
  List<MessageModel>? peekMessages(String chatKey) {
    final mem = _memCache[chatKey];
    if (mem != null) {
      _memCacheUpdate(chatKey, mem); // refresh LRU
      return mem;
    }
    return null;
  }

  /// Prefetch pesan ke memori (fire-and-forget) — dipanggil saat user TAP
  /// item chat, supaya saat screen mount cache sudah panas → bubble instant.
  Future<void> preloadMessages(String chatKey) async {
    try {
      if ((_memCache[chatKey]?.isNotEmpty ?? false)) return;
      await loadMessages(chatKey);
    } catch (_) {}
  }

  /// Buang cache pesan IN-MEMORY saja (disk tetap) — dipanggil saat app
  /// di-background. Tiap entri menahan pesan + `imageData` base64 foto
  /// (bisa besar); melepasnya mencegah akumulasi → "ngetik ngelag setelah
  /// app lama". Saat dibuka lagi, chat dibaca ulang dari SQLite (cepat).
  void trimMemCache() {
    _memCache.clear();
    _memRawList.clear();
    _memRawObj.clear();
  }

  /// Hapus SEMUA cache (dipakai saat logout / reset).
  Future<void> clearAllLegacy() async {
    _memCache.clear();
    _memRawList.clear();
    _memRawObj.clear();
    try {
      await MessageStore.instance.clearAll();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    for (final prefix in [
      'chat_cache_v1_',
      'chat_cache_v2_',
      'chats_list_v1_',
      'obj_v1_',
    ]) {
      final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    }
  }

  Future<void> clearAll() => clearAllLegacy();

  /// Hapus HANYA cache format lama v1 â€” cache v2 aktif tetap utuh.
  /// Dipanggil saat app startup agar pesan cached tetap tersedia.
  Future<void> clearLegacyV1Only() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith('chat_cache_v1_'))
        .toList();
    for (final k in keys) await prefs.remove(k);
  }
}
