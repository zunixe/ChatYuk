import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/providers/online_users_provider.dart';
import 'package:chatyuk/services/chat_service.dart';

import 'test_helper.dart';

class MockChatService extends Mock implements ChatService {}

UserModel _u(
  String uid,
  String status, {
  int seenMinAgo = 1,
  String avatar = '',
}) =>
    UserModel(
      uid: uid,
      nickname: 'N$uid',
      gender: 'other',
      age: 20,
      country: 'ID',
      city: 'Jakarta',
      ipAddress: '',
      status: status,
      avatar: avatar,
      isRegistered: true,
      loginAt: DateTime.utc(2026, 1, 1),
      createdAt: DateTime.utc(2026, 1, 1),
      lastSeen:
          DateTime.now().toUtc().subtract(Duration(minutes: seenMinAgo)),
    );

void main() {
  late MockChatService service;
  late StreamController<List<UserModel>> stream;
  late OnlineUsersProvider provider;

  setUpAll(() async {
    await initSupabaseForTest();
  });

  setUp(() {
    service = MockChatService();
    stream = StreamController<List<UserModel>>.broadcast();
    when(() => service.getOnlineUsers()).thenAnswer((_) => stream.stream);
    provider = OnlineUsersProvider(service: service);
  });

  tearDown(() async {
    provider.dispose();
    await stream.close();
  });

  Future<void> _emit(List<UserModel> users) async {
    stream.add(users);
    await Future.delayed(const Duration(milliseconds: 100));
  }

  group('sortir + dedupe emission', () {
    test('online di atas, idle tengah, offline bawah; lastSeen desc per bucket',
        () async {
      await _emit([
        _u('off1', 'offline', seenMinAgo: 1),
        _u('idle1', 'idle', seenMinAgo: 5),
        _u('on1', 'online', seenMinAgo: 3),
        _u('on2', 'online', seenMinAgo: 1),
      ]);
      final uids = provider.users.map((u) => u.uid).toList();
      expect(uids, ['on2', 'on1', 'idle1', 'off1']);
    });

    test('uid duplikat + uid kosong dibuang', () async {
      await _emit([_u('a', 'online'), _u('a', 'online'), _u('', 'online')]);
      expect(provider.users.map((u) => u.uid).toList(), ['a']);
    });
  });

  group('merge avatar anti-kedip', () {
    test('avatar path baru tidak menimpa base64 lama', () async {
      await _emit([_u('a', 'online', avatar: 'BASE64LAMA')]);
      expect(provider.users.single.avatar, 'BASE64LAMA');
      // Fast-path berikutnya datang tanpa avatar (masih path storage).
      await _emit([_u('a', 'online', avatar: 'avatars/a.jpg')]);
      await Future.delayed(const Duration(milliseconds: 400));
      expect(provider.users.single.avatar, 'BASE64LAMA');
    });
  });

  group('pindah bucket + grace kosong', () {
    test('online → offline pindah ke bawah', () async {
      await _emit([_u('a', 'online'), _u('b', 'online')]);
      await _emit([_u('a', 'offline'), _u('b', 'online')]);
      expect(
        provider.users.map((u) => u.uid).toList(),
        ['b', 'a'],
      );
    });

    test('emit kosong saat list terisi ditahan (grace), emit isi membatalkan',
        () async {
      await _emit([_u('a', 'online')]);
      stream.add([]);
      await Future.delayed(const Duration(milliseconds: 100));
      // Grace 8 dtk: list lama tetap tampil.
      expect(provider.users.map((u) => u.uid).toList(), ['a']);
      // Emit berisi datang sebelum timer habis → grace batal.
      await _emit([_u('a', 'online'), _u('b', 'online')]);
      expect(provider.users.length, 2);
    });
  });
}
