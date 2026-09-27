import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/call/opus_sdp.dart';

/// SDP minimal mirip keluaran WebRTC (Opus pt=111 + telephone-event pt=101).
final _sdpSample = [
  'v=0',
  'o=- 123 2 IN IP4 127.0.0.1',
  's=-',
  't=0 0',
  'm=audio 9 UDP/TLS/RTP/SAVPF 111 101',
  'a=rtpmap:111 opus/48000/2',
  'a=rtcp-fb:111 transport-cc',
  'a=fmtp:111 minptime=10;useinbandfec=1',
  'a=rtpmap:101 telephone-event/8000',
  'a=fmtp:101 0-15',
].join('\r\n');

void main() {
  group('applyOpusLowLatencyPrefs', () {
    test('menambah parameter low-latency pada fmtp Opus', () {
      final out = applyOpusLowLatencyPrefs(_sdpSample);
      expect(out, contains('a=fmtp:111 '));
      expect(out, contains('useinbandfec=1'));
      expect(out, contains('usedtx=1'));
      expect(out, contains('minptime=10'));
      expect(out, contains('stereo=0'));
      expect(out, contains('maxaveragebitrate=32000'));
    });

    test('idempoten — dipanggil 2× hasilnya sama', () {
      final once = applyOpusLowLatencyPrefs(_sdpSample);
      final twice = applyOpusLowLatencyPrefs(once);
      expect(twice, once);
    });

    test('tidak menduplikasi kunci yang sudah ada', () {
      final out = applyOpusLowLatencyPrefs(_sdpSample);
      final fmtp = out
          .split(RegExp(r'\r\n|\n'))
          .firstWhere((l) => l.startsWith('a=fmtp:111'));
      expect('minptime'.allMatches(fmtp).length, 1);
      expect('useinbandfec'.allMatches(fmtp).length, 1);
    });

    test('m-line & kodek lain tidak diubah', () {
      final out = applyOpusLowLatencyPrefs(_sdpSample);
      expect(out, contains('m=audio 9 UDP/TLS/RTP/SAVPF 111 101'));
      expect(out, contains('a=rtpmap:101 telephone-event/8000'));
      expect(out, contains('a=fmtp:101 0-15'));
      expect(out, contains('a=rtcp-fb:111 transport-cc'));
    });

    test('SDP tanpa Opus dikembalikan apa adanya', () {
      const sdp = 'v=0\r\nm=audio 9 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000';
      expect(applyOpusLowLatencyPrefs(sdp), sdp);
    });

    test('string kosong aman', () {
      expect(applyOpusLowLatencyPrefs(''), '');
    });

    test('pertahankan parameter non-kita (apt=)', () {
      final sdp = [
        'm=audio 9 UDP/TLS/RTP/SAVPF 111',
        'a=rtpmap:111 opus/48000/2',
        'a=fmtp:111 apt=99;minptime=20',
      ].join('\r\n');
      final out = applyOpusLowLatencyPrefs(sdp);
      expect(out, contains('apt=99'));
      expect(out, contains('minptime=10'));
      expect(out, isNot(contains('minptime=20')));
    });

    test('fmtp sebelum rtpmap: rewrite valid di tempat', () {
      final sdp = [
        'm=audio 9 UDP/TLS/RTP/SAVPF 111',
        'a=fmtp:111 minptime=20',
        'a=rtpmap:111 opus/48000/2',
      ].join('\n');
      final out = applyOpusLowLatencyPrefs(sdp);
      expect(out, contains('a=fmtp:111 '));
      expect(out, contains('minptime=10'));
      // Rewrite di tempat (urutan asli dipertahankan) — tetap valid.
      expect(out.indexOf('a=fmtp:111'), lessThan(out.indexOf('a=rtpmap:111')));
    });
  });
}
