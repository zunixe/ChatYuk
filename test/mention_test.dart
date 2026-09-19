import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/core/cache/offline_outbox.dart';
import 'package:chatyuk/utils/mention.dart';

void main() {
  const budi = Mention(uid: 'u-budi', name: 'Budi');
  const budiSantoso = Mention(uid: 'u-bs', name: 'Budi Santoso');
  const sari = Mention(uid: 'u-sari', name: 'Sari');

  group('activeMentionToken', () {
    test('deteksi token di akhir teks', () {
      final t = activeMentionToken('halo @bud', 9);
      expect(t, isNotNull);
      expect(t!.start, 5);
      expect(t.query, 'bud');
    });

    test('token di tengah, kursor tepat setelah nama', () {
      final t = activeMentionToken('hai @sar apa kabar', 8);
      expect(t!.start, 4);
      expect(t.query, 'sar');
    });

    test('null setelah spasi', () {
      expect(activeMentionToken('hai @sar ', 9), isNull);
    });

    test('null tanpa @', () {
      expect(activeMentionToken('halo dunia', 10), isNull);
    });

    test('null bila @ menempel huruf sebelumnya (email)', () {
      expect(activeMentionToken('a@b', 3), isNull);
    });

    test('query tanpa spasi — nama berspasi dipilih utuh dari daftar', () {
      final t = activeMentionToken('@Budi', 5);
      expect(t!.query, 'Budi');
      // Spasi menutup token (user memilih item, bukan mengetik nama penuh).
      expect(activeMentionToken('@Budi San', 9), isNull);
    });

    test('null saat baris baru', () {
      expect(activeMentionToken('@budi\nx', 7), isNull);
    });

    test('null saat kursor di posisi 0', () {
      expect(activeMentionToken('@budi', 0), isNull);
    });

    test('null saat kursor melebihi panjang teks', () {
      expect(activeMentionToken('@budi', 10), isNull);
    });

    test('@ tunggal = token kosong (panel bisa muncul)', () {
      final t = activeMentionToken('@', 1);
      expect(t, isNotNull);
      expect(t!.start, 0);
      expect(t.query, '');
    });

    test('query lebih dari 40 char diabaikan', () {
      final long = '@${'a' * 41}';
      expect(activeMentionToken(long, long.length), isNull);
    });

    test('deteksi @everyone sebagai token', () {
      final t = activeMentionToken('@everyone', 9);
      expect(t!.query, 'everyone');
    });
  });

  group('filterCandidates', () {
    final all = [budi, budiSantoso, sari];

    test('prefix nama diprioritaskan', () {
      final r = filterCandidates(all, 'bud');
      expect(r.map((e) => e.uid), ['u-budi', 'u-bs']);
    });

    test('cocok prefix kata kedua', () {
      final r = filterCandidates(all, 'sant');
      expect(r.single.uid, 'u-bs');
    });

    test('query kosong = urutan asli', () {
      expect(filterCandidates(all, '').length, 3);
    });

    test('limit dipatuhi', () {
      expect(filterCandidates(all, '', limit: 2).length, 2);
    });

    test('case-insensitive', () {
      expect(filterCandidates(all, 'bUdI').map((e) => e.uid), contains('u-budi'));
    });

    test('query tanpa hasil = kosong', () {
      expect(filterCandidates(all, 'zzz'), isEmpty);
    });

    test('query hanya spasi diperlakukan sebagai kosong', () {
      expect(filterCandidates(all, '   ').length, 3);
    });

    test('dedup uid walau nama berbeda', () {
      final r = filterCandidates(const [
        Mention(uid: 'u1', name: 'Budi'),
        Mention(uid: 'u1', name: 'Budi S'),
      ], 'bud');
      expect(r.length, 1);
    });
  });

  group('parseMentions', () {
    final candidates = [budi, budiSantoso, sari];

    test('resolusi mention tunggal', () {
      final r = parseMentions('hai @Budi apa kabar', candidates: candidates);
      expect(r.single.uid, 'u-budi');
    });

    test('nama berspasi menang atas prefix lebih pendek', () {
      final r = parseMentions('cc @Budi Santoso ya', candidates: candidates);
      expect(r.single.uid, 'u-bs');
    });

    test('dedupe uid', () {
      final r = parseMentions('@Budi @Budi', candidates: candidates);
      expect(r.length, 1);
    });

    test('tidak cocok substring tanpa batas', () {
      final r = parseMentions('email@Budi.com', candidates: candidates);
      expect(r, isEmpty);
    });

    test('@all diabaikan bila allowAll=false', () {
      final r = parseMentions('@all kumpul', candidates: candidates);
      expect(r, isEmpty);
    });

    test('@all diekspansi bila allowAll=true', () {
      final r = parseMentions(
        '@all kumpul',
        candidates: candidates,
        allowAll: true,
        allExpansion: candidates,
      );
      expect(r.map((e) => e.uid).toSet(), {'u-budi', 'u-bs', 'u-sari'});
    });

    test('@all + mention bernama saling melengkapi', () {
      final r = parseMentions(
        '@all dan @Sari',
        candidates: candidates,
        allowAll: true,
        allExpansion: [budi],
      );
      expect(r.map((e) => e.uid).toSet(), {'u-budi', 'u-sari'});
    });

    test('mention di awal teks', () {
      final r = parseMentions('@Budi halo', candidates: candidates);
      expect(r.single.uid, 'u-budi');
    });

    test('mention di akhir teks', () {
      final r = parseMentions('halo @Sari', candidates: candidates);
      expect(r.single.uid, 'u-sari');
    });

    test('mention diikuti tanda baca tetap cocok', () {
      final r = parseMentions('halo @Budi, apa kabar?', candidates: candidates);
      expect(r.single.uid, 'u-budi');
    });

    test('dua nama berbeda = 2 entri', () {
      final r = parseMentions('@Budi @Sari', candidates: candidates);
      expect(r.map((e) => e.uid).toSet(), {'u-budi', 'u-sari'});
    });

    test('@everyone diekspansi bila allowAll=true', () {
      final r = parseMentions(
        '@everyone kumpul',
        candidates: candidates,
        allowAll: true,
        allExpansion: candidates,
      );
      expect(r.length, 3);
    });

    test('allowAll tanpa allExpansion = tidak ada entri', () {
      final r = parseMentions(
        '@all kumpul',
        candidates: candidates,
        allowAll: true,
      );
      expect(r, isEmpty);
    });

    test('teks kosong = kosong', () {
      expect(parseMentions('', candidates: candidates), isEmpty);
    });

    test('kandidat kosong = kosong', () {
      expect(parseMentions('@Budi', candidates: const []), isEmpty);
    });
  });

  group('hasAllToken', () {
    test('deteksi @all', () => expect(hasAllToken('hai @all'), isTrue));
    test(
      'deteksi @everyone',
      () => expect(hasAllToken('@everyone hello'), isTrue),
    );
    test('tidak deteksi @alls', () => expect(hasAllToken('@alls'), isFalse));
  });

  group('Mention map round-trip', () {
    test('toMap/fromMap', () {
      final m = Mention(uid: 'u1', name: 'Nama Satu');
      final back = Mention.fromMap(m.toMap());
      expect(back.uid, 'u1');
      expect(back.name, 'Nama Satu');
    });

    test('listFrom membuang entri tanpa uid', () {
      final list = Mention.listFrom([
        {'uid': 'a', 'name': 'A'},
        {'uid': '', 'name': 'B'},
        {'name': 'C'},
      ]);
      expect(list.length, 1);
      expect(list.single.uid, 'a');
    });

    test('listFrom menerima nilai non-list = kosong', () {
      expect(Mention.listFrom(null), isEmpty);
      expect(Mention.listFrom('bukan list'), isEmpty);
      expect(Mention.listFrom({'uid': 'x'}), isEmpty);
    });

    test('listTo list kosong = []', () {
      expect(Mention.listTo(const []), isEmpty);
    });

    test('equality berdasarkan uid + name', () {
      expect(const Mention(uid: 'u', name: 'N'),
          const Mention(uid: 'u', name: 'N'));
      expect(const Mention(uid: 'u', name: 'N') ==
              const Mention(uid: 'u', name: 'Lain'),
          isFalse);
    });
  });

  group('MessageModel mentions', () {
    test('fromMap membaca mentions', () {
      final m = MessageModel.fromMap('1', {
        'senderId': 'x',
        'text': 'hai @Budi',
        'mentions': [
          {'uid': 'u-budi', 'name': 'Budi'},
        ],
      });
      expect(m.mentions.single.uid, 'u-budi');
    });

    test('toMap menyimpan mentions', () {
      final m = MessageModel(
        id: '1',
        senderId: 'x',
        senderName: 'X',
        senderGender: 'other',
        isRegistered: true,
        text: 'hai',
        type: 'text',
        imageData: '',
        timestamp: DateTime.now(),
        mentions: const [Mention(uid: 'u-budi', name: 'Budi')],
      );
      expect((m.toMap()['mentions'] as List).length, 1);
    });

    test('pesan terhapus mengosongkan mentions', () {
      final m = MessageModel(
        id: '1',
        senderId: 'x',
        senderName: 'X',
        senderGender: 'other',
        isRegistered: true,
        text: 'hai @Budi',
        type: 'text',
        imageData: '',
        timestamp: DateTime.now(),
        mentions: const [Mention(uid: 'u-budi', name: 'Budi')],
      );
      final deleted = m.copyWith(isDeleted: true);
      expect(deleted.mentions, isEmpty);
      // copyWith tanpa argumen mentions mempertahankan nilai lama.
      expect(m.copyWith(text: 'hai lagi').mentions.single.uid, 'u-budi');
      expect(
        MessageModel.fromMap('1', {
          'isDeleted': true,
          'mentions': [
            {'uid': 'u-budi', 'name': 'Budi'},
          ],
        }).mentions,
        isEmpty,
      );
    });
  });

  group('OutboxEntry mentions', () {
    test('round-trip map', () {
      final e = OutboxEntry(
        pendingId: 'p1',
        kind: 'room',
        chatId: 'r1',
        senderId: 'x',
        senderName: 'X',
        senderGender: 'other',
        text: 'hai @Budi',
        mentions: const [Mention(uid: 'u-budi', name: 'Budi')],
        createdAt: DateTime.now(),
      );
      final back = OutboxEntry.fromMap(e.toMap());
      expect(back.mentions.single.uid, 'u-budi');
    });
  });
}
