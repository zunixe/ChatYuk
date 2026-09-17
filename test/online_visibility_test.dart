import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/chat_service.dart';

Map<String, dynamic> _row(String id, String status) => {
      'id': id,
      'status': status,
      'nickname': 'N$id',
    };

void main() {
  group('shouldDropOnlineUid', () {
    test('offline + invisible langsung drop', () {
      expect(ChatService.shouldDropOnlineUid('offline'), isTrue);
      expect(ChatService.shouldDropOnlineUid('invisible'), isTrue);
    });

    test('online/idle/null/status lain tidak drop', () {
      expect(ChatService.shouldDropOnlineUid('online'), isFalse);
      expect(ChatService.shouldDropOnlineUid('idle'), isFalse);
      expect(ChatService.shouldDropOnlineUid(null), isFalse);
      expect(ChatService.shouldDropOnlineUid('busy'), isFalse);
    });
  });

  group('filterRpcOnlineRows', () {
    test('idle tanpa presence dibuang (zombie app di-kill)', () {
      final rows = ChatService.filterRpcOnlineRows(
        [_row('zombie', 'idle'), _row('hidup', 'idle')],
        {'hidup'},
      );
      expect(rows.map((r) => (r as Map)['id']).toList(), ['hidup']);
    });

    test('online tanpa presence tetap tampil (baru connect)', () {
      final rows = ChatService.filterRpcOnlineRows(
        [_row('baru', 'online')],
        <String>{},
      );
      expect(rows.map((r) => (r as Map)['id']).toList(), ['baru']);
    });

    test('dummy online dari cron tanpa presence tetap tampil', () {
      final rows = ChatService.filterRpcOnlineRows(
        [_row('dummy1', 'online'), _row('dummy2', 'online')],
        {'userAsli'},
      );
      final ids = rows.map((r) => (r as Map)['id']).toSet();
      expect(ids, containsAll(['dummy1', 'dummy2']));
    });

    test('offline tanpa presence dibuang', () {
      final rows = ChatService.filterRpcOnlineRows(
        [_row('pergi', 'offline'), _row('on', 'online')],
        <String>{},
      );
      expect(rows.map((r) => (r as Map)['id']).toList(), ['on']);
    });

    test('semua terfilter → fallback RPC asli (cold start)', () {
      final rpc = [_row('a', 'idle'), _row('b', 'idle')];
      final rows = ChatService.filterRpcOnlineRows(rpc, <String>{});
      expect(identical(rows, rpc), isTrue);
    });

    test('dummy idle tanpa presence tetap tampil', () {
      final rows = ChatService.filterRpcOnlineRows(
        [_row('sarah', 'idle'), _row('zombie', 'idle')],
        <String>{},
        dummyUids: {'sarah'},
      );
      expect(rows.map((r) => (r as Map)['id']).toList(), ['sarah']);
    });

    test('guest idle tanpa presence tetap dibuang (bukan dummy)', () {
      // is_registered=false saja tidak cukup — 73 guest non-dummy juga
      // false. Hanya UID di dummy_accounts yang lolos jalur dummy.
      final rows = ChatService.filterRpcOnlineRows(
        [_row('guest1', 'idle'), _row('sarah', 'idle')],
        <String>{},
        dummyUids: {'sarah'},
      );
      expect(rows.map((r) => (r as Map)['id']).toList(), ['sarah']);
    });

    test('campuran: presence menang, online lolos, idle zombie gugur', () {
      final rows = ChatService.filterRpcOnlineRows(
        [
          _row('p1', 'idle'),
          _row('p2', 'online'),
          _row('baru', 'online'),
          _row('zombie', 'idle'),
          _row('off', 'offline'),
        ],
        {'p1', 'p2'},
      );
      final ids = rows.map((r) => (r as Map)['id']).toSet();
      expect(ids, {'p1', 'p2', 'baru'});
    });
  });

  group('avatar cache (batas memori)', () {
    // Cache avatar statis lintas test → bersihkan key yang dipakai di sini.
    tearDown(() {
      for (final k in ChatService.avatarCacheKeys) {
        if (k.startsWith('avatars/cache-') || k.startsWith('cache-')) {
          ChatService.clearAvatarCacheForPath(k);
        }
      }
    });

    test('set uid → satu entri di path kanonik avatars/<uid>.jpg', () {
      final before = ChatService.avatarCacheKeys.length;
      ChatService.setAvatarCacheForUid('cache-1', 'B64');
      expect(ChatService.avatarCacheKeys, contains('avatars/cache-1.jpg'));
      expect(ChatService.avatarCacheKeys.length, before + 1);
    });

    test('clear per uid menghapus entri itu saja', () {
      ChatService.setAvatarCacheForUid('cache-2', 'B64');
      ChatService.setAvatarCacheForPath('cache-lain.jpg', 'B64');
      ChatService.clearAvatarCacheForUid('cache-2');
      final keys = ChatService.avatarCacheKeys;
      expect(keys, isNot(contains('avatars/cache-2.jpg')));
      expect(keys, contains('cache-lain.jpg'));
    });

    test('base64 kosong = hapus entri, bukan simpan string kosong', () {
      final before = ChatService.avatarCacheKeys.length;
      ChatService.setAvatarCacheForUid('cache-3', 'B64');
      ChatService.setAvatarCacheForUid('cache-3', '');
      expect(ChatService.avatarCacheKeys.length, before);

      ChatService.setAvatarCacheForPath('cache-3.jpg', 'B64');
      ChatService.setAvatarCacheForPath('cache-3.jpg', '');
      expect(ChatService.avatarCacheKeys.length, before);
    });

    test('path kosong diabaikan (tidak bikin entri "")', () {
      final before = ChatService.avatarCacheKeys.length;
      ChatService.setAvatarCacheForPath('', 'B64');
      expect(ChatService.avatarCacheKeys.length, before);
      expect(ChatService.avatarCacheKeys, isNot(contains('')));
    });

    test('cap 100: entri tertua ter-evict lebih dulu', () {
      for (var i = 0; i < 130; i++) {
        ChatService.setAvatarCacheForUid('cache-$i', 'B64');
      }
      final keys = ChatService.avatarCacheKeys;
      expect(keys.length, lessThanOrEqualTo(100),
          reason: 'cache tak boleh tumbuh tanpa batas');
      expect(keys, contains('avatars/cache-129.jpg'),
          reason: 'entri terbaru tetap ada');
      expect(keys, isNot(contains('avatars/cache-0.jpg')),
          reason: 'entri tertua yang ter-evict lebih dulu (FIFO)');
    });
  });
}
