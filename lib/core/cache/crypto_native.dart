import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Kripto AES-256-GCM cache pesan/foto.
///
/// Kunci disimpan di **Android Keystore** (non-exportable) lewat channel native
/// `com.chatyuk.chatyuk/crypto`. Di environment tanpa channel (unit test, PC),
/// otomatis FALLBACK ke implementasi Dart `package:cryptography` dengan kunci
/// di `flutter_secure_storage` (perilaku lama).
///
/// KOMPATIBILITAS: format payload IDENTIK (base64 JSON {n,c,m}) sehingga data
/// lama tetap terbaca. Migrasi kunci: kunci lama (dari secure-storage) diimpor
/// sekali ke Keystore (`ensureKey`), setelah itu tak ada lagi kunci plaintext
/// di Dart.
class CryptoNative {
  CryptoNative._();

  static const MethodChannel _ch = MethodChannel('com.chatyuk.chatyuk/crypto');

  static const _keyId = 'chatyuk_msg_key_v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static final _aes = AesGcm.with256bits();

  /// True bila channel native tersedia (di-cache setelah probe pertama).
  static bool? _available;

  @visibleForTesting
  static void resetAvailabilityForTest() => _available = null;

  static Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    if (kIsWeb) {
      _available = false;
      return false;
    }
    try {
      await _ch.invokeMethod<bool>('hasKey');
      _available = true;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  // ── Kunci native (Keystore) ──────────────────────────────────
  static bool _nativeKeyReady = false;

  /// Pastikan Keystore punya kunci: impor kunci lama dari secure-storage
  /// (bila ada) supaya data lama tetap terbaca; kalau tidak ada, native
  /// membuat kunci baru. Idempoten.
  static Future<void> ensureNativeKey() async {
    if (_nativeKeyReady) return;
    final legacy = await _storage.read(key: _keyId) ?? '';
    await _ch.invokeMethod<bool>('importKey', {'key': legacy});
    _nativeKeyReady = true;
  }

  // ── Kunci fallback Dart (secure-storage) ─────────────────────
  static SecretKey? _dartKey;

  static Future<SecretKey> _loadDartKey() async {
    if (_dartKey != null) return _dartKey!;
    final existing = await _storage.read(key: _keyId);
    if (existing != null && existing.isNotEmpty) {
      _dartKey = SecretKey(base64Decode(existing));
    } else {
      final newKey = await _aes.newSecretKey();
      _dartKey = newKey;
      await _storage.write(
        key: _keyId,
        value: base64Encode(await newKey.extractBytes()),
      );
    }
    return _dartKey!;
  }

  // ── Encrypt/decrypt string ───────────────────────────────────
  /// Return base64 payload (format {n,c,m}) — IDENTIK di kedua jalur.
  static Future<String> encryptString(String plain) async {
    if (await isAvailable()) {
      try {
        await ensureNativeKey();
        final r = await _ch.invokeMethod<String>('encrypt', {'plain': plain});
        if (r != null && r.isNotEmpty) return r;
      } catch (_) {}
    }
    return _dartEncrypt(plain, await _loadDartKey());
  }

  static Future<String?> decryptString(String encoded) async {
    if (await isAvailable()) {
      try {
        await ensureNativeKey();
        final r = await _ch.invokeMethod<String>('decrypt', {'encoded': encoded});
        if (r != null) return r;
      } catch (_) {}
    }
    try {
      return await _dartDecrypt(encoded, await _loadDartKey());
    } catch (_) {
      return null;
    }
  }

  /// Baca file `.enc` + decrypt → plaintext. Native menghindari bytes masuk
  /// Dart; fallback baca di Dart.
  static Future<String?> decryptFile(String path) async {
    if (await isAvailable()) {
      try {
        await ensureNativeKey();
        final r = await _ch.invokeMethod<String>('decryptFile', {'path': path});
        if (r != null) return r;
      } catch (_) {}
    }
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return await _dartDecrypt(await f.readAsString(), await _loadDartKey());
    } catch (_) {
      return null;
    }
  }

  /// Decrypt BANYAK file sekaligus (Map<messageId, path>) → Map<messageId, b64>.
  static Future<Map<String, String>?> decryptFiles(
    Map<String, String> paths,
  ) async {
    if (paths.isEmpty) return {};
    if (await isAvailable()) {
      try {
        await ensureNativeKey();
        final r = await _ch.invokeMethod<Map<dynamic, dynamic>>(
          'decryptFiles',
          {'paths': paths},
        );
        if (r != null) return r.map((k, v) => MapEntry(k.toString(), v.toString()));
      } catch (_) {}
    }
    // Fallback: decrypt satu per satu.
    final key = await _loadDartKey();
    final out = <String, String>{};
    for (final e in paths.entries) {
      try {
        final f = File(e.value);
        if (!await f.exists()) continue;
        out[e.key] = await _dartDecrypt(await f.readAsString(), key);
      } catch (_) {}
    }
    return out;
  }

  /// Encrypt + tulis ke file `.enc` (native; fallback Dart).
  static Future<void> encryptToFile(String path, String plain) async {
    if (await isAvailable()) {
      try {
        await ensureNativeKey();
        final ok = await _ch.invokeMethod<bool>('encryptToFile', {
          'path': path,
          'plain': plain,
        });
        if (ok == true) return;
      } catch (_) {}
    }
    final enc = await _dartEncrypt(plain, await _loadDartKey());
    await File(path).writeAsString(enc, flush: true);
  }

  // ── Implementasi Dart (fallback) ─────────────────────────────
  static Future<String> _dartEncrypt(String plain, SecretKey key) async {
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

  static Future<String> _dartDecrypt(String encoded, SecretKey key) async {
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

  /// Untuk test: paksa jalur Dart (lewati native).
  @visibleForTesting
  static Future<String> dartEncryptForTest(String plain) async =>
      _dartEncrypt(plain, await _loadDartKey());

  @visibleForTesting
  static Future<String?> dartDecryptForTest(String encoded) async {
    try {
      return await _dartDecrypt(encoded, await _loadDartKey());
    } catch (_) {
      return null;
    }
  }
}
