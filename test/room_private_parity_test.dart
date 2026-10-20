import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PARITAS room (grup & global) vs private chat untuk MEDIA & BALASAN.
///
/// Guard ini mengunci hasil audit 2026-10-20:
/// 1. Room WAJIB mengambil `replied_to_meta` — dulu tidak, akibatnya thumbnail
///    kutipan media hilang setiap keluar-masuk room.
/// 2. Bubble room memakai widget yang SAMA (ViewOnceImage/MessageImage/ReplyQuote)
///    dengan `isRoom: true` supaya perilaku sekali-lihat identik private.
/// 3. HD hanya dari panel galeri (tidak ada toggle HD di composer room).
void main() {
  String read(String p) => File(p).readAsStringSync();

  test('room mengambil replied_to_meta seperti private', () {
    final src = read('lib/services/chat_stream_session.dart');
    expect(
      src.contains(r"'$roomCols,replied_to_meta'"),
      isTrue,
      reason: 'roomCols wajib + replied_to_meta agar kutipan media tampil',
    );
    expect(src.contains(r"'$privateCols,$replyCols'"), isTrue);
  });

  test('bubble room memakai widget media yang sama + isRoom', () {
    final bubble = read(
      'lib/screens/room_chat/widgets/room_message_bubble.dart',
    );
    expect(bubble.contains('ViewOnceImage('), isTrue);
    expect(bubble.contains('isRoom: true'), isTrue);
    expect(bubble.contains('MessageImage('), isTrue);
    expect(bubble.contains('ReplyQuote.fromMessage('), isTrue);
    expect(
      bubble.contains('meta: msg.repliedToMeta'),
      isTrue,
      reason: 'kutipan media (foto/video/lokasi/stiker) butuh meta',
    );
  });

  test('room: HD hanya dari galeri, tanpa toggle HD di composer', () {
    final live = read('lib/screens/room_chat/room_chat_live.dart');
    expect(live.contains('openGalleryPicker()'), isTrue);
    expect(live.contains('photoHd'), isFalse);
    expect(live.contains('onHdChanged'), isFalse);
  });

  test('kunci cache kutipan room = room_<id>', () {
    final core = read('lib/screens/room_chat/room_chat_core.dart');
    expect(core.contains(r"String get sendReplyCacheKey => 'room_${widget.room.id}'"), isTrue);
  });

  test('video (biasa & sekali-lihat) aktif di room seperti private', () {
    final core = read('lib/screens/room_chat/room_chat_core.dart');
    expect(core.contains('bool get videoSendEnabled => true;'), isTrue);
    expect(core.contains('String? get sendPendingVideoPath => _pendingVideoPath;'), isTrue);
    expect(core.contains('void videoSetPreview('), isTrue);
    expect(core.contains('void videoClearPreview()'), isTrue);

    final live = read('lib/screens/room_chat/room_chat_live.dart');
    expect(live.contains('videoPickToPreview()'), isTrue);
    expect(live.contains('pendingVideoPath: _pendingVideoPath'), isTrue);
    expect(live.contains('videoOnce: _pendingVideoOnce'), isTrue);

    // Bubble room merender video lewat widget SAMA dengan private.
    final bubble = read('lib/screens/room_chat/widgets/room_message_bubble.dart');
    expect(bubble.contains('ChatVideoBubble('), isTrue);
    expect(bubble.contains("msg.type == 'video_once'"), isTrue);

    // Expiry video sekali-lihat harus tahu tabel room (messages) — bukan
    // selalu private_messages.
    final vb = read('lib/widgets/chat_video_bubble.dart');
    expect(vb.contains('isRoom: widget.isRoom'), isTrue);
    expect(vb.contains('chatId: widget.chatId.isEmpty ? null : widget.chatId'), isTrue);
  });

  test('room dedupe video pending vs server (anti dobel)', () {
    final room = read('lib/screens/room_chat/room_chat_room.dart');
    expect(room.contains('_confirmedVideoIds.add(m.id)'), isTrue);
    final state = read('lib/screens/room_chat_screen.dart');
    expect(state.contains('_confirmedVideoIds'), isTrue);
  });
}
