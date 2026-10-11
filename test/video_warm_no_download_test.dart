import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/widgets/video_prefetch.dart';

/// ZERO-JANK (2026-10-11, keputusan produk): buka chat TIDAK mengunduh video
/// penuh otomatis — video hanya diunduh saat user tap play. Regresi yang
/// dikunci: `warmChat` + `warmOne(path)` tanpa bytes lokal DILARANG menyentuh
/// `downloader` (dulu tiap buka chat = s.d. 6 video penuh terunduh otomatis).
MessageModel _videoMsg(String path, int i) => MessageModel(
      id: 'v$i',
      senderId: 'other',
      senderName: 'Lawan',
      senderGender: '',
      isRegistered: false,
      text: '',
      type: 'video',
      imageData: path,
      timestamp: DateTime.utc(2026, 10, 11, 10, i),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int dlCalls;

  setUp(() {
    dlCalls = 0;
    VideoPrefetch.downloader = (String path) async {
      dlCalls++;
      return Uint8List.fromList(List<int>.filled(16, 1));
    };
    // posterGenerator sengaja null: tanpa generator pun tidak boleh download.
    VideoPrefetch.posterGenerator = null;
  });

  tearDown(() {
    VideoPrefetch.downloader = null;
    VideoPrefetch.posterGenerator = null;
  });

  test('warmChat tidak mengunduh video (poster MISS → lewati)', () async {
    final msgs = [
      _videoMsg('chat/c1/a.mp4', 1),
      _videoMsg('chat/c1/b.mp4', 2),
      _videoMsg('chat/c1/c.mp4', 3),
    ];
    await VideoPrefetch.warmChat('kunciUnikWarmChat', msgs);
    expect(dlCalls, 0);
  });

  test('warmOne tanpa bytes lokal tidak mengunduh', () async {
    await VideoPrefetch.warmOne('chat/c1/tanpa-poster.mp4');
    expect(dlCalls, 0);
  });
}
