/// Utilitas mention `@` — murni Dart (tanpa Flutter) supaya mudah di-test.
///
/// Aturan bentuk (dikunci di UI):
/// - Token mention = `@` + nickname apa adanya (nickname boleh mengandung
///   spasi, panjang 3–20 char). Saat user memilih dari daftar, teks
///   `@Nama ` disisipkan utuh, jadi pengguna tidak perlu mengetik spasi.
/// - Deteksi token aktif (untuk autocomplete) BERHENTI di whitespace/baris
///   baru → begitu user mengetik spasi, panel tertutup.
/// - `@all` / `@everyone` hanya dianggap mention bila [allowAll] true
///   (grup/private room oleh owner/admin). Di global room selalu false.
class Mention {
  final String uid;
  final String name;
  const Mention({required this.uid, required this.name});

  Map<String, dynamic> toMap() => {'uid': uid, 'name': name};

  factory Mention.fromMap(Map<dynamic, dynamic> m) =>
      Mention(uid: '${m['uid'] ?? ''}', name: '${m['name'] ?? ''}');

  static List<Mention> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Mention>[];
    for (final e in raw) {
      if (e is Map) {
        final m = Mention.fromMap(e);
        if (m.uid.isNotEmpty) out.add(m);
      }
    }
    return out;
  }

  static List<Map<String, dynamic>> listTo(List<Mention> list) =>
      list.map((m) => m.toMap()).toList();

  @override
  bool operator ==(Object other) =>
      other is Mention && other.uid == uid && other.name == name;

  @override
  int get hashCode => Object.hash(uid, name);

  @override
  String toString() => 'Mention($uid,$name)';
}

/// Token massal yang dikenali (urutan tidak penting).
const List<String> mentionAllTokens = ['@all', '@everyone'];

/// Batas panjang query aktif — cegah pemindaian teks raksasa.
const int _maxQueryLen = 40;

bool _isBoundary(String c) {
  if (c.isEmpty) return true;
  final code = c.codeUnitAt(0);
  final isDigit = code >= 0x30 && code <= 0x39;
  final isUpper = code >= 0x41 && code <= 0x5A;
  final isLower = code >= 0x61 && code <= 0x7A;
  final isUnderscore = c == '_';
  return !(isDigit || isUpper || isLower || isUnderscore);
}

/// Token `@…` yang sedang diketik pada posisi [cursor].
/// Null bila kursor tidak berada di dalam sebuah token mention.
({int start, String query})? activeMentionToken(String text, int cursor) {
  if (cursor <= 0 || cursor > text.length) return null;
  var i = cursor - 1;
  while (i >= 0) {
    final c = text[i];
    if (c == '@') {
      if (i == 0 || _isBoundary(text[i - 1])) {
        final q = text.substring(i + 1, cursor);
        if (q.contains('\n') || q.length > _maxQueryLen) return null;
        return (start: i, query: q);
      }
      return null;
    }
    // Spasi / baris baru mengakhiri token → panel ditutup.
    if (c == '\n' || c.trim().isEmpty) return null;
    i--;
  }
  return null;
}

/// Filter kandidat untuk [query]: prioritas prefix nama, lalu prefix salah
/// satu kata, lalu substring. Dedup per uid, maksimum [limit].
List<Mention> filterCandidates(
  List<Mention> all,
  String query, {
  int limit = 8,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return all.take(limit).toList();
  }
  final prefix = <Mention>[];
  final wordPrefix = <Mention>[];
  final contains = <Mention>[];
  final seen = <String>{};
  for (final m in all) {
    final name = m.name.toLowerCase();
    if (!seen.add(m.uid)) continue;
    if (name.startsWith(q)) {
      prefix.add(m);
    } else if (name.split(RegExp(r'\s+')).any((w) => w.startsWith(q))) {
      wordPrefix.add(m);
    } else if (name.contains(q)) {
      contains.add(m);
    }
  }
  return [...prefix, ...wordPrefix, ...contains].take(limit).toList();
}

/// Resolusi teks pesan → daftar mention ber-uid (dedup).
///
/// [candidates] = kandidat yang sah di konteks (lawan chat / anggota grup /
/// user online room). Nama diurutkan terpanjang lebih dulu supaya
/// "Budi Santoso" menang atas "Budi".
///
/// [allowAll] true → token `@all`/`@everyone` di-ekspansi menjadi
/// [allExpansion] (owner/admin grup). Bila false, token massal diabaikan
/// total (tanpa uid, tanpa highlight, tanpa push) — perilaku global room.
List<Mention> parseMentions(
  String text, {
  required List<Mention> candidates,
  bool allowAll = false,
  List<Mention> allExpansion = const [],
}) {
  if (text.isEmpty) return const [];
  final lower = text.toLowerCase();
  final out = <Mention>[];
  final seen = <String>{};
  final consumed = <({int start, int end})>[];

  bool free(int s, int e) {
    for (final r in consumed) {
      if (s < r.end && e > r.start) return false;
    }
    return true;
  }

  void add(Mention m, int s, int e) {
    if (m.uid.isEmpty || !seen.add(m.uid)) return;
    out.add(m);
    consumed.add((start: s, end: e));
  }

  final sorted = [...candidates]
    ..sort((a, b) => b.name.length.compareTo(a.name.length));

  for (final c in sorted) {
    if (c.name.isEmpty) continue;
    final token = '@${c.name}'.toLowerCase();
    var idx = 0;
    while (idx < lower.length) {
      final found = lower.indexOf(token, idx);
      if (found < 0) break;
      final end = found + token.length;
      final beforeOk = found == 0 || _isBoundary(text[found - 1]);
      final afterOk = end >= text.length || _isBoundary(text[end]);
      if (beforeOk && afterOk && free(found, end)) {
        add(c, found, end);
        break;
      }
      idx = end;
    }
  }

  if (allowAll && allExpansion.isNotEmpty) {
    for (final t in mentionAllTokens) {
      final ti = lower.indexOf(t);
      if (ti < 0) continue;
      final end = ti + t.length;
      final beforeOk = ti == 0 || _isBoundary(text[ti - 1]);
      final afterOk = end >= text.length || _isBoundary(text[end]);
      if (beforeOk && afterOk && free(ti, end)) {
        for (final m in allExpansion) {
          add(m, ti, end);
        }
        break;
      }
    }
  }

  return out;
}

/// True bila [text] memuat token massal `@all`/`@everyone` (boundary-aware).
bool hasAllToken(String text) {
  final lower = text.toLowerCase();
  for (final t in mentionAllTokens) {
    final i = lower.indexOf(t);
    if (i < 0) continue;
    final end = i + t.length;
    final beforeOk = i == 0 || _isBoundary(text[i - 1]);
    final afterOk = end >= text.length || _isBoundary(text[end]);
    if (beforeOk && afterOk) return true;
  }
  return false;
}
