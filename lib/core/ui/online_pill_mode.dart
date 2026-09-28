/// Mode kapsul di halaman Online — bergantian tiap 1 jam antara
/// Timeline dan Global Room.
enum OnlinePillMode {
  /// Klik → pindah ke TAB Timeline.
  timeline,

  /// Klik → buka Global Room (perilaku lama).
  globalRoom,
}

/// Mode aktif berdasarkan jam dinding. Bergantian TEPAT tiap pergantian jam
/// (jam genap = Timeline, jam ganjil = Global Room) sehingga kapsul berubah
/// otomatis setiap 1 jam sekali. Murni & testable.
OnlinePillMode onlinePillModeFor(DateTime now) =>
    now.hour.isEven ? OnlinePillMode.timeline : OnlinePillMode.globalRoom;

/// Detik menuju pergantian jam berikutnya — dipakai timer agar kapsul
/// berganti tepat saat jam berubah (bukan polling tiap detik).
Duration untilNextHour(DateTime now) {
  final next = DateTime(now.year, now.month, now.day, now.hour)
      .add(const Duration(hours: 1));
  final d = next.difference(now);
  // Minimal 1 detik supaya tidak ada loop timer 0-durasi.
  return d < const Duration(seconds: 1) ? const Duration(seconds: 1) : d;
}
