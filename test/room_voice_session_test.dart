import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/room_voice_service.dart';

/// Voice stage global room: state awal + konstanta.
/// (Handshake WebRTC butuh 2 HP — diuji manual; di sini kunci state murni
/// agar refactor tak merusak kontrak UI.)
void main() {
  // stop() sekarang menyentuh platform channel audio (setSpeakerphoneOn) →
  // binding wajib siap agar tidak "Binding has not yet been initialized".
  TestWidgetsFlutterBinding.ensureInitialized();

  RoomVoiceSession make() => RoomVoiceSession(
        roomId: 'room-1',
        myUid: 'uid-1',
      );

  group('RoomVoiceSession state awal', () {
    test('belum join: semua flag mati', () {
      final s = make();
      expect(s.joined, isFalse);
      expect(s.onStage, isFalse);
      expect(s.muted, isTrue);
      expect(s.speakers, isEmpty);
      expect(s.speakerCount, 0);
      expect(s.isSpeaking('x'), isFalse);
      expect(s.isMuted('x'), isFalse);
      s.dispose();
    });

    test('batas stage = 6 (cermin server room_voice_join)', () {
      expect(RoomVoiceSession.kMaxSpeakers, 6);
      make().dispose();
    });

    test('callback opsional boleh null', () {
      final s = RoomVoiceSession(roomId: 'r', myUid: 'u');
      expect(s.joined, isFalse);
      s.dispose();
    });

    test('pairing mati di awal (belum stage)', () {
      final s = make();
      expect(s.pairing, isFalse);
      s.dispose();
    });
  });

  group('Generasi sesi v_bye (keluar-masuk cepat)', () {
    test('sesi baru nomornya lebih besar', () {
      final a = make();
      final b = make();
      expect(b.sessId, greaterThan(a.sessId));
      a.dispose();
      b.dispose();
    });

    test('v_bye basi (sess lama) diabaikan, sess baru diproses', () {
      expect(isStaleBye(5, 3), isTrue);
      expect(isStaleBye(5, 5), isFalse);
      expect(isStaleBye(5, 7), isFalse);
      // Belum pernah dengar speaker (-1): bye apa pun diproses.
      expect(isStaleBye(-1, 0), isFalse);
    });
  });

  group('Routing kandidat ICE (mesh dua arah)', () {
    // A = peer. Aku punya pc uplink ke A (key 'A', pcId 'up_1') DAN pc
    // downlink dari A (key 'dn_A', pcId 'dn_2') — skenario mesh dua arah.
    const a = 'A';
    final pcIds = {'A': 'up_1', 'dn_A': 'dn_2'};
    final peerKeys = {'A', 'dn_A'};

    test('candPcId cocok → pc arah yang tepat (uplink)', () {
      expect(
        resolveCandidateKey(
          from: a,
          candPcId: 'up_1',
          dir: '',
          pcIds: pcIds,
          peerKeys: peerKeys,
        ),
        'A',
      );
    });

    test('candPcId cocok → pc arah yang tepat (downlink)', () {
      expect(
        resolveCandidateKey(
          from: a,
          candPcId: 'dn_2',
          dir: '',
          pcIds: pcIds,
          peerKeys: peerKeys,
        ),
        'dn_A',
      );
    });

    test('hint dir=down → key downlink meski uplink ada', () {
      expect(
        resolveCandidateKey(
          from: a,
          candPcId: '',
          dir: 'down',
          pcIds: const {},
          peerKeys: peerKeys,
        ),
        'dn_A',
      );
    });

    test('hint dir=up → key uplink', () {
      expect(
        resolveCandidateKey(
          from: a,
          candPcId: '',
          dir: 'up',
          pcIds: const {},
          peerKeys: peerKeys,
        ),
        'A',
      );
    });

    test('tanpa pcId/hint: pcId tak dikenal + tidak ada peer → downlink', () {
      expect(
        resolveCandidateKey(
          from: a,
          candPcId: 'unknown',
          dir: '',
          pcIds: const {},
          peerKeys: const {},
        ),
        'dn_A',
      );
    });

    test('tanpa pcId/hint: ada uplink → pakai uplink', () {
      expect(
        resolveCandidateKey(
          from: a,
          candPcId: '',
          dir: '',
          pcIds: const {},
          peerKeys: {'A'},
        ),
        'A',
      );
    });
  });

  group('Keputusan relay-only ICE (percepat connect + fallback)', () {
    test('peer belum fallback → relay-only (config tercepat)', () {
      expect(
        relayOnlyFor(
          peerUid: 'A',
          allCandTried: const {},
        ),
        isTrue,
      );
    });

    test('peer sudah fallback all-candidates → relay-only OFF (tak ping-pong)', () {
      expect(
        relayOnlyFor(
          peerUid: 'A',
          allCandTried: const {'A'},
        ),
        isFalse,
      );
    });

    test('fallback HANYA berlaku untuk peer itu (peer lain tetap relay-only)', () {
      const tried = {'A'};
      expect(relayOnlyFor(peerUid: 'A', allCandTried: tried),
          isFalse);
      expect(relayOnlyFor(peerUid: 'B', allCandTried: tried),
          isTrue);
    });
  });

  group('Full mesh 3-6 orang (keputusan offer uplink per-peer)', () {
    test('aku di stage & belum ada pc → offer ke speaker lain', () {
      expect(
        meshNeedsOfferTo(
          myUid: 'me',
          peerUid: 'A',
          onStage: true,
          hasUplinkPc: false,
        ),
        isTrue,
      );
    });

    test('pc uplink sudah ada → TIDAK offer lagi (idempoten)', () {
      expect(
        meshNeedsOfferTo(
          myUid: 'me',
          peerUid: 'A',
          onStage: true,
          hasUplinkPc: true,
        ),
        isFalse,
      );
    });

    test('tidak di stage (pendengar) → tidak offer', () {
      expect(
        meshNeedsOfferTo(
          myUid: 'me',
          peerUid: 'A',
          onStage: false,
          hasUplinkPc: false,
        ),
        isFalse,
      );
    });

    test('self & uid kosong → tidak offer', () {
      expect(
        meshNeedsOfferTo(
          myUid: 'me',
          peerUid: 'me',
          onStage: true,
          hasUplinkPc: false,
        ),
        isFalse,
      );
      expect(
        meshNeedsOfferTo(
          myUid: 'me',
          peerUid: '',
          onStage: true,
          hasUplinkPc: false,
        ),
        isFalse,
      );
    });
  });
}
