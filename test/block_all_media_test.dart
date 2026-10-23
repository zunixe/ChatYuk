import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/cache/offline_outbox.dart';
import 'package:chatyuk/core/chat/pending_merge.dart';
import 'package:chatyuk/models/message_model.dart';

/// BLOKIR SENYAP untuk SELURUH jenis media (2026-10-23).
///
/// Aturan produk: bila salah satu pihak memblokir, pesan apa pun yang
/// dikirim TETAP tampil centang-1 (tidak pernah terkirim), TANPA snackbar,
/// dan TIDAK hilang saat chat ditutup-buka.
///
/// Test ini SATU PINTU untuk semua media: daftar tipe diambil langsung dari
/// validasi `sendPrivateMessage`. Tipe baru yang ditambahkan ke sana tanpa
/// jalur blokir di bawah → test GAGAL (tidak perlu dicek satu-satu lagi).
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// Tipe yang boleh dikirim lewat `sendPrivateMessage`, dibaca dari kode.
  List<String> serviceTypes() {
    final src = read('lib/services/chat_service_private.dart');
    final start = src.indexOf('// Validasi tipe pesan');
    expect(start, greaterThan(-1), reason: 'blok validasi tipe harus ada');
    final end = src.indexOf('].contains(type)', start);
    final block = src.substring(start, end);
    return RegExp(r"^\s*'([a-z_]+)',", multiLine: true)
        .allMatches(block)
        .map((m) => m.group(1)!)
        .toList();
  }

  /// Jalur kirim PRIVATE tiap tipe → file yang wajib menangani blokir.
  const sendPaths = <String, String>{
    'text': 'lib/mixins/chat_send_mixin.dart',
    'image': 'lib/mixins/chat_photo_send_mixin.dart',
    'view_once': 'lib/mixins/chat_photo_send_mixin.dart',
    'video': 'lib/mixins/chat_photo_send_mixin.dart',
    'video_once': 'lib/mixins/chat_photo_send_mixin.dart',
    'voice': 'lib/screens/private_chat/private_chat_media.dart',
    'location': 'lib/screens/private_chat/private_chat_build.dart',
    'sticker': 'lib/mixins/chat_sticker_send_mixin.dart',
    'file': 'lib/mixins/chat_file_send_mixin.dart',
    'poll': 'lib/screens/private_chat/private_chat_poll.dart',
    'contact': 'lib/screens/private_chat/private_chat_contact.dart',
  };

  /// Tipe yang BUKAN kiriman konten user (tidak perlu jalur blokir).
  const notUserContent = <String, String>{
    'call': 'log panggilan dari sistem call, bukan kiriman composer',
    'video_once_expired': 'status sesudah dilihat, tak pernah dikirim user',
  };

  test('setiap tipe pesan punya jalur blokir (atau dikecualikan beralasan)',
      () {
    final types = serviceTypes();
    expect(types, isNotEmpty);
    final missing = types
        .where((t) => !sendPaths.containsKey(t) && !notUserContent.containsKey(t))
        .toList();
    expect(missing, isEmpty,
        reason: 'Tipe baru tanpa jalur blokir: $missing. Tambahkan '
            'penanganan isSilentBlock + keepBlocked di jalur kirimnya, lalu '
            'daftarkan di `sendPaths`.');
  });

  for (final entry in sendPaths.entries) {
    test('${entry.key}: gagal karena blokir → keepBlocked (bubble tetap)', () {
      final src = read(entry.value);
      expect(src.contains('isSilentBlock('), isTrue,
          reason: '${entry.value} harus mengenali penolakan blokir');
      expect(src.contains('keepBlocked('), isTrue,
          reason: '${entry.value} harus menyimpan bubble blokir (centang-1)');
    });
  }

  test('foto & video: kedua jalur (gambar + video) menyimpan bubble blokir', () {
    final src = read('lib/mixins/chat_photo_send_mixin.dart');
    expect('keepBlocked('.allMatches(src).length, greaterThanOrEqualTo(2));
  });

  test('flush antrean: entri blokir dilewati & penolakan blokir ditandai', () {
    final src = read('lib/mixins/chat_outbox_mixin.dart');
    expect(src.contains('.where((e) => !e.blocked)'), isTrue,
        reason: 'pesan saat diblokir tidak boleh terkirim setelah unblock');
    expect(src.contains('markBlocked('), isTrue);
    expect(src.contains("outboxKind == 'private'"), isTrue,
        reason: 'room: 42501 = bukan anggota/dibisukan → jangan disenyapkan');
  });

  test('konfirmasi server tidak "memakan" bubble blokir lama', () {
    final src = read('lib/screens/private_chat/private_chat_chat.dart');
    expect(src.contains('outboxBlockedIds.contains(p.id)'), isTrue);
    expect(src.contains('pendings: _pending'), isFalse,
        reason: 'pencocokan wajib memakai list tanpa bubble blokir');
  });

  group('OutboxEntry blokir', () {
    test('roundtrip toMap/fromMap menjaga blocked + poll + contact', () {
      final e = OutboxEntry(
        pendingId: 'p1',
        kind: 'private',
        chatId: 'c1',
        senderId: 'u',
        senderName: 'U',
        senderGender: 'male',
        type: 'poll',
        createdAt: DateTime.utc(2026, 10, 23),
        blocked: true,
        poll: const {'q': 'Makan?', 'o': ['ya', 'tidak'], 'm': false},
        contact: const {'t': 'user', 'u': 'x'},
      );
      final back = OutboxEntry.fromMap(e.toMap());
      expect(back.blocked, isTrue);
      expect(back.poll?['q'], 'Makan?');
      expect(back.contact?['u'], 'x');
      expect(OutboxEntry.fromMap({...e.toMap()}..remove('blocked')).blocked,
          isFalse);
    });

    test('isBlockedError mengenali penolakan trigger (P0001 blocked)', () {
      expect(
        OfflineOutbox.isBlockedError(
          Exception('PostgrestException(message: blocked, code: P0001)'),
        ),
        isTrue,
      );
    });
  });

  group('mergePendingChrono', () {
    MessageModel m(String id, int minute) => MessageModel(
          id: id,
          senderId: 'u',
          senderName: 'U',
          senderGender: 'male',
          isRegistered: true,
          text: id,
          type: 'text',
          imageData: '',
          timestamp: DateTime(2026, 10, 23, 10, minute),
        );

    test('pending lebih baru → ditempel di akhir', () {
      final out = mergePendingChrono([m('a', 1), m('b', 2)], [m('p', 3)]);
      expect(out.map((e) => e.id), ['a', 'b', 'p']);
    });

    test('bubble blokir lama disisipkan sesuai waktu', () {
      final out = mergePendingChrono(
        [m('a', 1), m('b', 5)],
        [m('blk', 3), m('new', 6)],
      );
      expect(out.map((e) => e.id), ['a', 'blk', 'b', 'new']);
    });

    test('tanpa pending → list asli (identitas sama, cache derive tetap hit)',
        () {
      final msgs = [m('a', 1)];
      expect(identical(mergePendingChrono(msgs, const []), msgs), isTrue);
    });
  });
}
