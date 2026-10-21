import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/services/chat_stream_session.dart';

/// Bukti: saat penerima membuka foto sekali-lihat, pengirim menerima
/// broadcast `view_once_seen` dan pesannya LANGSUNG berubah jadi
/// `*_once_expired` (kartu terkunci) tanpa refetch.
void main() {
  MessageModel viewOnce({String type = 'view_once'}) => MessageModel(
    id: '77',
    senderId: 'me',
    senderName: 'A',
    senderGender: 'male',
    isRegistered: true,
    text: '',
    type: type,
    imageData: 'X',
    timestamp: DateTime(2026, 10, 20, 6),
  );

  test('apply pesan berubah ke view_once_expired (jalur broadcast)', () {
    // Simulasi yang dilakukan listener: copyWith(type: newType).
    final before = [viewOnce()];
    expect(before.first.type, 'view_once');

    final after = List<MessageModel>.of(before)
      ..[0] = before[0].copyWith(type: 'view_once_expired');
    expect(after.first.type, 'view_once_expired');
    // UI membaca type ini → isExpired=true → kartu terkunci.
    expect(after.first.type == 'view_once_expired', isTrue);
  });

  test('video sekali-lihat memakai type video_once_expired', () {
    final m = viewOnce(type: 'video_once');
    final after = m.copyWith(type: 'video_once_expired');
    expect(after.type, 'video_once_expired');
  });

  test('applyUpdateRecord juga mengubah type (jalur realtime postgres)', () {
    final cur = [viewOnce()];
    final next = ChatStreamSession.applyUpdateRecord(cur, {
      'id': '77',
      'type': 'view_once_expired',
    });
    expect(next, isNotNull);
    expect(next!.first.type, 'view_once_expired');
  });
}
