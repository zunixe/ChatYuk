import '../../utils.dart';
import '../../utils/mention.dart';
import 'message_cache.dart';

/// Satu pesan yang gagal terkirim karena jaringan dan menunggu dikirim ulang.
///
/// Disimpan di kv terenkripsi (`outbox_v1`) supaya selamat dari restart app:
/// internet mati → bubble tetap tampil → otomatis terkirim saat online.
class OutboxEntry {
  final String pendingId;
  final String kind;
  final String chatId;
  final String senderId;
  final String senderName;
  final String senderGender;
  final String text;
  final String type;
  final String imagePayload;
  final bool needsUpload;
  final String uploadKind;
  final int? durationMs;
  final String? repliedToId;
  final String? repliedToText;
  final String? repliedToSenderName;
  /// Metadata kutipan (jenis media + dimensi + path video) → thumbnail
  /// di kutipan balasan. Null = kutipan teks saja.
  final Map<String, dynamic>? repliedToMeta;
  final bool isForwarded;
  final List<Mention> mentions;
  final DateTime createdAt;
  final bool pointsDeducted;
  final String pointsKind;
  /// Poster video (base64 JPEG, opsional) — disimpan agar kirim ulang dari
  /// outbox tetap menyertakan thumbnail preview penerima.
  final String videoPosterB64;
  /// Ditolak server karena BLOKIR. Bubble tetap tampil (centang-1) lintas
  /// buka-tutup chat, tapi TIDAK PERNAH di-flush — termasuk setelah blokir
  /// dibuka (pesan saat diblokir memang tidak pernah sampai, ala WhatsApp).
  final bool blocked;
  /// Payload poll/kontak (JSON) — supaya bubble tampil lagi setelah dimuat.
  final Map<String, dynamic>? poll;
  final Map<String, dynamic>? contact;

  const OutboxEntry({
    required this.pendingId,
    required this.kind,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.senderGender,
    this.text = '',
    this.type = 'text',
    this.imagePayload = '',
    this.needsUpload = false,
    this.uploadKind = '',
    this.durationMs,
    this.repliedToId,
    this.repliedToText,
    this.repliedToSenderName,
    this.repliedToMeta,
    this.isForwarded = false,
    this.mentions = const [],
    required this.createdAt,
    this.pointsDeducted = false,
    this.pointsKind = 'text',
    this.videoPosterB64 = '',
    this.blocked = false,
    this.poll,
    this.contact,
  });

  OutboxEntry copyWith({bool? pointsDeducted, bool? blocked}) => OutboxEntry(
        pendingId: pendingId,
        kind: kind,
        chatId: chatId,
        senderId: senderId,
        senderName: senderName,
        senderGender: senderGender,
        text: text,
        type: type,
        imagePayload: imagePayload,
        needsUpload: needsUpload,
        uploadKind: uploadKind,
        durationMs: durationMs,
        repliedToId: repliedToId,
        repliedToText: repliedToText,
        repliedToSenderName: repliedToSenderName,
        repliedToMeta: repliedToMeta,
        isForwarded: isForwarded,
        mentions: mentions,
        createdAt: createdAt,
        pointsDeducted: pointsDeducted ?? this.pointsDeducted,
        pointsKind: pointsKind,
        videoPosterB64: videoPosterB64,
        blocked: blocked ?? this.blocked,
        poll: poll,
        contact: contact,
      );

  Map<String, dynamic> toMap() => {
        'pendingId': pendingId,
        'kind': kind,
        'chatId': chatId,
        'senderId': senderId,
        'senderName': senderName,
        'senderGender': senderGender,
        'text': text,
        'type': type,
        'imagePayload': imagePayload,
        'needsUpload': needsUpload,
        'uploadKind': uploadKind,
        'durationMs': durationMs,
        'repliedToId': repliedToId,
        'repliedToText': repliedToText,
        'repliedToSenderName': repliedToSenderName,
        'repliedToMeta': repliedToMeta,
        'isForwarded': isForwarded,
        'mentions': Mention.listTo(mentions),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'pointsDeducted': pointsDeducted,
        'pointsKind': pointsKind,
        'videoPosterB64': videoPosterB64,
        if (blocked) 'blocked': true,
        if (poll != null) 'poll': poll,
        if (contact != null) 'contact': contact,
      };

  factory OutboxEntry.fromMap(Map<String, dynamic> m) => OutboxEntry(
        pendingId: '${m['pendingId'] ?? ''}',
        kind: '${m['kind'] ?? 'private'}',
        chatId: '${m['chatId'] ?? ''}',
        senderId: '${m['senderId'] ?? ''}',
        senderName: '${m['senderName'] ?? ''}',
        senderGender: '${m['senderGender'] ?? ''}',
        text: '${m['text'] ?? ''}',
        type: '${m['type'] ?? 'text'}',
        imagePayload: '${m['imagePayload'] ?? ''}',
        needsUpload: m['needsUpload'] == true,
        uploadKind: '${m['uploadKind'] ?? ''}',
        durationMs: (m['durationMs'] as num?)?.toInt(),
        repliedToId: m['repliedToId'] as String?,
        repliedToText: m['repliedToText'] as String?,
        repliedToSenderName: m['repliedToSenderName'] as String?,
        repliedToMeta: m['repliedToMeta'] is Map
            ? Map<String, dynamic>.from(m['repliedToMeta'] as Map)
            : null,
        isForwarded: m['isForwarded'] == true,
        mentions: Mention.listFrom(m['mentions']),
        createdAt: DateTime.tryParse('${m['createdAt'] ?? ''}') ?? DateTime.now(),
        pointsDeducted: m['pointsDeducted'] == true,
        pointsKind: '${m['pointsKind'] ?? 'text'}',
        videoPosterB64: '${m['videoPosterB64'] ?? ''}',
        blocked: m['blocked'] == true,
        poll: m['poll'] is Map ? Map<String, dynamic>.from(m['poll'] as Map) : null,
        contact: m['contact'] is Map
            ? Map<String, dynamic>.from(m['contact'] as Map)
            : null,
      );
}

/// Antrean pesan offline — singleton + persist ke kv terenkripsi.
class OfflineOutbox {
  OfflineOutbox._();
  static final OfflineOutbox instance = OfflineOutbox._();

  static const _kvKey = 'outbox_v1';
  static const _maxItems = 50;

  final List<OutboxEntry> _items = [];
  bool _loaded = false;
  int _generation = 0;

  /// Kosongkan antrean di MEMORI (logout). Disk dihapus terpisah oleh
  /// `MessageCache.clearAll` — tanpa ini entri akun lama tetap tampil &
  /// ter-flush oleh akun berikutnya sampai app di-restart.
  void resetForLogout() {
    _generation++;
    _items.clear();
    _loaded = false;
  }

  List<OutboxEntry> get all => List.unmodifiable(_items);

  List<OutboxEntry> forChat(String kind, String chatId) =>
      _items.where((e) => e.kind == kind && e.chatId == chatId).toList();

  bool contains(String pendingId) =>
      _items.any((e) => e.pendingId == pendingId);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final gen = _generation;
    try {
      final obj = await MessageCache.instance.loadRawObj(_kvKey);
      // Logout terjadi selagi baca disk → hasil milik akun lama, buang.
      if (gen != _generation) return;
      final raw = obj['items'];
      if (raw is List) {
        _items.clear();
        for (final e in raw) {
          if (e is Map) {
            final entry =
                OutboxEntry.fromMap(Map<String, dynamic>.from(e));
            if (entry.pendingId.isNotEmpty && entry.chatId.isNotEmpty) {
              _items.add(entry);
            }
          }
        }
        _items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      }
    } catch (e) {
      // Antrean lama korup/gagal baca: jangan senyap — tanpa log, pesan yang
      // "hilang" mustahil didiagnosa dari laporan user.
      dlog('[Outbox] load gagal: $e');
    }
  }

  Future<void> _persist() async {
    try {
      if (_items.isEmpty) {
        await MessageCache.instance.removeRawObj(_kvKey);
        return;
      }
      await MessageCache.instance.saveRawObj(_kvKey, {
        'items': _items.map((e) => e.toMap()).toList(),
      });
    } catch (e) {
      // PENTING: dulu `catch (_) {}` → bila tulis disk gagal (kuota/disk
      // penuh/korup), antrean hanya hidup di MEMORI dan HILANG saat app
      // di-restart — tanpa satu pun jejak log. Sekarang selalu tercatat.
      dlog('[Outbox] persist gagal (antrean hanya di memori): $e');
    }
  }

  Future<void> enqueue(OutboxEntry entry) async {
    await load();
    _items.removeWhere((e) => e.pendingId == entry.pendingId);
    _items.add(entry);
    _items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _trimToMax();
    await _persist();
  }

  /// Batas [_maxItems]: buang entri BLOKIR tertua dulu — jangan sampai
  /// bubble blokir menggusur pesan offline yang masih menunggu terkirim.
  void _trimToMax() {
    while (_items.length > _maxItems) {
      final i = _items.indexWhere((e) => e.blocked);
      _items.removeAt(i >= 0 ? i : 0);
    }
  }

  /// Tandai entri ditolak karena BLOKIR (tetap tampil, tak di-flush lagi).
  Future<void> markBlocked(String pendingId) async {
    await load();
    final i = _items.indexWhere((e) => e.pendingId == pendingId);
    if (i < 0 || _items[i].blocked) return;
    _items[i] = _items[i].copyWith(blocked: true);
    await _persist();
  }

  Future<void> remove(String pendingId) async {
    await load();
    final n = _items.length;
    _items.removeWhere((e) => e.pendingId == pendingId);
    if (_items.length != n) await _persist();
  }

  /// Tandai poin entri sudah dipotong (persist) — flush ulang tidak memotong
  /// lagi. Tidak menambah entri bila sudah dihapus.
  Future<void> markPointsDeducted(String pendingId) async {
    await load();
    final i = _items.indexWhere((e) => e.pendingId == pendingId);
    if (i < 0 || _items[i].pointsDeducted) return;
    _items[i] = _items[i].copyWith(pointsDeducted: true);
    await _persist();
  }

  /// True bila kegagalan kirim disebabkan BLOKIR (server menolak).
  ///
  /// Server: trigger `enforce_chat_block` melempar
  /// `raise exception 'blocked' using errcode = 'P0001'`.
  /// Dulu klien hanya mengenali `42501`/`policy`/`insufficient_privilege`
  /// sehingga penolakan blokir jatuh ke pesan generik ("gagal kirim") dan
  /// user tidak tahu ia diblokir.
  static bool isBlockedError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('blocked') ||
        msg.contains('42501') ||
        msg.contains('insufficient_privilege') ||
        msg.contains('row-level security');
  }

  /// True bila error terlihat seperti gangguan jaringan (bukan RLS/blokir).
  static bool isNetworkError(Object e) {
    final msg = e.toString().toLowerCase();
    const markers = [
      'socketexception',
      'failed host lookup',
      'network is unreachable',
      'network is down',
      'network request failed',
      'no internet',
      'unable to resolve',
      'temporary failure',
      'connection refused',
      'connection reset',
      'connection closed',
      'connection timed out',
      'connection failed',
      'connection aborted',
      'broken pipe',
      'handshakeexception',
      'tlsexception',
      'clientexception',
      'xmlhttprequest',
      'timeoutexception',
      'timed out',
      'operation timed out',
      'os error',
      'errno',
    ];
    for (final m in markers) {
      if (msg.contains(m)) return true;
    }
    return false;
  }
}
