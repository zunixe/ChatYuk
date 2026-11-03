import 'nik.dart';

/// Hasil baca OCR sebuah foto KTP (dari teks per-baris ML Kit).
class KtpOcrResult {
  /// NIK 16 digit yang strukturnya valid ([Nik.parse] lolos), atau null.
  final String? nik;
  final String? name;
  final DateTime? birthDate;

  /// true = "PEREMPUAN", false = "LAKI-LAKI", null = tak terbaca.
  final bool? female;

  /// Jumlah label khas KTP yang terbaca (PROVINSI, NIK, Nama, …).
  final int keywordHits;

  const KtpOcrResult({
    this.nik,
    this.name,
    this.birthDate,
    this.female,
    this.keywordHits = 0,
  });

  static const empty = KtpOcrResult();

  /// Cukup bukti ini KTP asli yang terbaca: label khas + NIK valid.
  bool get looksLikeKtp => nik != null && keywordHits >= 4;

  Map<String, dynamic> toJson() => {
        'nik': nik,
        'name': name,
        'birth_date': birthDate?.toIso8601String().substring(0, 10),
        'female': female,
        'keyword_hits': keywordHits,
      };
}

/// Parser teks KTP — murni (tanpa ML Kit) supaya bisa dites.
class KtpOcr {
  KtpOcr._();

  static const _keywords = [
    'PROVINSI',
    'KABUPATEN',
    'KOTA',
    'NIK',
    'NAMA',
    'LAHIR',
    'JENIS KELAMIN',
    'ALAMAT',
    'AGAMA',
    'PERKAWINAN',
    'PEKERJAAN',
    'KEWARGANEGARAAN',
    'BERLAKU',
    'GOL',
    'RT/RW',
    'KECAMATAN',
  ];

  static final _date = RegExp(r'(\d{2})\s*[-/.]\s*(\d{2})\s*[-/.]\s*(\d{4})');
  static final _nameLabel = RegExp(r'^\s*NAMA\s*[:;.]?\s*(.*)$');

  static KtpOcrResult parse(List<String> lines, {DateTime? now}) {
    final up = [for (final l in lines) l.toUpperCase().trim()];
    final joined = up.join('\n');

    var hits = 0;
    for (final k in _keywords) {
      if (joined.contains(k)) hits++;
    }

    return KtpOcrResult(
      nik: _findNik(up, now: now),
      name: _findName(up),
      birthDate: _findBirth(up),
      female: joined.contains('PEREMPUAN')
          ? true
          : (joined.contains('LAKI') ? false : null),
      keywordHits: hits,
    );
  }

  /// Cari kandidat 16 digit: utamakan baris berlabel NIK, lalu semua baris.
  static String? _findNik(List<String> up, {DateTime? now}) {
    String? scan(String line) {
      final cleaned = line.replaceFirst(RegExp(r'^\s*NIK\s*[:;.]?'), '');
      for (final tok in cleaned.split(RegExp(r'\s{2,}|:'))) {
        final compact = tok.replaceAll(' ', '');
        if (compact.length < 16 || compact.length > 18) continue;
        final digitCount = RegExp(r'\d').allMatches(compact).length;
        if (digitCount < 12) continue;
        final n = Nik.normalize(compact);
        if (n.length == 16 && Nik.parse(n, now: now) != null) return n;
      }
      return null;
    }

    for (final l in up.where((l) => l.contains('NIK'))) {
      final r = scan(l);
      if (r != null) return r;
    }
    for (final l in up) {
      final r = scan(l);
      if (r != null) return r;
    }
    return null;
  }

  /// Nama: nilai di baris "Nama : …"; bila kolom label & nilai terpisah
  /// (sering di ML Kit), ambil baris huruf berikutnya yang bukan label.
  static String? _findName(List<String> up) {
    for (var i = 0; i < up.length; i++) {
      final m = _nameLabel.firstMatch(up[i]);
      if (m == null) continue;
      final inline = _cleanName(m.group(1) ?? '');
      if (inline != null) return inline;
      for (var j = i + 1; j < up.length && j <= i + 2; j++) {
        if (_isLabel(up[j])) continue;
        final next = _cleanName(up[j]);
        if (next != null) return next;
      }
    }
    return null;
  }

  static bool _isLabel(String l) =>
      _keywords.any((k) => l.startsWith(k)) || l.startsWith('TEMPAT');

  static String? _cleanName(String raw) {
    final s = raw
        .replaceAll(RegExp(r"[^A-Z .,'\-]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.length < 3 || _isLabel(s)) return null;
    return s;
  }

  static DateTime? _findBirth(List<String> up) {
    // Utamakan baris "Tempat/Tgl Lahir"; tanggal lain di KTP = tgl terbit.
    final ordered = [
      ...up.where((l) => l.contains('LAHIR')),
      ...up.where((l) => !l.contains('LAHIR') && !l.contains('BERLAKU')),
    ];
    for (final l in ordered) {
      for (final m in _date.allMatches(l)) {
        final d = int.parse(m.group(1)!);
        final mo = int.parse(m.group(2)!);
        final y = int.parse(m.group(3)!);
        final dt = DateTime(y, mo, d);
        if (dt.day == d && dt.month == mo && y > 1900) return dt;
      }
    }
    return null;
  }
}

/// Kemiripan nama (0..1) — toleran salah baca OCR & gelar/singkatan.
double nameSimilarity(String a, String b) {
  String norm(String s) => s
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final x = norm(a);
  final y = norm(b);
  if (x.isEmpty || y.isEmpty) return 0;
  if (x == y) return 1;
  final ratio = 1 - _levenshtein(x, y) / (x.length > y.length ? x.length : y.length);
  // Semua kata nama input muncul di nama KTP (urutan bebas) = cocok.
  final tx = x.split(' ').toSet();
  final ty = y.split(' ').toSet();
  final contained = tx.every(ty.contains) || ty.every(tx.contains);
  return contained && ratio < 0.9 ? 0.9 : ratio;
}

int _levenshtein(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
          .reduce((p, q) => p < q ? p : q);
    }
    prev = cur;
  }
  return prev[b.length];
}
