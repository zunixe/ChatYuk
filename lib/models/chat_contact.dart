import 'dart:convert';

/// Kontak yang dibagikan di pesan (type `contact`), disimpan di kolom
/// `contact` (`private_messages` & `messages`) — dua bentuk:
///
///  - kirim kontak **ChatYuk**: `{"t":"user","u":"<uid>"}` → HANYA id, supaya
///    tak ada data pribadi yang dibekukan di pesan; penerima me-resolve nama/
///    foto sendiri (menghormati privasi & selalu terbaru).
///  - kirim kontak **HP**: `{"t":"phone","n":"Nama","p":["+62…", …]}` → nama +
///    nomor apa adanya dari buku kontak perangkat.
///
/// Ikut cache pesan lokal (`MessageModel.toMap/fromMap`) → bubble kontak
/// tampil lengkap di frame pertama tanpa fetch.
class ChatContact {
  /// `'user'` (pengguna ChatYuk) atau `'phone'` (buku kontak perangkat).
  final String kind;

  /// Diisi bila [kind] == 'user'.
  final String uid;

  /// Nama tampilan. Untuk 'user' hanya dipakai LOKAL (teks pesan/optimistik) —
  /// tidak ikut payload. Untuk 'phone' = nama dari buku kontak.
  final String name;

  /// Nomor kontak HP (max [maxPhones]) — kosong untuk [kind] == 'user'.
  final List<String> phones;

  static const int maxPhones = 5;
  static const int maxNameLen = 120;

  const ChatContact({
    required this.kind,
    this.uid = '',
    this.name = '',
    this.phones = const [],
  });

  bool get isUser => kind == 'user';
  bool get isPhone => kind == 'phone';

  factory ChatContact.user(String uid, {String name = ''}) =>
      ChatContact(kind: 'user', uid: uid, name: name);

  factory ChatContact.phone(String name, List<String> phones) => ChatContact(
    kind: 'phone',
    name: name.length > maxNameLen ? name.substring(0, maxNameLen) : name,
    phones: [
      for (final p in phones)
        if (p.trim().isNotEmpty) p.trim(),
    ].take(maxPhones).toList(),
  );

  /// Toleran: Map (realtime/PostgREST/cache) atau string JSON. null bila tidak
  /// valid (bubble jatuh ke teks biasa).
  static ChatContact? tryParse(dynamic raw) {
    try {
      final m = raw is String ? jsonDecode(raw) : raw;
      if (m is! Map) return null;
      final t = '${m['t'] ?? ''}';
      if (t == 'user') {
        final u = '${m['u'] ?? ''}'.trim();
        if (u.isEmpty) return null;
        return ChatContact(kind: 'user', uid: u);
      }
      if (t == 'phone') {
        final n = '${m['n'] ?? ''}'.trim();
        final ps = m['p'] is List
            ? [
                for (final e in (m['p'] as List))
                  if ('$e'.trim().isNotEmpty) '$e'.trim(),
              ]
            : const <String>[];
        if (n.isEmpty && ps.isEmpty) return null;
        return ChatContact(
          kind: 'phone',
          name: n.isEmpty ? ps.first : n,
          phones: ps.take(maxPhones).toList(),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => isUser
      ? {'t': 'user', 'u': uid}
      : {'t': 'phone', 'n': name, 'p': phones};

  /// Teks pesan (notif + preview daftar chat). Untuk kontak ChatYuk, [name]
  /// diisi pengirim dari cache (nama tidak dikirim di payload).
  String previewText({String fallbackName = ''}) {
    final n = name.isNotEmpty ? name : fallbackName;
    return '📇 ${n.isEmpty ? uid : n}';
  }
}
