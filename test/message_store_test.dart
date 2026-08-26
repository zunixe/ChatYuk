import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/services/message_store.dart';

MessageModel _msg(String id, DateTime ts, {String text = 'halo'}) =>
    MessageModel(
      id: id,
      senderId: 'uid-1',
      senderName: 'Andi',
      senderGender: 'male',
      isRegistered: true,
      text: text,
      type: 'text',
      imageData: '',
      timestamp: ts,
    );

void main() {
  // Native assets kadang tidak ter-link saat flutter test di Windows →
  // preload dll secara manual; lookup simbol @Native berikutnya menemukan
  // modul yang sudah termuat di proses.
  final localDll = File('build/native_assets/windows/sqlite3.dll');
  if (Platform.isWindows && localDll.existsSync()) {
    DynamicLibrary.open(localDll.absolute.path);
  }
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    // Folder unik per run supaya test selalu mulai dari DB kosong.
    final dir = await Directory.systemTemp.createTemp('msgstore_test');
    MessageStore.debugDir = dir.path;
    MessageStore.debugOpener = (path) => databaseFactory.openDatabase(path);
    await MessageStore.instance.open('test');
  });

  tearDown(() async {
    await MessageStore.instance.clearAll();
  });

  test('roundtrip: save → load, urutan ASC & field utuh', () async {
    final base = DateTime(2026, 8, 26, 10);
    final msgs = [
      _msg('a', base),
      _msg('b', base.add(const Duration(seconds: 1))),
      _msg('c', base.add(const Duration(seconds: 2))),
    ];
    await MessageStore.instance.saveMessages('chat-1', msgs);
    final loaded = await MessageStore.instance.loadMessages('chat-1');
    expect(loaded.map((m) => m.id).toList(), ['a', 'b', 'c']);
    expect(loaded.first.senderId, 'uid-1');
    expect(loaded.last.text, 'halo');
  });

  test('loadMessages limit mengambil window TERBARU (bukan terlama)', () async {
    final base = DateTime(2026, 8, 26, 10);
    final msgs = List.generate(
      150,
      (i) => _msg('m$i', base.add(Duration(seconds: i))),
    );
    await MessageStore.instance.saveMessages('chat-2', msgs);
    final loaded = await MessageStore.instance.loadMessages('chat-2');
    expect(loaded.length, 100);
    // Window terbaru → pesan pertama yang tampil adalah m50..m149
    expect(loaded.first.id, 'm50');
    expect(loaded.last.id, 'm149');
  });

  test('saveMessages trim ke 500 terbaru per chat', () async {
    final base = DateTime(2026, 8, 26);
    final msgs = List.generate(
      600,
      (i) => _msg('t$i', base.add(Duration(minutes: i))),
    );
    await MessageStore.instance.saveMessages('chat-3', msgs);
    final loaded =
        await MessageStore.instance.loadMessages('chat-3', limit: 500);
    expect(loaded.length, 500);
    expect(loaded.first.id, 't100');
    expect(loaded.last.id, 't599');
  });

  test('replace-all: simpan ulang menimpa isi lama', () async {
    final base = DateTime(2026, 8, 26);
    await MessageStore.instance
        .saveMessages('chat-4', [_msg('x1', base), _msg('x2', base)]);
    await MessageStore.instance.saveMessages('chat-4', [
      _msg('y1', base),
      _msg('y2', base),
      _msg('y3', base),
    ]);
    final loaded = await MessageStore.instance.loadMessages('chat-4');
    expect(loaded.map((m) => m.id).toList(), ['y1', 'y2', 'y3']);
  });

  test('clearAll mengosongkan semua chat', () async {
    final base = DateTime(2026, 8, 26);
    await MessageStore.instance.saveMessages('chat-5', [_msg('z1', base)]);
    await MessageStore.instance.clearAll();
    final loaded = await MessageStore.instance.loadMessages('chat-5');
    expect(loaded, isEmpty);
  });

  test('kv: roundtrip objek + replace + remove', () async {
    await MessageStore.instance.saveKv('timeline_all', '{"posts":[1,2]}');
    expect(await MessageStore.instance.loadKv('timeline_all'),
        '{"posts":[1,2]}');
    await MessageStore.instance
        .saveKv('timeline_all', '{"posts":[3],"cursor":"x"}');
    expect(await MessageStore.instance.loadKv('timeline_all'),
        '{"posts":[3],"cursor":"x"}');
    await MessageStore.instance.removeKv('timeline_all');
    expect(await MessageStore.instance.loadKv('timeline_all'), isNull);
  });

  test('clearAll juga mengosongkan kv (logout)', () async {
    await MessageStore.instance.saveKv('rooms_ID', '{"rooms":[]}');
    await MessageStore.instance.clearAll();
    expect(await MessageStore.instance.loadKv('rooms_ID'), isNull);
  });
}
