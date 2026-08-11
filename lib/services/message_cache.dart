import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message_model.dart';

// Top-level function untuk compute() — encrypt + write di background isolate
Future<void> _encSave(Map<String, dynamic> args) async {
  final prefsKey = args['prefsKey'] as String;
  final plaintext = args['plaintext'] as String;
  final keyBytes = (args['keyBytes'] as List<dynamic>).cast<int>();
  final key = SecretKey(List<int>.from(keyBytes));
  final aes = AesGcm.with256bits();
  final iv = aes.newNonce();
  final secretBox = await aes.encrypt(
    utf8.encode(plaintext),
    secretKey: key,
    nonce: iv,
  );
  final payload = {
    'n': base64Encode(secretBox.nonce),
    'c': base64Encode(secretBox.cipherText),
    'm': base64Encode(secretBox.mac.bytes),
  };
  final enc = base64Encode(utf8.encode(jsonEncode(payload)));
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(prefsKey, enc);
}

// Top-level function untuk compute() — decrypt + parse di background isolate
// supaya buka chat tidak freeze saat mendekripsi cache besar.
Future<List<dynamic>?> _decLoad(Map<String, dynamic> args) async {
  try {
    final encoded = args['encoded'] as String;
    final keyBytes = (args['keyBytes'] as List<dynamic>).cast<int>();
    final key = SecretKey(List<int>.from(keyBytes));
    final aes = AesGcm.with256bits();
    final payload = jsonDecode(utf8.decode(base64Decode(encoded))) as Map<String, dynamic>;
    final box = SecretBox(
      base64Decode(payload['c'] as String),
      nonce: base64Decode(payload['n'] as String),
      mac: Mac(base64Decode(payload['m'] as String)),
    );
    final clear = await aes.decrypt(box, secretKey: key);
    final list = jsonDecode(utf8.decode(clear)) as List<dynamic>;
    return list;
  } catch (_) {
    return null;
  }
}

// Top-level function untuk compute() — decrypt string tunggal (foto) di background
Future<String?> _decStr(Map<String, dynamic> args) async {
  try {
    final encoded = args['encoded'] as String;
    final keyBytes = (args['keyBytes'] as List<dynamic>).cast<int>();
    final key = SecretKey(List<int>.from(keyBytes));
    final aes = AesGcm.with256bits();
    final payload = jsonDecode(utf8.decode(base64Decode(encoded))) as Map<String, dynamic>;
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
  // Dibatasi 30 chat — LRU sederhana, buang yang paling lama saat penuh.
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
      await _storage.write(key: keyId, value: base64Encode(await newKey.extractBytes()));
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
    final payload = jsonDecode(utf8.decode(base64Decode(encoded))) as Map<String, dynamic>;
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

  /// Dekripsi di background isolate — untuk PhotoCache supaya buka chat
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

  /// Simpan daftar pesan untuk sebuah chat (key = chatId/roomId).
  /// Kirim list kosong untuk menghapus cache chat tersebut.
  /// imageData di-strip (foto disimpan terpisah di PhotoCache) supaya
  /// cache pesan tetap kecil dan cepat dibaca.
  Future<void> saveMessages(String chatKey, List<MessageModel> messages) async {
    _memCacheUpdate(chatKey, messages);
    final prefs = await SharedPreferences.getInstance();
    if (messages.isEmpty) {
      await prefs.remove('$_keyPrefix$chatKey');
      return;
    }
    final key = await _getKey();
    final data = messages.map((m) => {...m.toMap(), 'imageData': ''}).toList();
    final plain = jsonEncode(data);
    final keyBytes = await key.extractBytes();
    await compute(_encSave, {
      'prefsKey': '$_keyPrefix$chatKey',
      'plaintext': plain,
      'keyBytes': keyBytes,
    });
  }

  /// Ambil pesan cache (null jika tidak ada).
  Future<List<MessageModel>> loadMessages(String chatKey) async {
    // Fast path: sudah pernah dibuka sesi ini — langsung pakai mem-cache
    // tanpa perlu decrypt sama sekali.
    final mem = _memCache[chatKey];
    if (mem != null) {
      _memCacheUpdate(chatKey, mem); // refresh urutan LRU
      return mem;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final enc = prefs.getString('$_keyPrefix$chatKey');
      if (enc == null || enc.isEmpty) return [];
      final key = await _getKey();
      final keyBytes = await key.extractBytes();
      // Decrypt + parse di isolate — jangan block UI saat cache besar.
      final list = await compute(_decLoad, {'encoded': enc, 'keyBytes': keyBytes});
      if (list == null) return [];
      final msgs = list
          .map((e) => MessageModel.fromMap('cached', Map<String, dynamic>.from(e as Map)))
          .toList();
      _memCacheUpdate(chatKey, msgs);
      return msgs;
    } catch (e) {
      // Cache corrupt / key mismatch — abaikan, tampilkan dari server.
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

  /// Hapus SEMUA cache versi lama & baru (dipanggil saat app start & logout).
  Future<void> clearAllLegacy() async {
    _memCache.clear();
    final prefs = await SharedPreferences.getInstance();
    for (final prefix in ['chat_cache_v1_', 'chat_cache_v2_']) {
      final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    }
  }

  Future<void> clearAll() => clearAllLegacy();
}
