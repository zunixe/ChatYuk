import 'dart:convert';
import 'dart:async';
import 'dart:io';

import '../utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../models/message_model.dart';

/// Penyimpanan pesan lokal berbasis SQLite terenkripsi (SQLCipher).
///
/// Pola WhatsApp: DB hanya menyimpan teks + metadata pesan (satu baris JSON
/// per pesan); foto tetap di PhotoCache sebagai file terenkripsi terpisah.
///
/// Passphrase = base64 dari kunci AES yang sama dengan cache lama
/// (secure storage `chatyuk_msg_key_v1`) — paritas keamanan setara.
///
/// ponytail: desktop butuh databaseFactoryFfi saat runtime; target rilis
/// Android-only. Upgrade path: init sqfliteFfi di bootstrap desktop.
class MessageStore {
  MessageStore._();
  static final MessageStore instance = MessageStore._();

  /// Di-inject test (sqlite polos tanpa enkripsi via ffi). Null = produksi.
  static Future<Database> Function(String path)? debugOpener;

  /// Override lokasi folder DB untuk test (path_provider tidak tersedia).
  static String? debugDir;

  Database? _db;
  Completer<Database>? _opening;

  static const _table = 'messages';
  static const _trimPerChat = 500;

  bool get isOpen => _db != null && _db!.isOpen;

  /// Buka DB (idempoten; panggilan bersamaan menunggu pembukaan yang sama).
  Future<Database> open(String password) async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    final pending = _opening;
    if (pending != null) return pending.future;
    final completer = Completer<Database>();
    _opening = completer;
    try {
      final dirPath = debugDir ??
          (await getApplicationDocumentsDirectory()).path;
      final path = '$dirPath/chatyuk_messages_v1.db';
      Database db;
      try {
        db = debugOpener != null
            ? await debugOpener!(path)
            : await openDatabase(path, password: password);
      } catch (e) {
        // SELF-HEAL: DB tak bisa dibuka (kunci SQLCipher berubah / file
        // korup → "file is not a database", code 26). Dulu hanya rethrow →
        // cache pesan MATI sepanjang sesi (tiap buka chat selalu fetch
        // server = terasa loading). Kini hapus DB lama & buat ulang bersih.
        dlog('[STORE] open gagal ($e) → recreate DB bersih');
        // deleteDatabase saja kadang tak cukup (file masih ke-lock / handle
        // error) → hapus file mentah + wal/shm manual, baru buka ulang.
        try {
          await deleteDatabase(path);
        } catch (_) {}
        try {
          for (final suffix in ['', '-wal', '-shm', '-journal']) {
            final f = File('$path$suffix');
            if (f.existsSync()) f.deleteSync();
          }
        } catch (e2) {
          dlog('[STORE] hapus file DB manual error: $e2');
        }
        db = debugOpener != null
            ? await debugOpener!(path)
            : await openDatabase(path, password: password);
      }
      // DDL idempoten di sini (bukan onCreate) agar jalur produksi & test
      // memakai definisi skema yang sama persis.
      await db.execute(
        'CREATE TABLE IF NOT EXISTS $_table('
        'id TEXT PRIMARY KEY, '
        'chat_key TEXT NOT NULL, '
        'ts INTEGER NOT NULL, '
        'json TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_chat_ts ON $_table(chat_key, ts DESC)',
      );
      await db.execute(
        'CREATE TABLE IF NOT EXISTS kv('
        'key TEXT PRIMARY KEY, '
        'json TEXT NOT NULL)',
      );
      _db = db;
      completer.complete(db);
      return db;
    } catch (e, st) {
      _opening = null;
      completer.completeError(e, st);
      rethrow;
    }
  }

  /// Pesan ASC (terlama → terbaru), window [limit] TERBARU.
  ///
  /// [before] = kursor paging: kembalikan [limit] pesan TERAKHIR yang
  /// `ts`-nya LEBIH LAMA dari [before] (buka riwayat chat yang lebih lama).
  /// Menggunakan idx_chat_ts(chat_key, ts DESC) supaya query tetap cepat.
  Future<List<MessageModel>> loadMessages(
    String chatKey, {
    int limit = 100,
    DateTime? before,
  }) async {
    final db = _db;
    if (db == null || !db.isOpen) return const [];
    try {
      final List<Map<String, Object?>> rows;
      if (before == null) {
        rows = await db.query(
          _table,
          columns: ['id', 'json'],
          where: 'chat_key = ?',
          whereArgs: [chatKey],
          orderBy: 'ts DESC, rowid DESC',
          limit: limit,
        );
      } else {
        rows = await db.query(
          _table,
          columns: ['id', 'json'],
          where: 'chat_key = ? AND ts < ?',
          whereArgs: [chatKey, before.millisecondsSinceEpoch],
          orderBy: 'ts DESC, rowid DESC',
          limit: limit,
        );
      }
      return rows.reversed.map((r) {
        final map = jsonDecode(r['json'] as String) as Map<String, dynamic>;
        return MessageModel.fromMap('${r['id']}', map);
      }).toList();
    } catch (e) {
      dlog('[STORE] load $chatKey error: $e');
      return const [];
    }
  }

  /// Upsert incremental [messages] (urut ASC) untuk [chatKey].
  ///
  /// Hanya menulis baris yang ID-nya baru atau JSON-nya berubah (diff hash
  /// di memori) — tidak lagi DELETE+reinsert seluruh chat tiap ~2s. Baris
  /// lama yang tersisa di atas [_trimPerChat] dipangkas di akhir transaksi.
  ///
  /// JANGAN diandalkan untuk menghapus pesan (delete/edit pesan = baris
  /// ber-`isDeleted`/`edited` ter-update via JSON). Hapus permanen → [clearChat].
  Future<void> saveMessages(
    String chatKey,
    List<MessageModel> messages,
  ) async {
    final db = _db;
    if (db == null || !db.isOpen) return;
    var list = messages;
    if (list.length > _trimPerChat) {
      list = list.sublist(list.length - _trimPerChat);
    }
    try {
      final rows = await db.query(
        _table,
        columns: ['id', 'json'],
        where: 'chat_key = ?',
        whereArgs: [chatKey],
        orderBy: 'ts DESC, rowid DESC',
      );
      final existingJson = {
        for (final r in rows) '${r['id']}': '${r['json']}',
      };
      await db.transaction((txn) async {
        final batch = txn.batch();
        final incomingIds = <String>{};
        for (final m in list) {
          incomingIds.add(m.id);
          final json = jsonEncode(m.toMap());
          // Skip kalau isi sama persis — hemat tulis saat burst realtime
          // (tiap pesan masuk memicu save ulang seluruh window).
          if (existingJson[m.id] == json) continue;
          batch.insert(
            _table,
            {
              'id': m.id,
              'chat_key': chatKey,
              'ts': m.timestamp.millisecondsSinceEpoch,
              'json': json,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        // Sisa baris di luar window terbaru dibuang biar tabel tidak membesar.
        // Trim berbasis ID (kontrak "replace-all": window baru menggantikan
        // yang lama walau timestamp sama): hitung delta di Dart dari hasil
        // query di atas, hapus per id dengan IN yang di-chunk 400 agar aman
        // dari batas 999 variabel SQLite. Plus potong ts tua sebagai jaring
        // pengaman.
        final staleIds = existingJson.keys
            .where((id) => !incomingIds.contains(id))
            .toList();
        for (var i = 0; i < staleIds.length; i += 400) {
          final chunk = staleIds.skip(i).take(400).toList();
          batch.delete(
            _table,
            where: 'chat_key = ? AND id IN '
                '(${List.filled(chunk.length, '?').join(',')})',
            whereArgs: [chatKey, ...chunk],
          );
        }
        if (list.isNotEmpty) {
          final cutoff = list.first.timestamp.millisecondsSinceEpoch;
          batch.delete(
            _table,
            where: 'chat_key = ? AND ts < ?',
            whereArgs: [chatKey, cutoff],
          );
        }
        await batch.commit(noResult: true);
      });
    } catch (e) {
      dlog('[STORE] save $chatKey error: $e');
    }
  }

  Future<void> clearChat(String chatKey) async {
    final db = _db;
    if (db == null || !db.isOpen) return;
    try {
      await db.delete(_table, where: 'chat_key = ?', whereArgs: [chatKey]);
    } catch (e) {
      dlog('[STORE] clear $chatKey error: $e');
    }
  }

  Future<void> clearAll() async {
    final db = _db;
    if (db == null || !db.isOpen) return;
    try {
      await db.delete(_table);
      await db.delete('kv');
    } catch (e) {
      dlog('[STORE] clearAll error: $e');
    }
  }

  /// Tutup DB & reset state (dipakai test / switch akun). open() berikutnya
  /// membuka ulang dari disk.
  Future<void> close() async {
    final db = _db;
    _db = null;
    _opening = null;
    if (db != null && db.isOpen) {
      try {
        await db.close();
      } catch (e) {
        dlog('[STORE] close error: $e');
      }
    }
  }

  // ── KV generik: timeline, list room, list chat, dsb ───────────────────────

  /// Simpan objek JSON di bawah [key]. [json] harus hasil jsonEncode.
  Future<void> saveKv(String key, String json) async {
    final db = _db;
    if (db == null || !db.isOpen) return;
    try {
      await db.insert(
        'kv',
        {'key': key, 'json': json},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      dlog('[STORE] kv save $key error: $e');
    }
  }

  Future<String?> loadKv(String key) async {
    final db = _db;
    if (db == null || !db.isOpen) return null;
    try {
      final rows = await db.query(
        'kv',
        columns: ['json'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['json'] as String?;
    } catch (e) {
      dlog('[STORE] kv load $key error: $e');
      return null;
    }
  }

  Future<void> removeKv(String key) async {
    final db = _db;
    if (db == null || !db.isOpen) return;
    try {
      await db.delete('kv', where: 'key = ?', whereArgs: [key]);
    } catch (e) {
      dlog('[STORE] kv remove $key error: $e');
    }
  }

  /// Hapus SEMUA baris kv tanpa menyentuh pesan.
  Future<void> clearKv() async {
    final db = _db;
    if (db == null || !db.isOpen) return;
    try {
      await db.delete('kv');
    } catch (e) {
      dlog('[STORE] clearKv error: $e');
    }
  }
}
