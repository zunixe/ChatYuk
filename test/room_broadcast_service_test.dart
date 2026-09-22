import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/room_broadcast_service.dart';

/// Fase 3 — RoomBroadcastSession (logic-only): tangga bitrate & cap.
/// Bagian WebRTC (RTCPeerConnection/renderer) TIDAK diuji di sini —
/// membutuhkan plugin native.
void main() {
  group('targetKbps', () {
    test('<=2 penonton → 1200 kbps', () {
      expect(RoomBroadcastSession.targetKbps(0), 1200);
      expect(RoomBroadcastSession.targetKbps(2), 1200);
    });

    test('3-4 penonton → 700 kbps', () {
      expect(RoomBroadcastSession.targetKbps(3), 700);
      expect(RoomBroadcastSession.targetKbps(4), 700);
    });

    test('>4 penonton → 400 kbps', () {
      expect(RoomBroadcastSession.targetKbps(5), 400);
      expect(RoomBroadcastSession.targetKbps(50), 400);
    });

    test('monoton tidak naik saat penonton bertambah', () {
      var prev = 1 << 30;
      for (var v = 0; v <= 10; v++) {
        final k = RoomBroadcastSession.targetKbps(v);
        expect(k, lessThanOrEqualTo(prev));
        prev = k;
      }
    });
  });

  test('kMaxBroadcasters = 4', () {
    expect(RoomBroadcastSession.kMaxBroadcasters, 4);
  });
}
