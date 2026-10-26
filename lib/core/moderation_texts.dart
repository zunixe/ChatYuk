import '../config/strings.dart';

/// Teks hasil "Ajukan jadi Moderator" — dipisah dari widget supaya bisa
/// diuji tanpa membangun UI.
///
/// Regresi yang dijaga: dulu `already_moderator` (SUDAH moderator) dan
/// `already_pending` (menunggu) sama-sama ditampilkan sebagai
/// "lamaran menunggu", sehingga admin/moderator aktif merasa lamarannya
/// gagal padahal dia sudah berwenang.
String moderationApplyMessage(Map<String, dynamic> res, S s) {
  if (res['already_moderator'] == true) return s.moderationAlreadyModerator;
  if (res['already_pending'] == true) return s.moderationApplyPending;

  switch (res['error']) {
    case 'account_too_new':
      return s.moderationApplyNeedDays((res['min_days'] as num?)?.toInt() ?? 7);
    case 'not_enough_messages':
      return s.moderationApplyNeedMsgs(
        (res['need'] as num?)?.toInt() ?? 50,
        (res['have'] as num?)?.toInt() ?? 0,
      );
  }

  if (res['ok'] == true) return s.moderationApplySent;
  return s.errGeneric;
}

/// Negara asal efektif: override sesi (hasil pilih user) di atas nilai PROFIL.
///
/// Override kosong (`''`) berarti user/admin sudah mengosongkannya, jadi
/// nilai profil TIDAK boleh dipakai lagi (dulu `??=` mengunci null sehingga
/// nama negara tidak pernah tampil).
String effectiveHomeCountry({
  required String? override,
  required String? fromProfile,
}) {
  if (override != null) return override;
  return fromProfile ?? '';
}

/// Pesan penolakan ubah negara asal. Bila server menyertakan
/// `next_change_at`, sebutkan TANGGALNYA agar user tahu kapan bisa diubah.
String homeCountryCooldownMessage(Map<String, dynamic> res, S s) {
  final next = DateTime.tryParse('${res['next_change_at'] ?? ''}');
  if (next == null) return s.moderationCountryCooldown;
  final d = next.day.toString().padLeft(2, '0');
  final m = next.month.toString().padLeft(2, '0');
  return s.moderationCooldownUntil('$d/$m/${next.year}');
}
