import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/gifts.dart';
import 'package:chatyuk/models/active_call_model.dart';
import 'package:chatyuk/models/legal_section.dart';
import 'package:chatyuk/models/user_photo.dart';

void main() {
  group('ActiveCallInfo', () {
    test('fromJson memetakan semua kolom snake_case', () {
      final c = ActiveCallInfo.fromJson({
        'id': 'call-1',
        'chat_id': 'c1_c2',
        'caller_id': 'u1',
        'callee_id': 'u2',
        'caller_name': 'Budi',
        'callee_name': 'Sari',
        'call_type': 'audio',
        'status': 'answered',
        'created_at': '2026-05-04T03:00:00Z',
        'answered_at': '2026-05-04T03:00:10Z',
      });
      expect(c.id, 'call-1');
      expect(c.chatId, 'c1_c2');
      expect(c.callerId, 'u1');
      expect(c.calleeId, 'u2');
      expect(c.callerName, 'Budi');
      expect(c.calleeName, 'Sari');
      expect(c.callType, 'audio');
      expect(c.status, 'answered');
      expect(c.answeredAt, isNotNull);
    });

    test('fromJson default saat kolom hilang', () {
      final c = ActiveCallInfo.fromJson({});
      expect(c.id, '');
      expect(c.callerName, 'Unknown');
      expect(c.calleeName, 'Unknown');
      expect(c.callType, 'video');
      expect(c.status, 'ringing');
      expect(c.answeredAt, isNull);
    });

    test('elapsedSeconds pakai answered_at bila ada', () {
      final c = ActiveCallInfo(
        id: 'x',
        chatId: 'x',
        callerId: 'a',
        calleeId: 'b',
        callerName: 'A',
        calleeName: 'B',
        callType: 'video',
        status: 'answered',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        answeredAt: DateTime.now().subtract(const Duration(seconds: 30)),
      );
      expect(c.elapsedSeconds, greaterThanOrEqualTo(29));
      expect(c.elapsedSeconds, lessThan(35));
    });

    test('elapsedSeconds clamp negatif ke 0', () {
      final c = ActiveCallInfo(
        id: 'x',
        chatId: 'x',
        callerId: 'a',
        calleeId: 'b',
        callerName: 'A',
        calleeName: 'B',
        callType: 'video',
        status: 'ringing',
        createdAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      expect(c.elapsedSeconds, 0);
    });
  });

  group('UserPhoto.fromMap', () {
    test('memetakan + parse tanggal string', () {
      final p = UserPhoto.fromMap('p1', {
        'userId': 'u1',
        'photo': 'photos/a.jpg',
        'createdAt': '2026-05-04T03:00:00Z',
        'unlocked': false,
        'preview': 'base64prv',
      });
      expect(p.id, 'p1');
      expect(p.userId, 'u1');
      expect(p.photo, 'photos/a.jpg');
      expect(p.unlocked, isFalse);
      expect(p.preview, 'base64prv');
      expect(p.createdAt.year, 2026);
    });

    test('unlocked default true bila kolom absen', () {
      final p = UserPhoto.fromMap('p1', {});
      expect(p.unlocked, isTrue);
      expect(p.preview, '');
    });

    test('createdAt DateTime dipakai apa adanya', () {
      final d = DateTime(2026, 1, 1);
      final p = UserPhoto.fromMap('p1', {'createdAt': d});
      expect(p.createdAt, d);
    });
  });

  group('LegalSection / LegalItem', () {
    test('konstruksi dasar + default', () {
      const sec = LegalSection(
        chapter: 'Bab I',
        article: 'Pasal 1',
        items: [LegalItem('Teks', bullet: true)],
      );
      expect(sec.chapter, 'Bab I');
      expect(sec.article, 'Pasal 1');
      expect(sec.items.single.bullet, isTrue);
      expect(sec.items.single.table, isNull);
    });

    test('chapter/article opsional', () {
      const sec = LegalSection(items: []);
      expect(sec.chapter, isNull);
      expect(sec.article, isNull);
      expect(sec.items, isEmpty);
    });

    test('item dengan tabel', () {
      const it = LegalItem('baris', table: [
        ['a', 'b'],
      ]);
      expect(it.table!.length, 1);
      expect(it.table!.first, ['a', 'b']);
    });
  });

  group('giftById / kGiftCatalog', () {
    test('id ada → item benar', () {
      final g = giftById('rose');
      expect(g, isNotNull);
      expect(g!.emoji, '🌹');
      expect(g.coins, 10);
      expect(g.nameEn, 'Rose');
    });

    test('id tak dikenal → null', () {
      expect(giftById('tidak-ada'), isNull);
      expect(giftById(''), isNull);
    });

    test('katalog: id unik & harga positif', () {
      final ids = kGiftCatalog.map((g) => g.id).toSet();
      expect(ids.length, kGiftCatalog.length);
      for (final g in kGiftCatalog) {
        expect(g.coins, greaterThan(0), reason: g.id);
        expect(g.emoji, isNotEmpty);
        expect(g.nameId, isNotEmpty);
        expect(g.nameEn, isNotEmpty);
      }
    });

    test('semua id katalog bisa di-resolve', () {
      for (final g in kGiftCatalog) {
        expect(giftById(g.id)?.id, g.id);
      }
    });
  });
}
