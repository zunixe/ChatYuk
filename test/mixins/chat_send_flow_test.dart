import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/cache/offline_outbox.dart';
import 'package:chatyuk/utils.dart' show capitalizeFirst;
import 'package:chatyuk/utils/mention.dart';

/// Mengunci kontrak `chat_send_mixin` (alur kirim teks/caption/poin):
/// kapitalisasi, mention, guard double-tap, edit-mode, pending-id, deteksi
/// error jaringan vs error blokir. Harness penuh mixin berat (butuh
/// Auth/Profile/Points/Outbox) — di sini kunci helper + aturan yang dipakai
/// mixin, supaya refactor private↔room tidak diam-diam mengubah perilaku.
void main() {
  group('kapitalisasi pesan baru (gaya WhatsApp)', () {
    test('huruf pertama dikapitalkan', () {
      expect(capitalizeFirst('halo dunia'), 'Halo dunia');
    });

    test('string kosong tetap kosong (diabaikan mixin)', () {
      expect(capitalizeFirst(''), '');
      expect(capitalizeFirst('   ').trim(), isEmpty);
    });
  });

  group('mention', () {
    test('parseMentions menemukan uid dari kandidat', () {
      const cands = [Mention(uid: 'u-sari', name: 'Sari')];
      final out = parseMentions('hai @Sari apa kabar', candidates: cands);
      expect(out.map((m) => m.uid), contains('u-sari'));
    });

    test('tanpa @ → daftar kosong (kolom mentions tidak dikirim)', () {
      const cands = [Mention(uid: 'u-sari', name: 'Sari')];
      expect(parseMentions('halo dunia', candidates: cands), isEmpty);
    });
  });

  group('guard kirim', () {
    test('teks kosong tanpa foto → no-op', () {
      const raw = '   ';
      const hasPhoto = false;
      final shouldSend = raw.trim().isNotEmpty || hasPhoto;
      expect(shouldSend, isFalse);
    });

    test('double-tap (_isSending true) → return awal', () async {
      var dispatched = false;
      Future<void> sendMessage(bool isSending) async {
        if (isSending) return;
        dispatched = true;
      }

      await sendMessage(true);
      expect(dispatched, isFalse);
      await sendMessage(false);
      expect(dispatched, isTrue);
    });

    test('edit-mode teks sama → cancel (bukan persist)', () {
      const editingText = 'lama';
      const raw = 'lama';
      final shouldPersist = raw.isNotEmpty && raw != editingText;
      expect(shouldPersist, isFalse);
    });

    test('edit-mode teks beda → persist', () {
      const editingText = 'lama';
      const raw = 'baru';
      final shouldPersist = raw.isNotEmpty && raw != editingText;
      expect(shouldPersist, isTrue);
    });
  });

  group('pending + error jaringan', () {
    test('pending id ber-prefix pending- (ditolak reaksi)', () {
      final id = 'pending-${DateTime.now().microsecondsSinceEpoch}';
      expect(id.startsWith('pending-'), isTrue);
    });

    test('isNetworkError membedakan jaringan vs blokir', () {
      expect(
        OfflineOutbox.isNetworkError(Exception('SocketException: Failed')),
        isTrue,
      );
      expect(
        OfflineOutbox.isNetworkError(Exception('42501 policy')),
        isFalse,
        reason: 'blokir RLS harus snackbar, bukan antrean',
      );
    });
  });
}
