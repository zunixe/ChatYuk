import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/active_call_model.dart';
import 'package:chatyuk/services/admin_call_watch_service.dart';

/// P3: jalur call & monitor admin yang berisiko tapi minim test.
///
/// Yang bisa dikunci TANPA plugin WebRTC/foreground-service:
/// - `WatchParticipant` state awal (renderer lazy — aman dikonstruksi)
/// - `WatchSession` daftar peserta dari `ActiveCallInfo` (guard anti-intip:
///   sesi hanya dibuat untuk peserta call yang benar)
/// - `ActiveCallInfo.fromJson` + `elapsedSeconds` (model, sudah ada di
///   `models_extra_test.dart` — di sini fokus sisi monitor)
///
/// Yang TIDAK bisa: `start()`/`stop()` (createPeerConnection, renderer),
/// `CallNotification` (FlutterForegroundTask native).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ActiveCallInfo call({
    String id = 'call-1',
    String callerId = 'u-caller',
    String calleeId = 'u-callee',
    String callType = 'video',
    DateTime? answeredAt,
  }) =>
      ActiveCallInfo(
        id: id,
        chatId: 'chat-1',
        callerId: callerId,
        calleeId: calleeId,
        callerName: 'Penelepon',
        calleeName: 'Penerima',
        callType: callType,
        status: 'answered',
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        answeredAt: answeredAt,
      );

  group('WatchParticipant — state awal', () {
    test('default: belum konek, mic & kamera ON', () {
      final p = WatchParticipant(uid: 'u1', name: 'Budi');
      expect(p.uid, 'u1');
      expect(p.name, 'Budi');
      expect(p.pc, isNull);
      expect(p.connecting, isFalse);
      expect(p.connected, isFalse);
      expect(p.micOn, isTrue);
      expect(p.cameraOn, isTrue);
      expect(p.hasVideoTrack, isFalse);
    });
  });

  group('WatchSession — daftar peserta', () {
    test('selalu berisi caller + callee (2 pihak)', () {
      final s = WatchSession(call());
      expect(s.participants.length, 2);
      expect(s.participants[0].uid, 'u-caller');
      expect(s.participants[1].uid, 'u-callee');
      expect(s.participants[0].name, 'Penelepon');
      expect(s.participants[1].name, 'Penerima');
    });

    test('isVideo mengikuti callType', () {
      expect(WatchSession(call(callType: 'video')).isVideo, isTrue);
      expect(WatchSession(call(callType: 'audio')).isVideo, isFalse);
    });

    test('belum start → stopped false; mainIndex default 0 (caller)', () {
      final s = WatchSession(call());
      expect(s.stopped, isFalse);
      expect(s.mainIndex, 0);
    });
  });

  group('ActiveCallInfo — model sisi monitor', () {
    test('fromJson default aman saat field kosong', () {
      final c = ActiveCallInfo.fromJson(const {});
      expect(c.id, '');
      expect(c.chatId, '');
      expect(c.callerName, 'Unknown');
      expect(c.calleeName, 'Unknown');
      expect(c.callType, 'video');
      expect(c.status, 'ringing');
      expect(c.answeredAt, isNull);
    });

    test('elapsedSeconds pakai answeredAt bila ada, createdAt bila belum', () {
      final answered = ActiveCallInfo(
        id: 'c',
        chatId: 'ch',
        callerId: 'a',
        calleeId: 'b',
        callerName: 'A',
        calleeName: 'B',
        callType: 'audio',
        status: 'answered',
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        answeredAt: DateTime.now().subtract(const Duration(seconds: 30)),
      );
      expect(answered.elapsedSeconds, inInclusiveRange(28, 32),
          reason: 'dihitung dari answeredAt, bukan createdAt');

      final ringing = ActiveCallInfo(
        id: 'c',
        chatId: 'ch',
        callerId: 'a',
        calleeId: 'b',
        callerName: 'A',
        calleeName: 'B',
        callType: 'audio',
        status: 'ringing',
        createdAt: DateTime.now().subtract(const Duration(seconds: 5)),
      );
      expect(ringing.elapsedSeconds, inInclusiveRange(4, 7));
    });

    test('elapsedSeconds tidak negatif (clock skew / waktu depan)', () {
      final future = ActiveCallInfo(
        id: 'c',
        chatId: 'ch',
        callerId: 'a',
        calleeId: 'b',
        callerName: 'A',
        calleeName: 'B',
        callType: 'audio',
        status: 'answered',
        createdAt: DateTime.now().add(const Duration(minutes: 5)),
        answeredAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      expect(future.elapsedSeconds, 0, reason: 'di-clamp ke 0');
    });
  });
}
