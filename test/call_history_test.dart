import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/call/call_history_entry.dart';

/// Mengunci klasifikasi arah & outcome baris riwayat panggilan
/// ("Panggilan Terbaru", 2026-09-29).
///
/// Murni tanpa plugin: memastikan panggilan tak terjawab tidak salah
/// tampil sebagai terjawab, dan arah masuk/keluar konsisten dengan siapa
/// yang menelepon.
void main() {
  const me = 'me-uid';
  const other = 'other-uid';

  Map<String, dynamic> row({
    required String caller,
    required String callee,
    required String status,
    String type = 'audio',
    String? created,
    String? answered,
    String? ended,
  }) => {
    'id': 'c1',
    'caller_id': caller,
    'callee_id': callee,
    'call_type': type,
    'status': status,
    'created_at': created ?? '2026-09-29T11:00:00Z',
    'answered_at': answered,
    'ended_at': ended,
  };

  group('CallHistoryEntry.fromRow — arah & lawan bicara', () {
    test('saya menelepon → outgoing, lawan = callee', () {
      final e = CallHistoryEntry.fromRow(
        row(caller: me, callee: other, status: 'ended'),
        me,
      )!;
      expect(e.isOutgoing, isTrue);
      expect(e.otherUid, other);
    });

    test('saya menerima → incoming, lawan = caller', () {
      final e = CallHistoryEntry.fromRow(
        row(caller: other, callee: me, status: 'ended'),
        me,
      )!;
      expect(e.isOutgoing, isFalse);
      expect(e.otherUid, other);
    });

    test('baris tanpa partisipan valid → null', () {
      expect(CallHistoryEntry.fromRow({'caller_id': me}, me), isNull);
    });

    test('baris di mana saya satu-satunya pihak → null', () {
      expect(
        CallHistoryEntry.fromRow(
          row(caller: me, callee: me, status: 'ended'),
          me,
        ),
        isNull,
      );
    });
  });

  group('classifyOutcome', () {
    test('ended + terjawab → completed', () {
      expect(
        CallHistoryEntry.classifyOutcome(
          status: 'ended',
          isOutgoing: true,
          answered: true,
        ),
        CallOutcome.completed,
      );
    });

    test('ended tanpa diangkat, saya penelepon → canceled', () {
      expect(
        CallHistoryEntry.classifyOutcome(
          status: 'ended',
          isOutgoing: true,
          answered: false,
        ),
        CallOutcome.canceled,
      );
    });

    test('ended tanpa diangkat, saya penerima → missed', () {
      expect(
        CallHistoryEntry.classifyOutcome(
          status: 'ended',
          isOutgoing: false,
          answered: false,
        ),
        CallOutcome.missed,
      );
    });

    test('status missed selalu missed (dua arah)', () {
      for (final out in [true, false]) {
        expect(
          CallHistoryEntry.classifyOutcome(
            status: 'missed',
            isOutgoing: out,
            answered: false,
          ),
          CallOutcome.missed,
        );
      }
    });

    test('declined → declined; busy → busy', () {
      expect(
        CallHistoryEntry.classifyOutcome(
          status: 'declined',
          isOutgoing: false,
          answered: false,
        ),
        CallOutcome.declined,
      );
      expect(
        CallHistoryEntry.classifyOutcome(
          status: 'busy',
          isOutgoing: true,
          answered: false,
        ),
        CallOutcome.busy,
      );
    });

    test('ringing/answered → ongoing', () {
      expect(
        CallHistoryEntry.classifyOutcome(
          status: 'ringing',
          isOutgoing: true,
          answered: false,
        ),
        CallOutcome.ongoing,
      );
      expect(
        CallHistoryEntry.classifyOutcome(
          status: 'answered',
          isOutgoing: true,
          answered: true,
        ),
        CallOutcome.ongoing,
      );
    });
  });

  group('durasi & penanda missed-incoming', () {
    test('durasi = ended − answered (detik)', () {
      final e = CallHistoryEntry.fromRow(
        row(
          caller: me,
          callee: other,
          status: 'ended',
          answered: '2026-09-29T11:00:05Z',
          ended: '2026-09-29T11:01:05Z',
        ),
        me,
      )!;
      expect(e.durationSec, 60);
      expect(e.hasDuration, isTrue);
    });

    test('tanpa answered → durasi 0', () {
      final e = CallHistoryEntry.fromRow(
        row(caller: other, callee: me, status: 'missed'),
        me,
      )!;
      expect(e.durationSec, 0);
      expect(e.hasDuration, isFalse);
    });

    test('isMissedIncoming: masuk tak terjawab → true; keluar → false', () {
      final incoming = CallHistoryEntry.fromRow(
        row(caller: other, callee: me, status: 'missed'),
        me,
      )!;
      final outgoing = CallHistoryEntry.fromRow(
        row(caller: me, callee: other, status: 'ended'),
        me,
      )!;
      expect(incoming.isMissedIncoming, isTrue);
      expect(outgoing.isMissedIncoming, isFalse);
    });
  });

  group('call_type video', () {
    test('video call → isVideo true', () {
      final e = CallHistoryEntry.fromRow(
        row(caller: me, callee: other, status: 'ended', type: 'video'),
        me,
      )!;
      expect(e.isVideo, isTrue);
    });
  });
}
