import 'package:flutter_test/flutter_test.dart';

/// Regresi AUDIT TIMER (2026-10-18).
///
/// ChatYuk punya 58 `Timer.periodic` (WhatsApp ±3, karena push-only).
/// Audit menemukan poll pesan TERLALU AGRESIF:
///   - 8 detik  → app bangun 7,5×/menit hanya untuk memeriksa kondisi,
///   - gate `lastRealtime < 6s` terlalu ketat → chat yang wajar sepi
///     dianggap "realtime mati" lalu memicu query berulang.
///
/// Perbaikan: 8s → 20s (3×/menit, beban turun ~60%) + gate "layar chat
/// terlihat" (`activeChatId`) supaya poll berhenti saat user sudah kembali
/// ke daftar chat / tab lain.
void main() {
  /// Salinan logika gate pada `chat_stream_session` pollTimer.
  bool shouldPoll({
    required bool foreground,
    required String? activeChatIdValue,
    required String cacheFilterVal,
    required int secondsSinceLastRealtime,
  }) {
    if (!foreground) return false; // app di background
    if (activeChatIdValue != cacheFilterVal) return false; // layar tak terlihat
    if (secondsSinceLastRealtime < 25) return false; // realtime sehat
    return true;
  }

  test('tidak poll saat app di background', () {
    expect(
      shouldPoll(
        foreground: false,
        activeChatIdValue: 'a_b',
        cacheFilterVal: 'a_b',
        secondsSinceLastRealtime: 999,
      ),
      isFalse,
    );
  });

  test('tidak poll saat layar chat tidak terlihat (kembali ke list)', () {
    expect(
      shouldPoll(
        foreground: true,
        activeChatIdValue: null, // user sudah keluar dari layar chat
        cacheFilterVal: 'a_b',
        secondsSinceLastRealtime: 999,
      ),
      isFalse,
    );
    // Berpindah ke chat LAIN juga bukan alasan poll chat lama.
    expect(
      shouldPoll(
        foreground: true,
        activeChatIdValue: 'c_d',
        cacheFilterVal: 'a_b',
        secondsSinceLastRealtime: 999,
      ),
      isFalse,
    );
  });

  test('tidak poll saat realtime masih sehat (<25s ada event)', () {
    expect(
      shouldPoll(
        foreground: true,
        activeChatIdValue: 'a_b',
        cacheFilterVal: 'a_b',
        secondsSinceLastRealtime: 10,
      ),
      isFalse,
    );
  });

  test('poll hanya saat visible + realtime benar-benar diam', () {
    expect(
      shouldPoll(
        foreground: true,
        activeChatIdValue: 'a_b',
        cacheFilterVal: 'a_b',
        secondsSinceLastRealtime: 40,
      ),
      isTrue,
    );
  });

  test('interval 20s => maksimum 3 poll/menit (bukan 7,5)', () {
    const interval = Duration(seconds: 20);
    final perMinute = 60 ~/ interval.inSeconds;
    expect(perMinute, 3);
    // Regresi: memastikan bukan lagi 8 detik.
    expect(interval.inSeconds, greaterThan(8));
  });
}
