import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
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
      final db = debugOpener != null
          ? await debugOpener!(path)
          : await openDatabase(path, password: password);
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
  Future<List<MessageModel>> loadMessages(
    String chatKey, {
    int limit = 100,
  }) async {
    final db = _db;
    if (db == null || !db.isOpen) return const [];
    try {
      final rows = await db.query(
        _table,
        columns: ['id', 'json'],
        where: 'chat_key = ?',
        whereArgs: [chatKey],
        orderBy: 'ts DESC, rowid DESC',
        limit: limit,
      );
      return rows.reversed.map((r) {
        final map = jsonDecode(r['json'] as String) as Map<String, dynamic>;
        return MessageModel.fromMap('${r['id']}', map);
      }).toList();
    } catch (e) {
      debugPrint('[STORE] load $chatKey error: $e');
      return const [];
    }
  }

  /// Ganti seluruh isi [chatKey] dengan [messages] (urut ASC) dalam satu
  /// transaction. Trim ke [_trimPerChat] terbaru.
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
      await db.transaction((txn) async {
        await txn.delete(_table, where: 'chat_key = ?', whereArgs: [chatKey]);
        final batch = txn.batch();
        for (final m in list) {
          batch.insert(
            _table,
            {
              'id': m.id,
              'chat_key': chatKey,
              'ts': m.timestamp.millisecondsSinceEpoch,
              'json': jsonEncode(m.toMap()),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } catch (e) {
      debugPrint('[STORE] save $chatKey error: $e');
    }
  }

  Future<void> clearChat(String chatKey) async {
    final db = _db;
    if (db == null || !db.isOpen) return;
    try {
      await db.delete(_table, where: 'chat_key = ?', whereArgs: [chatKey]);
    } catch (e) {
      debugPrint('[STORE] clear $chatKey error: $e');
    }
  }

  Future<void> clearAll() async {
    final db = _db;
    if (db == null || !db.isOpen) return;
    try {
      await db.delete(_table);
    } catch (e) {
      debugPrint('[STORE] clearAll error: $e');
    }
  }
}
