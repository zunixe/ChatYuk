import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message_model.dart';
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
  static const _storage = FlutterSecureStorage();
  static final _aes = AesGcm.with256bits();

  // In-memory cache: sekali decrypt, buka ulang chat tidak perlu decrypt lagi.
  // Dibatasi 30 chat â€” LRU sederhana, buang yang paling lama saat penuh.
  final Map<String, List<MessageModel>> _memCache = {};
  static const _memCacheMax = 30;

  SecretKey? _key;

  Future<SecretKey>? _keyFuture;

  Future<SecretKey> _getKey() async {
    if (_key != null) return _key!;
    _keyFuture ??= _loadKey();
    return _keyFuture!;
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
  Future<void> saveMessages(String chatKey, List<MessageModel> messages) async {
    _memCacheUpdate(chatKey, messages);
    try {
      await _ensureDb();
      if (messages.isEmpty) {
        await MessageStore.instance.clearChat(chatKey);
      } else {
        await MessageStore.instance.saveMessages(
          chatKey,
          messages.map((m) {
            final map = m.toMap();
            map['imageData'] = '';
            return MessageModel.fromMap(m.id, map);
          }).toList(),
        );
      }
    } catch (e) {
      debugPrint('[MessageCache] saveMessages $chatKey ignored: $e');
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
    } catch (_) {}
  }

  // â”€â”€ List private chat / timeline / rooms (persist antar restart app) â”€â”€â”€â”€â”€
  // Semua blob generik kini di tabel `kv` SQLite terenkripsi â€” bukan lagi
  // prefs+AES. API tidak berubah supaya call site (timeline, room, chat
  // list) tidak perlu disentuh.

  Future<void> saveRawList(String key, List<Map<String, dynamic>> rows) async {
    try {
      if (rows.isEmpty) return;
      await _ensureDb();
      await MessageStore.instance.saveKv(key, jsonEncode(rows));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> loadRawList(String key) async {
    try {
      final json = await _loadKvSafe(key);
      if (json == null || json.isEmpty) return [];
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removeRawList(String key) async {
    try {
      await _ensureDb();
      await MessageStore.instance.removeKv(key);
    } catch (_) {}
  }

  // â”€â”€ Objek generic (timeline, rooms) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> saveRawObj(String key, Map<String, dynamic> obj) async {
    try {
      if (obj.isEmpty) return;
      await _ensureDb();
      await MessageStore.instance.saveKv(key, jsonEncode(obj));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> loadRawObj(String key) async {
    try {
      final json = await _loadKvSafe(key);
      if (json == null || json.isEmpty) return {};
      final obj = jsonDecode(json);
      return obj is Map<String, dynamic> ? obj : {};
    } catch (_) {
      return {};
    }
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
  Future<List<MessageModel>> loadMessages(String chatKey) async {
    // Fast path: sudah pernah dibuka sesi ini â€” langsung pakai mem-cache
    // tanpa perlu query DB sama sekali.
    final mem = _memCache[chatKey];
    if (mem != null) {
      _memCacheUpdate(chatKey, mem); // refresh urutan LRU
      return mem;
    }
    try {
      final sw = Stopwatch()..start();
      await _ensureDb();
      final msgs = await MessageStore.instance.loadMessages(chatKey);
      debugPrint(
        '[CACHE-TIME] $chatKey sqlite=${sw.elapsedMilliseconds}ms n=${msgs.length}',
      );
      _memCacheUpdate(chatKey, msgs);
      return msgs;
    } catch (e) {
      debugPrint('[MessageCache] loadMessages $chatKey error: $e');
      return [];
    }
  }

  // LRU sederhana: list kosong = hapus; saat penuh buang yang paling lama.
  void _memCacheUpdate(String chatKey, List<MessageModel> messages) {
    if (messages.isEmpty) {
      _memCache.remove(chatKey);
      return;
    }
    _memCache.remove(chatKey);
    _memCache[chatKey] = messages;
    while (_memCache.length > _memCacheMax) {
      _memCache.remove(_memCache.keys.first);
    }
  }

  /// Hapus SEMUA cache (dipakai saat logout / reset).
  Future<void> clearAllLegacy() async {
    _memCache.clear();
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
