import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/mixins/chat_photo_send_mixin.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/widgets/private_chat_message.dart';

/// Aturan durasi view-once (durationMs pesan):
/// null/negatif = legacy 10 dtk, 0 = sampai ditutup (1x), N = N detik.
void main() {
  group('resolveViewOnceSecs', () {
    test('null → 10 (legacy)', () => expect(resolveViewOnceSecs(null), 10));
    test('negatif → 10', () {
      expect(resolveViewOnceSecs(-1), 10);
      expect(resolveViewOnceSecs(-99), 10);
    });
    test('0 → 0 (1x sampai ditutup)', () {
      expect(resolveViewOnceSecs(0), 0);
    });
    test('N → N detik', () {
      expect(resolveViewOnceSecs(3), 3);
      expect(resolveViewOnceSecs(10), 10);
    });
  });

  group('resolvePhotoSendKind (satu dispatch, routing benar)', () {
    test('tanpa timer → kind asal', () {
      expect(resolvePhotoSendKind('image', null), 'image');
      expect(resolvePhotoSendKind('view_once', null), 'view_once');
    });
    test('timer 0/3/10 → view_once', () {
      for (final t in [0, 3, 10]) {
        expect(resolvePhotoSendKind('image', t), 'view_once');
      }
    });
    test('gallery view-once tanpa timer tetap view_once', () {
      expect(resolvePhotoSendKind('view_once', null), 'view_once');
    });
  });

  group('transit durasi sender→receiver (tidak boleh hilang)', () {
    test('payload broadcast duration_ms=3 → durationMs 3', () {
      final m = MessageModel.fromMap('bc-1', {
        'type': 'view_once',
        'duration_ms': 3,
      });
      expect(m.durationMs, 3);
      expect(resolveViewOnceSecs(m.durationMs), 3);
    });
    test('row realtime duration_ms=0 → mode 1x', () {
      final m = MessageModel.fromMap('123', {
        'type': 'view_once',
        'duration_ms': 0,
      });
      expect(m.durationMs, 0);
      expect(resolveViewOnceSecs(m.durationMs), 0);
    });
    test('tanpa duration → null (legacy 10)', () {
      final m = MessageModel.fromMap('123', {'type': 'view_once'});
      expect(m.durationMs, isNull);
      expect(resolveViewOnceSecs(m.durationMs), 10);
    });
  });
}
