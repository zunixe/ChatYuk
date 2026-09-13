import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/utils/bounded_cache.dart';
import 'package:chatyuk/utils.dart' as utils;
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/widgets/date_chip.dart';

void main() {
  group('BoundedCache', () {
    test('evict tertua saat penuh (FIFO)', () {
      final c = BoundedCache<String, int>(3);
      c.putIfAbsent('a', () => 1);
      c.putIfAbsent('b', () => 2);
      c.putIfAbsent('c', () => 3);
      c.putIfAbsent('d', () => 4);
      expect(c.get('a'), isNull, reason: 'a harus ter-evict (tertua)');
      expect(c.get('b'), 2);
      expect(c.get('d'), 4);
    });

    test('get memperbarui urutan (entry baru dianggap terbaru)', () {
      final c = BoundedCache<String, int>(2);
      c.putIfAbsent('a', () => 1);
      c.putIfAbsent('b', () => 2);
      c.get('a'); // a jadi terbaru
      c.putIfAbsent('c', () => 3); // b yang ter-evict, bukan a
      expect(c.get('a'), 1);
      expect(c.get('b'), isNull);
      expect(c.get('c'), 3);
    });

    test('putIfAbsent existing tidak menghitung ulang', () {
      final c = BoundedCache<String, int>(2);
      var calls = 0;
      int factory() => ++calls;
      c.putIfAbsent('a', factory);
      c.putIfAbsent('a', factory);
      expect(c.get('a'), 1);
      expect(calls, 1);
    });

    test('clear mengosongkan semua', () {
      final c = BoundedCache<String, int>(2);
      c.putIfAbsent('a', () => 1);
      c.clear();
      expect(c.get('a'), isNull);
      c.putIfAbsent('b', () => 2);
      expect(c.get('b'), 2);
    });
  });

  group('snakeToCamel', () {
    test('konversi key snake_case ke camelCase, nilai tetap', () {
      final out = utils.snakeToCamel({
        'sender_id': 'u1',
        'is_registered': true,
        'created_at': '2026-01-01',
      });
      expect(out['senderId'], 'u1');
      expect(out['isRegistered'], true);
      expect(out['createdAt'], '2026-01-01');
      expect(out.containsKey('sender_id'), isFalse);
    });

    test('key tanpa underscore diteruskan apa adanya', () {
      final out = utils.snakeToCamel({'id': 5, 'text': 'halo'});
      expect(out['id'], 5);
      expect(out['text'], 'halo');
    });

    test('underscore berurutan tidak menghasilkan huruf kapital kosong', () {
      final out = utils.snakeToCamel({'a__b_c': 1});
      expect(out['aBC'], 1);
    });
  });

  group('formatBytes', () {
    test('B di bawah 1 KB', () {
      expect(utils.formatBytes(512), '512 B');
    });

    test('KB dua digit tanpa desimal (toStringAsFixed(0))', () {
      // 2048/1024 = 2.0 → toStringAsFixed(0) = '2' → interpolasi '2.0 KB'.
      expect(utils.formatBytes(2048), '2.0 KB');
    });

    test('KB satu digit pakai 1 desimal', () {
      expect(utils.formatBytes(1536), '1.5 KB');
    });

    test('MB', () {
      expect(utils.formatBytes(23 * 1024 * 1024), '23 MB');
    });

    test('GB dua desimal', () {
      expect(utils.formatBytes(1.25 * 1024 * 1024 * 1024), '1.25 GB');
    });
  });

  group('notifIdForKey', () {
    test('selalu non-negatif & deterministik', () {
      final a = utils.notifIdForKey('chat-abc');
      final b = utils.notifIdForKey('chat-abc');
      expect(a, b);
      expect(a, greaterThanOrEqualTo(0));
      expect(a, lessThanOrEqualTo(0x7FFFFFFF));
    });

    test('key beda → id beda (praktis)', () {
      expect(utils.notifIdForKey('a'), isNot(utils.notifIdForKey('b')));
    });
  });

  group('formatRelativeTime', () {
    test('kurang dari 1 menit → Baru/Now', () {
      final now = DateTime.now();
      expect(utils.formatRelativeTime(now.subtract(const Duration(seconds: 10)), isId: true), 'Baru');
      expect(utils.formatRelativeTime(now.subtract(const Duration(seconds: 10))), 'Now');
    });

    test('menit & jam', () {
      final now = DateTime.now();
      expect(
        utils.formatRelativeTime(now.subtract(const Duration(minutes: 5))),
        '5m',
      );
      expect(
        utils.formatRelativeTime(now.subtract(const Duration(hours: 3))),
        '3h',
      );
    });

    test('hari di bawah seminggu', () {
      final now = DateTime.now();
      expect(
        utils.formatRelativeTime(now.subtract(const Duration(days: 2))),
        '2d',
      );
    });
  });

  group('dateChipLabel', () {
    test('hari ini & kemarin bilingual', () {
      final id = S(isId: true);
      final en = S(isId: false);
      final now = DateTime.now();
      expect(dateChipLabel(now, id), id.labelToday);
      expect(dateChipLabel(now, en), en.labelToday);
      final kemarin = now.subtract(const Duration(days: 1));
      expect(dateChipLabel(kemarin, id), id.labelYesterday);
      expect(dateChipLabel(kemarin, en), en.labelYesterday);
    });

    test('tanggal lama format lengkap, bukan label relatif', () {
      final id = S(isId: true);
      final lama = DateTime.now().subtract(const Duration(days: 10));
      final label = dateChipLabel(lama, id);
      expect(label, isNot(id.labelToday));
      expect(label, isNot(id.labelYesterday));
      expect(label.isNotEmpty, isTrue);
    });
  });

  group('ChatItem', () {
    test('message vs date mutually exclusive', () {
      final m = ChatItem.message(_dummyMsg());
      expect(m.msg, isNotNull);
      expect(m.dateLabel, isNull);
      const d = ChatItem.date('Hari ini');      expect(d.msg, isNull);
      expect(d.dateLabel, 'Hari ini');
    });
  });
}

MessageModel _dummyMsg() => MessageModel(
      id: 'x',
      senderId: 'u',
      senderName: 'A',
      senderGender: 'male',
      isRegistered: true,
      text: 't',
      type: 'text',
      imageData: '',
      timestamp: DateTime.now(),
    );
