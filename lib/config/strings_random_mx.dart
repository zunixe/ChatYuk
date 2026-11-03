part of 'strings.dart';

/// String fitur Random Video Call ("Match Nearby") — ID + EN.
mixin SRandomMx {
  /// Kontrak dari class S (mixin tak punya field).
  bool get isId;
  String get randomTitle => isId ? 'Video Random' : 'Random Video';
  String get randomSearching =>
      isId ? 'Mencari di sekitar…' : 'Matching nearby…';
  String get randomConnecting => isId ? 'Menyambungkan…' : 'Connecting…';
  String randomWaitingCount(int n) =>
      isId ? '$n orang sedang mencari' : '$n people searching';
  String get randomIdleHint => isId
      ? 'Tekan Match untuk video call dengan orang di sekitar.'
      : 'Tap Match to video call someone nearby.';
  String get randomEmptyPool => isId
      ? 'Belum ada yang mencari sekarang. Tunggu sebentar atau coba lagi.'
      : 'Nobody is searching right now. Wait a moment or try again.';
  String get btnRandomMatch => 'Match';
  String get btnRandomCancel => isId ? 'Batal' : 'Cancel';
  String get randomGenderAll => isId ? 'Semua' : 'All';
  String get randomGenderMale => isId ? 'Cowok' : 'Male';
  String get randomGenderFemale => isId ? 'Cewek' : 'Female';
  String get randomFilterTitle => isId ? 'Cari' : 'Find';
  String get quickMenuRandomVideo =>
      isId ? 'Video Random' : 'Random Video';

  // ── Saat video call ──
  String get randomCallNext => 'Next';
  String get randomCallEnd => isId ? 'Akhiri' : 'End';
  String get randomCallSearchingAgain =>
      isId ? 'Mencari orang baru…' : 'Finding someone new…';
  String randomCallPartnerLeft(String name) =>
      isId ? '$name keluar' : '$name left';
  String get randomCallReport => isId ? 'Laporkan & Blokir' : 'Report & Block';
  String get randomCallReportDone =>
      isId ? 'Dilaporkan & diblokir' : 'Reported & blocked';
  String get randomCallReportTitle =>
      isId ? 'Laporkan orang ini?' : 'Report this person?';
  String get randomCallReportBody => isId
      ? 'Orang ini akan dilaporkan dan diblokir. Kalian tidak akan dipasangkan lagi.'
      : 'This person will be reported and blocked. You will not be matched again.';
  String get randomCallChat => isId ? 'Chat' : 'Chat';
  String get randomCallCameraOff => isId ? 'Kamera mati' : 'Camera off';
  String get randomYou => isId ? 'Kamu' : 'You';
  String randomDuration(String d) => d;

  // ── Konfirmasi keluar (back) dari layar call ──
  // Keluar = panggilan benar-benar diakhiri (dulu back diam-diam
  // membiarkan call jalan di background → membingungkan).
  String get randomCallExitTitle =>
      isId ? 'Keluar dari panggilan?' : 'Leave the call?';
  String get randomCallExitBody => isId
      ? 'Kalau keluar, panggilan ini akan diakhiri.'
      : 'If you leave, this call will end.';
  String get randomCallExitYes => isId ? 'Akhiri panggilan' : 'End call';

  // ── Riwayat ──
  String get randomHistoryTitle =>
      isId ? 'Riwayat Video Random' : 'Random Video History';
  String get randomHistoryEmpty =>
      isId ? 'Belum ada riwayat' : 'No history yet';
  String get randomHistoryEnd => isId ? 'Sudah semua' : "That's all for now";
  String get randomHistoryMissed => isId ? 'Tidak tersambung' : 'Not connected';
  String randomHistoryTime(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return '$hh:$mm';
    if (diff == 1) return isId ? 'Kemarin $hh:$mm' : 'Yesterday $hh:$mm';
    final d = local.day.toString().padLeft(2, '0');
    return '${local.year == now.year ? '$d/${local.month}' : '$d/${local.month}/${local.year}'} $hh:$mm';
  }

  // ── Error ──
  String get randomErrFeature =>
      isId ? 'Fitur belum aktif' : 'Feature is not available yet';
  String get randomErrInCall =>
      isId ? 'Kamu sedang dalam panggilan lain' : 'You are in another call';
  String get randomErrRegistered => isId
      ? 'Daftar dulu untuk memakai fitur ini'
      : 'Register to use this feature';
  String get randomErrGeneric =>
      isId ? 'Gagal memulai. Coba lagi.' : 'Could not start. Try again.';

  // ── Lawan jenis otomatis + biaya match ──
  String get randomOppositeOnly =>
      isId ? 'Dipasangkan dengan lawan jenis' : 'Matched with the opposite gender';
  String randomOppositeHint(String g) => isId
      ? 'Kamu akan dipasangkan dengan $g'
      : 'You will be matched with $g';
  String get randomNeedCoinTitle =>
      isId ? 'YukCoin tidak cukup' : 'Not enough YukCoin';
  String randomBonusNotUsable(int bonus, int need) => isId
      ? 'YukCoin bonus ($bonus) tidak bisa dipakai untuk match & video call. Butuh minimal $need YukCoin hasil isi ulang.'
      : 'Bonus YukCoin ($bonus) can\'t be used for match & video calls. You need at least $need topped-up YukCoin.';
  String randomNeedCoinBody(int fee) => isId
      ? 'Match memotong $fee YukCoin saat kamu dapat pasangan. Isi YukCoin dulu, ya.'
      : 'A match costs $fee YukCoin — charged only when you get a match. Top up first.';

  // ── Koin habis di tengah panggilan ──
  String get callNoCoinTitle => isId ? 'YukCoin habis' : 'Out of YukCoin';
  String callNoCoinBody(int perMin) => isId
      ? 'Panggilan butuh $perMin YukCoin/menit. Lanjutkan panggilan?'
      : 'This call costs $perMin YukCoin/min. Continue the call?';
  String get callNoCoinContinue => isId ? 'Lanjutkan' : 'Continue';
  String get callNoCoinEnd => isId ? 'Akhiri' : 'End call';
  String get callNoCoinTopup => isId ? 'Isi YukCoin' : 'Top up';
  String get callTopupWaiting => isId
      ? 'Menunggu pembayaran Google Play selesai…'
      : 'Waiting for the Google Play payment to finish…';
  String get callTopupFailed => isId
      ? 'Pembayaran gagal atau dibatalkan.'
      : 'Payment failed or was cancelled.';
  String get callNoCoinStillEmpty => isId
      ? 'YukCoin masih belum cukup'
      : 'Still not enough YukCoin';

  // ── Batas call gratis harian habis (female) ──
  String get callFreeLimitTitle => isId
      ? 'Batas gratis habis'
      : 'Free limit reached';
  String callFreeLimitBody(int limitMin) => isId
      ? 'Kamu sudah memakai $limitMin menit call gratis hari ini. Coba lagi besok.'
      : 'You have used your $limitMin free call minutes today. Try again tomorrow.';

  // ── Countdown gratis 30 detik awal call match ──
  String randomCallFreeLeft(int sec) =>
      isId ? 'Gratis ${sec}s' : 'Free ${sec}s';
}
