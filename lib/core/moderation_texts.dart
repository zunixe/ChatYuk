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

/// Negara efektif: override sesi (hasil pilih user) di atas nilai PROFIL.
///
/// Sejak 2026-10-27 hanya ada SATU negara (`profiles.country`). Override
/// dipakai agar perubahan langsung terlihat tanpa menunggu profil di-refresh.
String effectiveCountry({
  required String? override,
  required String? fromProfile,
}) {
  if (override != null) return override;
  return fromProfile ?? '';
}

/// Pesan penolakan ubah negara (lock 7 hari). Bila server menyertakan
/// `next_change_at`, sebutkan TANGGALNYA agar user tahu kapan bisa diubah.
String countryCooldownMessage(Map<String, dynamic> res, S s) {
  final next = DateTime.tryParse('${res['next_change_at'] ?? ''}');
  if (next == null) return s.moderationCountryCooldown;
  final d = next.day.toString().padLeft(2, '0');
  final m = next.month.toString().padLeft(2, '0');
  return s.moderationCooldownUntil('$d/$m/${next.year}');
}

/// Tanggal `dd/MM/yyyy` dari string ISO, atau null bila tak valid.
String? moderationDate(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return null;
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  return '$day/$month/${d.year}';
}

/// Info SETELAH negara berhasil diubah: kapan bisa diubah lagi, dan (bila
/// user tadinya moderator) jabatan mana yang dicabut.
String countryChangedMessage(Map<String, dynamic> res, S s) {
  final next = moderationDate('${res['next_change_at'] ?? ''}');
  final revoked = res['revoked_moderator_for'];
  final list = revoked is List ? [for (final e in revoked) '$e'] : const <String>[];

  if (list.isNotEmpty) {
    return s.moderationRevokedOnCountryChange(list.join(', '));
  }
  if (next == null) return s.moderationCountrySaved;
  return s.moderationCountryChangedUntil(next);
}

/// Teks popup PERSETUJUAN pindah negara. [moderating] = negara yang sedang
/// dimoderasi user (kosong bila bukan moderator).
String countryChangeConfirmBody({
  required String from,
  required String to,
  required String moderating,
  required String lockUntil,
  required S s,
}) {
  if (moderating.isEmpty) {
    return s.moderationChangeCountryWarn(to, lockUntil);
  }
  return s.moderationChangeCountryRevokeWarn(moderating, to, lockUntil);
}
