import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/chat_stream_session.dart';

/// GUARD realtime view-once (bug 2026-10-20): broadcast `view_once_seen`
/// dikirim ke topik `private_<chatId>` sementara subscriber stream chat
/// mendengarkan di `msg-<cacheKey>-<n>` → tidak pernah bertemu sehingga
/// PENGIRIM tidak melihat "foto sudah kadaluarsa" secara realtime.
/// Sekarang topik = SATU sumber (`chatStreamTopic`/`viewOnceSeenTopic`).
void main() {
  test('chatStreamTopic = msg-<cacheKey>', () {
    expect(chatStreamTopic('private_uidA_uidB'), 'msg-private_uidA_uidB');
    expect(chatStreamTopic('room_42'), 'msg-room_42');
  });

  test(
    'viewOnceSeenTopic private = topik stream chat private (cocok persis)',
    () {
      const chatId = 'uidA_uidB';
      expect(
        viewOnceSeenTopic(isRoom: false, id: chatId),
        chatStreamTopic('private_$chatId'),
      );
    },
  );

  test('viewOnceSeenTopic room = topik stream chat room (cocok persis)', () {
    const roomId = '42';
    expect(
      viewOnceSeenTopic(isRoom: true, id: roomId),
      chatStreamTopic('room_$roomId'),
    );
  });

  test('GUARD sumber: subscriber & pengirim memakai helper topik yang sama', () {
    final session = File(
      'lib/services/chat_stream_session.dart',
    ).readAsStringSync();
    // Subscriber memakai helper (bukan string 'msg-$cacheKey' mentah).
    expect(session.contains('chatStreamTopic(cacheKey)'), isTrue);
    // Topik TIDAK boleh lagi bersufiks percobaan reconnect (memecah cocokan
    // dengan pengirim broadcast).
    expect(session.contains(r'${channelAttempt++}'), isFalse);
    // Handler broadcast tetap ada di kanal ini.
    expect(
      RegExp(r"onBroadcast\(\s*event:\s*'view_once_seen'").hasMatch(session),
      isTrue,
    );

    final room = File('lib/services/chat_service_room.dart').readAsStringSync();
    // Pengirim view_once_seen memakai helper (dulu hardcode 'private_$chatId').
    expect(
      room.contains('viewOnceSeenTopic(isRoom: isRoom, id: chatId)'),
      isTrue,
    );
    expect(room.contains("_sb.channel('private_\$chatId')"), isFalse);

    final priv = File(
      'lib/services/chat_service_private.dart',
    ).readAsStringSync();
    // Broadcast new_message juga memakai topik stream (kelas bug yang sama).
    expect(priv.contains("chatStreamTopic('private_\$chatId')"), isTrue);
    expect(priv.contains("_sb.channel('private_\$chatId')"), isFalse);
  });

  test('GUARD SEC-01: broadcast pesan baru = sinyal id, isi tak dipercaya', () {
    // Channel broadcast publik bisa disadap & dipalsukan siapa pun yang tahu
    // topiknya (REVIEW_2026-10-24). Pengirim hanya boleh mengirim id; penerima
    // wajib mengambil baris asli lewat RLS, bukan memakai payload.
    expect(chatNewMessageSignalEvent, 'new_message_id');
    final priv = File(
      'lib/services/chat_service_private.dart',
    ).readAsStringSync();
    final send = RegExp(
      r'_sendBroadcastOnce\(\s*chatId,\s*chatNewMessageSignalEvent,\s*\{([^}]*)\}',
    ).firstMatch(priv);
    expect(send, isNotNull);
    final keys = RegExp(
      r"'([a-z_]+)'\s*:",
    ).allMatches(send!.group(1)!).map((m) => m.group(1)).toSet();
    expect(keys, {'chat_id', 'id'});

    final session = File(
      'lib/services/chat_stream_session.dart',
    ).readAsStringSync();
    expect(session.contains('ingestBroadcastSignal(payload)'), isTrue);
    expect(
      session.contains("'bc-\${"),
      isFalse,
      reason: 'id palsu bc-<micros> = pesan dari payload broadcast',
    );
    expect(
      RegExp(
        r"\.eq\('id', id\)\s*\.eq\(filterKey, filterVal\)",
      ).hasMatch(session),
      isTrue,
    );
  });

  test('GUARD sumber: resume app me-reload + join ulang kanal realtime', () {
    // Skenario nyata 2026-10-20 (tes 2 app di SATU HP): sender di-background
    // saat penerima membuka foto → socket mati, reconnect ditahan saat
    // background → broadcast terlewat. Hook resume wajib reload + kanal baru.
    final session = File(
      'lib/services/chat_stream_session.dart',
    ).readAsStringSync();
    expect(
      session.contains('AppForeground.isForeground.addListener(_onFgChanged)'),
      isTrue,
    );
    expect(
      session.contains(
        'AppForeground.isForeground.removeListener(_onFgChanged)',
      ),
      isTrue,
    );
    expect(session.contains('reconnectNow();'), isTrue);
    // Kanal lama yang di-teardown sengaja memicu status `closed` — WAJIB
    // diabaikan, kalau tidak reconnect berulang tiap ~2 dtk (loop terukur
    // 14:01-14:02 pada build 2026-10-20).
    expect(session.contains('identical(ch, channel)'), isTrue);
  });
}
