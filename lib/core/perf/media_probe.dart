import 'perf_probe.dart';

/// Instrumentasi MEDIA (video/audio) untuk audit respons & leak (Fase 1).
///
/// Semua di-gate [PerfProbe.measuring] → **no-op total di produksi** (tanpa
/// Stopwatch, tanpa counter). Dipakai:
///  - `video.tap→open`  : tap bubble video → viewer siap (frame pertama).
///  - `video.tap→play`  : tap → `play()` benar-benar dipanggil.
///  - `voice.tap→play`  : tap voice → `play()` benar-benar dipanggil.
///  - counter `videoCtrlLive` / `audioPlayerLive` : deteksi controller/player
///    yang tak dilepas (leak) setelah keluar layar.
class MediaProbe {
  MediaProbe._();

  static int videoCtrlLive = 0;
  static int audioPlayerLive = 0;
  static int videoPlayerScreenOpens = 0;

  /// Mulai stopwatch (null bila probe off → nol biaya).
  static Stopwatch? start() => PerfProbe.measuring ? (Stopwatch()..start()) : null;

  /// Selesai → catat ke [PerfProbe] (recap muncul saat app di-background).
  static void stop(String key, Stopwatch? sw) {
    if (sw == null) return;
    sw.stop();
    PerfProbe.record(key, sw.elapsed);
  }

  static void videoCtrlOpened() {
    if (PerfProbe.measuring) videoCtrlLive++;
  }

  static void videoCtrlClosed() {
    if (PerfProbe.measuring) videoCtrlLive--;
  }

  static void audioPlayerOpened() {
    if (PerfProbe.measuring) audioPlayerLive++;
  }

  static void audioPlayerClosed() {
    if (PerfProbe.measuring) audioPlayerLive--;
  }

  static void videoScreenOpened() {
    if (PerfProbe.measuring) videoPlayerScreenOpens++;
  }

  /// Baris recap untuk [PerfProbe.report].
  static String label() =>
      'videoCtrlLive=$videoCtrlLive audioPlayerLive=$audioPlayerLive '
      'videoScreens=$videoPlayerScreenOpens';
}
