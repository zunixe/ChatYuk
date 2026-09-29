import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/call/watch_policy.dart';

/// Mengunci perbaikan "suara call sempat hilang" (2026-09-28).
///
/// Akar: admin mengirim `watch_request` tiap 3 dtk; peserta menutup &
/// membuat ulang pc watch tiap ~8 dtk → audio putus sesaat. Test ini
/// memastikan: pc watch yang SEHAT tidak pernah di-rebuild, dan admin
/// berhenti minta saat sudah tersambung / sedang handshake.
void main() {
  group('decideWatchReply (sisi peserta)', () {
    test('pc sehat → sendState (TIDAK rebuild)', () {
      expect(
        decideWatchReply(
          isForMe: true,
          hasLocalMedia: true,
          isAdminWatcher: true,
          alreadyRepliedRecently: true, // pun pasca-throttle
          hasHealthyPc: true,
        ),
        WatchReplyAction.sendState,
      );
    });

    test('pc sehat & belum pernah balas → tetap sendState', () {
      expect(
        decideWatchReply(
          isForMe: true,
          hasLocalMedia: true,
          isAdminWatcher: true,
          alreadyRepliedRecently: false,
          hasHealthyPc: true,
        ),
        WatchReplyAction.sendState,
      );
    });

    test('pc belum ada & belum balas baru → rebuildOffer', () {
      expect(
        decideWatchReply(
          isForMe: true,
          hasLocalMedia: true,
          isAdminWatcher: true,
          alreadyRepliedRecently: false,
          hasHealthyPc: false,
        ),
        WatchReplyAction.rebuildOffer,
      );
    });

    test('pc mati tapi baru balas → ignore (throttle)', () {
      expect(
        decideWatchReply(
          isForMe: true,
          hasLocalMedia: true,
          isAdminWatcher: true,
          alreadyRepliedRecently: true,
          hasHealthyPc: false,
        ),
        WatchReplyAction.ignore,
      );
    });

    test('bukan admin → ignore (anti intip)', () {
      expect(
        decideWatchReply(
          isForMe: true,
          hasLocalMedia: true,
          isAdminWatcher: false,
          alreadyRepliedRecently: false,
          hasHealthyPc: false,
        ),
        WatchReplyAction.ignore,
      );
    });

    test('belum ada media lokal → ignore', () {
      expect(
        decideWatchReply(
          isForMe: true,
          hasLocalMedia: false,
          isAdminWatcher: true,
          alreadyRepliedRecently: false,
          hasHealthyPc: false,
        ),
        WatchReplyAction.ignore,
      );
    });

    test('bukan untuk kita → ignore', () {
      expect(
        decideWatchReply(
          isForMe: false,
          hasLocalMedia: true,
          isAdminWatcher: true,
          alreadyRepliedRecently: false,
          hasHealthyPc: false,
        ),
        WatchReplyAction.ignore,
      );
    });

    test('pc basi (belum connect >20s) → hasHealthyPc=false → rebuild', () {
      // Caller menghitung hasHealthyPc=false untuk pc basi; pastikan hasilnya
      // rebuild (bukan sendState) supaya tidak deadlock.
      expect(
        decideWatchReply(
          isForMe: true,
          hasLocalMedia: true,
          isAdminWatcher: true,
          alreadyRepliedRecently: false,
          hasHealthyPc: false,
        ),
        WatchReplyAction.rebuildOffer,
      );
    });
  });

  group('shouldRequestWatch (sisi admin)', () {
    test('sudah connected → tidak minta', () {
      expect(shouldRequestWatch(connected: true, negotiating: false), isFalse);
    });

    test('sedang handshake → tahan (jangan spam)', () {
      expect(shouldRequestWatch(connected: false, negotiating: true), isFalse);
    });

    test('belum ada & tidak handshake → minta', () {
      expect(shouldRequestWatch(connected: false, negotiating: false), isTrue);
    });
  });

  group('watchRequestDelay (kadens permintaan)', () {
    test('3 percobaan pertama cepat (1,5 dtk)', () {
      expect(watchRequestDelay(0), const Duration(milliseconds: 1500));
      expect(watchRequestDelay(1), const Duration(milliseconds: 1500));
      expect(watchRequestDelay(2), const Duration(milliseconds: 1500));
    });

    test('percobaan ke-4+ kembali 3 dtk (anti spam peserta)', () {
      expect(watchRequestDelay(3), const Duration(seconds: 3));
      expect(watchRequestDelay(10), const Duration(seconds: 3));
    });
  });

  /// Mengunci perbaikan "putus tengah jalan di monitor chat" (2026-09-29).
  ///
  /// Akar: admin mengirim `watch_request` TANPA `to` di dalam loop per
  /// peserta → 2 sinyal identik per siklus, tiap peserta memproses keduanya
  /// → pc/offer watch dobel → audio-video di monitor turun-bangun.
  group('isWatchRequestForMe (targeting watch_request)', () {
    test('bertarget ke kita → true', () {
      expect(isWatchRequestForMe(to: 'me', me: 'me'), isTrue);
    });

    test('bertarget ke peserta LAIN → false (jangan dobel-proses)', () {
      expect(isWatchRequestForMe(to: 'other', me: 'me'), isFalse);
    });

    test('tanpa `to` (sinyal versi lama) → true (kompat)', () {
      expect(isWatchRequestForMe(to: null, me: 'me'), isTrue);
    });
  });
}
