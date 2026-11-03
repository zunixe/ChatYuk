/// Validasi struktur NIK (Nomor Induk Kependudukan) KTP Indonesia.
///
/// Format 16 digit: PP KK CC DD MM YY SSSS
///  - PP   kode provinsi (daftar resmi Kemendagri)
///  - KK   kode kab/kota (≠ 00), CC kode kecamatan (≠ 00)
///  - DD   tanggal lahir; perempuan +40 (41–71)
///  - MM   bulan lahir, YY dua digit tahun lahir
///  - SSSS nomor urut (≠ 0000)
///
/// Validasi ini menolak NIK karangan/salah ketik, TIDAK membuktikan NIK
/// terdaftar di Dukcapil (itu butuh penyedia eKYC berlisensi).
class NikInfo {
  final String nik;
  final int provinceCode;
  final DateTime birthDate;
  final bool female;

  const NikInfo({
    required this.nik,
    required this.provinceCode,
    required this.birthDate,
    required this.female,
  });
}

class Nik {
  Nik._();

  /// Kode provinsi resmi (termasuk pemekaran Papua 2022).
  static const Set<int> provinces = {
    11, 12, 13, 14, 15, 16, 17, 18, 19, 21, //
    31, 32, 33, 34, 35, 36, //
    51, 52, 53, //
    61, 62, 63, 64, 65, //
    71, 72, 73, 74, 75, 76, //
    81, 82, //
    91, 92, 93, 94, 95, 96,
  };

  /// Rapikan hasil OCR/ketikan → hanya digit. Huruf yang sering tertukar
  /// dengan angka di font KTP dikoreksi (O→0, I/l/|→1, Z→2, S→5, B→8, G→6).
  static String normalize(String raw) {
    const map = {
      'O': '0', 'o': '0', 'D': '0', 'Q': '0', //
      'I': '1', 'l': '1', '|': '1', 'i': '1', 'L': '1', //
      'Z': '2', 'z': '2', 'S': '5', 's': '5', //
      'B': '8', 'G': '6', 'b': '6', 'T': '7', '?': '7',
    };
    final out = StringBuffer();
    for (final ch in raw.split('')) {
      if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
        out.write(ch);
      } else if (map.containsKey(ch)) {
        out.write(map[ch]);
      }
    }
    return out.toString();
  }

  /// Parse NIK 16 digit. null = struktur tidak valid.
  static NikInfo? parse(String nik, {DateTime? now}) {
    if (!RegExp(r'^\d{16}$').hasMatch(nik)) return null;
    final prov = int.parse(nik.substring(0, 2));
    if (!provinces.contains(prov)) return null;
    if (nik.substring(2, 4) == '00' || nik.substring(4, 6) == '00') {
      return null;
    }
    if (nik.substring(12) == '0000') return null;
    var day = int.parse(nik.substring(6, 8));
    final female = day > 40;
    if (female) day -= 40;
    final month = int.parse(nik.substring(8, 10));
    final yy = int.parse(nik.substring(10, 12));
    if (day < 1 || day > 31 || month < 1 || month > 12) return null;
    final today = now ?? DateTime.now();
    final year = yy > today.year % 100 ? 1900 + yy : 2000 + yy;
    final birth = DateTime(year, month, day);
    // Tanggal tak ada (mis. 31 Februari) → DateTime menggeser bulan.
    if (birth.month != month || birth.day != day) return null;
    if (birth.isAfter(today)) return null;
    return NikInfo(
      nik: nik,
      provinceCode: prov,
      birthDate: birth,
      female: female,
    );
  }

  /// Umur penuh (tahun) pada [now].
  static int ageOn(DateTime birth, DateTime now) {
    var age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return age;
  }
}
