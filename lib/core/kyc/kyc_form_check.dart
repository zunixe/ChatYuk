import 'kyc_capture.dart';
import 'ktp_ocr.dart';
import 'nik.dart';

enum KycFormError { photos, name, nik, birth, birthMismatch, underage }

enum KycFormWarning { nikMismatch, nameMismatch, genderMismatch }

/// Hasil validasi form KYC: error memblokir kirim; warning hanya ditandai
/// (ikut dikirim di `checks` untuk admin) karena OCR bisa salah baca.
class KycFormCheck {
  final KycFormError? error;
  final List<KycFormWarning> warnings;
  final Map<String, dynamic> checks;

  const KycFormCheck(this.error, this.warnings, this.checks);

  static const minAge = 17;
  static const nameThreshold = 0.8;

  static KycFormCheck evaluate({
    required String nik,
    required String name,
    required DateTime? birth,
    required KycDocCapture? doc,
    required KycSelfieCapture? selfie,
    required String? profileGender,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final info = Nik.parse(nik, now: today);
    final ocr = doc?.ocr ?? KtpOcrResult.empty;
    final warnings = <KycFormWarning>[];

    if (ocr.nik != null && info != null && ocr.nik != nik) {
      warnings.add(KycFormWarning.nikMismatch);
    }
    double? nameScore;
    if (ocr.name != null && name.trim().length >= 3) {
      nameScore = nameSimilarity(name, ocr.name!);
      if (nameScore < nameThreshold) warnings.add(KycFormWarning.nameMismatch);
    }
    if (info != null &&
        (profileGender == 'female' || profileGender == 'male') &&
        info.female != (profileGender == 'female')) {
      warnings.add(KycFormWarning.genderMismatch);
    }

    final birthMatch = info != null && birth != null && _sameDay(info.birthDate, birth);

    KycFormError? error;
    if (doc == null || selfie == null) {
      error = KycFormError.photos;
    } else if (info == null) {
      error = KycFormError.nik;
    } else if (name.trim().length < 3) {
      error = KycFormError.name;
    } else if (birth == null) {
      error = KycFormError.birth;
    } else if (!birthMatch) {
      error = KycFormError.birthMismatch;
    } else if (Nik.ageOn(birth, today) < minAge) {
      error = KycFormError.underage;
    }

    return KycFormCheck(error, warnings, {
      'v': 1,
      'nik_valid': info != null,
      'nik_female': info?.female,
      'birth_match_nik': birthMatch,
      'ocr_ktp': ocr.looksLikeKtp,
      'ocr_auto': doc?.auto ?? false,
      'ocr': ocr.toJson(),
      'nik_match_ocr': ocr.nik == null ? null : ocr.nik == nik,
      'name_score': nameScore == null
          ? null
          : double.parse(nameScore.toStringAsFixed(2)),
      'gender_match_profile': info == null ||
              (profileGender != 'female' && profileGender != 'male')
          ? null
          : info.female == (profileGender == 'female'),
      'doc_quality': doc?.quality?.toJson(),
      'live': selfie?.live ?? false,
      'live_steps': selfie?.steps ?? const <String>[],
    });
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
