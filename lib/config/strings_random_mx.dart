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
}
