import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/core/call/signal_route.dart';

void main() {
  group('isEphemeralSignal', () {
    test('SEMUA tipe reliable saat ephemeral dimatikan (regresi connect)', () {
      // 2026-10-05: candidate ephemeral DIMATIKAN karena broadcast tidak sampai
      // ke peer (call menghubungkan lama). Semua sinyal lewat DB.
      for (final t in [
        'candidate',
        'offer',
        'answer',
        'bye',
        'camera',
        'watch_request',
        'watch_offer',
        'watch_answer',
        'watch_candidate',
        'watch_state',
      ]) {
        expect(isEphemeralSignal(t), isFalse, reason: '$t harus reliable');
      }
    });
  });

  group('buildEphemeralEnvelope', () {
    test('membuat bid unik + payload diteruskan', () {
      final env = buildEphemeralEnvelope(
        fromUid: 'u1',
        type: 'candidate',
        payload: {
          'candidate': {'candidate': 'cand:1', 'sdpMid': '0'},
        },
        seq: 3,
        micros: 1000,
      );
      expect(env['from'], 'u1');
      expect(env['type'], 'candidate');
      expect(env['bid'], '1000-3');
      expect((env['payload'] as Map)['candidate'], isA<Map>());
    });

    test('payload null → map kosong (bukan crash)', () {
      final env = buildEphemeralEnvelope(
        fromUid: null,
        type: 'candidate',
        seq: 0,
        micros: 0,
      );
      expect(env['payload'], isEmpty);
      expect(env['from'], isNull);
    });
  });

  group('decodeEphemeralEnvelope', () {
    test('ephemeral dimatikan → SEMUA broadcast ditolak (defense)', () {
      // Saat kEphemeralSignalTypes kosong, tidak ada tipe yang lolos decode —
      // jadi jalur broadcast tak bisa menyuntik sinyal apa pun.
      for (final t in ['candidate', 'offer']) {
        final signal = decodeEphemeralEnvelope({
          'payload': {
            'from': 'other',
            'type': t,
            'bid': '42-7',
            'payload': {},
          },
        }, myUid: 'me');
        expect(signal, isNull, reason: '$t harus ditolak saat ephemeral OFF');
      }
    });

    test('envelope dari diri sendiri → null', () {
      final signal = decodeEphemeralEnvelope({
        'payload': {'from': 'me', 'type': 'candidate', 'payload': {}},
      }, myUid: 'me');
      expect(signal, isNull);
    });

    test('payload hilang / tipe kosong → null', () {
      expect(decodeEphemeralEnvelope({}, myUid: 'me'), isNull);
      expect(
        decodeEphemeralEnvelope({
          'payload': {'from': 'other', 'type': ''},
        }, myUid: 'me'),
        isNull,
      );
    });
  });
}
