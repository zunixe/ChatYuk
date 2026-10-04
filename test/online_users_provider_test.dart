import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/providers/online_users_provider.dart';
import 'package:chatyuk/services/chat_service.dart';
import 'package:chatyuk/core/cache/message_cache.dart';

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

  setUp(() async {
    // Provider menyimpan daftar ke cache disk ('online_users') tiap emit —
    // tanpa dibersihkan, emit test SEBELUMNYA terbaca `_loadDisk` test
    // berikutnya dan mencemari assertion (ketahuan saat `_loadDisk` jadi
    // lebih cepat setelah avatar dipindah ke latar).
    await MessageCache.instance.removeRawObj('online_users');
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
    test('online di atas lalu idle; offline/invisible/basi dibuang', () async {
      await _emit([
        _u('off1', 'offline', seenMinAgo: 1),
        _u('inv1', 'invisible', seenMinAgo: 1),
        _u('basi1', 'online', seenMinAgo: 60),
        _u('idle1', 'idle', seenMinAgo: 5),
        _u('on1', 'online', seenMinAgo: 3),
        _u('on2', 'online', seenMinAgo: 1),
      ]);
      final uids = provider.users.map((u) => u.uid).toList();
      expect(uids, ['on2', 'on1', 'idle1']);
    });

    test('uid duplikat + uid kosong dibuang', () async {
      await _emit([_u('a', 'online'), _u('a', 'online'), _u('', 'online')]);
      expect(provider.users.map((u) => u.uid).toList(), ['a']);
    });

    test('baru online langsung ke atas; idle terlama paling bawah', () async {
      // Idle >30 mnt disaring (tak tampil) — pakai 25 mnt untuk yang lama.
      await _emit([
        _u('lama', 'online', seenMinAgo: 10),
        _u('idle-lama', 'idle', seenMinAgo: 25),
        _u('idle-baru', 'idle', seenMinAgo: 2),
      ]);
      expect(
        provider.users.map((u) => u.uid).toList(),
        ['lama', 'idle-baru', 'idle-lama'],
      );

      // Pendatang baru yang paling segar langsung ke puncak.
      await _emit([
        _u('lama', 'online', seenMinAgo: 10),
        _u('baru', 'online', seenMinAgo: 0),
        _u('idle-lama', 'idle', seenMinAgo: 25),
        _u('idle-baru', 'idle', seenMinAgo: 2),
      ]);
      expect(
        provider.users.map((u) => u.uid).toList(),
        ['baru', 'lama', 'idle-baru', 'idle-lama'],
      );
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
    test('online → offline/invisible hilang dari list', () async {
      await _emit([_u('a', 'online'), _u('b', 'online')]);
      await _emit([_u('a', 'offline'), _u('b', 'online')]);
      expect(
        provider.users.map((u) => u.uid).toList(),
        ['b'],
      );
      await _emit([_u('b', 'invisible'), _u('c', 'online')]);
      expect(
        provider.users.map((u) => u.uid).toList(),
        ['c'],
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

    test('grace 8 dtk tanpa emit isi → list basi dibersihkan', () async {
      await MessageCache.instance.removeRawObj('online_users');
      FakeAsync().run((fake) {
        final svc = MockChatService();
        final ctl = StreamController<List<UserModel>>.broadcast();
        when(() => svc.getOnlineUsers()).thenAnswer((_) => ctl.stream);
        final p = OnlineUsersProvider(service: svc);
        ctl.add([_u('a', 'online')]);
        fake.elapse(const Duration(milliseconds: 100));
        expect(p.users.map((u) => u.uid).toList(), ['a']);
        // Semua jadi invisible → stream emit kosong → grace menahan dulu.
        ctl.add([]);
        fake.elapse(const Duration(milliseconds: 100));
        expect(p.users.map((u) => u.uid).toList(), ['a']);
        // Timer habis tanpa emit isi → list dibersihkan, tidak nempel.
        fake.elapse(const Duration(seconds: 8));
        expect(p.users, isEmpty);
        p.dispose();
        ctl.close();
      });
    });
  });

  group('hold-grace per user (anti kedip idle)', () {
    test('idle hilang sekilas ditahan + kembali tanpa duplikat', () async {
      await MessageCache.instance.removeRawObj('online_users');
      await _emit([_u('a', 'online'), _u('idle1', 'idle')]);
      expect(provider.users.map((u) => u.uid).toSet(), {'a', 'idle1'});
      // Emission berikutnya tanpa idle1 (socket blip) → tetap tampil.
      await _emit([_u('a', 'online')]);
      expect(provider.users.map((u) => u.uid).toSet(), {'a', 'idle1'});
      // Kembali → tetap satu, tidak duplikat.
      await _emit([_u('a', 'online'), _u('idle1', 'idle')]);
      expect(
        provider.users.where((u) => u.uid == 'idle1').length,
        1,
      );
    });

    test('hold dilepas setelah 10 dtk tanpa kembali', () async {
      await MessageCache.instance.removeRawObj('online_users');
      FakeAsync().run((fake) {
        // FakeAsync tidak memalsukan DateTime.now → kendalikan jam hold
        // lewat seam holdNow (prinsip sama seperti jitterRandom).
        var now = DateTime(2026, 9, 17, 12, 0, 0);
        final prevClock = OnlineUsersProvider.holdNow;
        OnlineUsersProvider.holdNow = () => now;
        try {
          final svc = MockChatService();
          final ctl = StreamController<List<UserModel>>.broadcast();
          when(() => svc.getOnlineUsers()).thenAnswer((_) => ctl.stream);
          final p = OnlineUsersProvider(service: svc);
          ctl.add([_u('a', 'online'), _u('idle1', 'idle')]);
          fake.elapse(const Duration(milliseconds: 100));
          expect(p.users.map((u) => u.uid).toSet(), {'a', 'idle1'});
          ctl.add([_u('a', 'online')]);
          fake.elapse(const Duration(milliseconds: 100));
          expect(p.users.map((u) => u.uid).toSet(), {'a', 'idle1'});
          // Grace habis tanpa kabar → dilepas (tidak nempel selamanya).
          now = now.add(const Duration(seconds: 15));
          fake.elapse(const Duration(seconds: 15));
          expect(p.users.map((u) => u.uid).toList(), ['a']);
          p.dispose();
          ctl.close();
        } finally {
          OnlineUsersProvider.holdNow = prevClock;
        }
      });
    });
  });

  // Grup ini di AKHIR file: emission-nya menyimpan snapshot disk/memori
  // (`MessageCache._memRawList`) yang dibaca `_loadDisk` provider test
  // berikutnya — di akhir tidak ada test yang bisa tercemar.
  // Uid sengaja unik (hidA/hidB) + assertion pakai contains, supaya tahan
  // terhadap stale user dari test sebelumnya (hold-grace bisa menahannya).
  group('sembunyikan (benam ke kotak bawah)', () {
    test('hide/unhide update in-memory langsung', () async {
      expect(provider.isHidden('hidA'), isFalse);
      await provider.hideUser('hidA');
      expect(provider.isHidden('hidA'), isTrue);
      expect(provider.hiddenCount, 1);
      expect(provider.hiddenUids, contains('hidA'));
      await provider.unhideUser('hidA');
      expect(provider.isHidden('hidA'), isFalse);
      expect(provider.hiddenCount, 0);
    });

    test('uid hidden yang online lagi tetap hidden', () async {
      await _emit([_u('hidA', 'online'), _u('hidB', 'online')]);
      await provider.hideUser('hidB');
      expect(provider.isHidden('hidB'), isTrue);
      // Tetap dikenal walau emission datang lagi (screen mempartisi
      // ke kotak bawah, provider tidak membuangnya).
      await _emit([_u('hidA', 'online'), _u('hidB', 'online')]);
      expect(provider.isHidden('hidB'), isTrue);
      final uids = provider.users.map((u) => u.uid).toSet();
      expect(uids, containsAll(['hidA', 'hidB']));
      await provider.unhideUser('hidB');
      expect(provider.isHidden('hidB'), isFalse);
    });

    test('setOwner ganti akun mengosongkan daftar lama', () async {
      provider.setHiddenForTest({'hidX'});
      expect(provider.isHidden('hidX'), isTrue);
      await provider.setOwner('owner1');
      // Prefs mock kosong → daftar bersih, tidak bocor antar akun.
      expect(provider.isHidden('hidX'), isFalse);
    });
  });

  group('fetchUserCounts (header total user)', () {
    test('sukses → total registered + anon tersimpan & notify', () async {
      var notified = 0;
      provider.addListener(() => notified++);
      when(() => service.userCounts())
          .thenAnswer((_) async => (registered: 355, anon: 136));

      expect(provider.totalRegistered, isNull);
      expect(provider.totalAnon, isNull);

      await provider.fetchUserCounts();
      expect(provider.totalRegistered, 355);
      expect(provider.totalAnon, 136);
      expect(notified, 1);
    });

    test('di-cache: panggil kedua tidak memicu RPC lagi', () async {
      when(() => service.userCounts())
          .thenAnswer((_) async => (registered: 10, anon: 2));
      await provider.fetchUserCounts();
      await provider.fetchUserCounts();
      verify(() => service.userCounts()).called(1);
    });

    test('gagal (null) → tetap null, tidak crash', () async {
      when(() => service.userCounts()).thenAnswer((_) async => null);
      await provider.fetchUserCounts();
      expect(provider.totalRegistered, isNull);
      expect(provider.totalAnon, isNull);
    });
  });
}
