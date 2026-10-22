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
  });

  OutboxEntry copyWith({bool? pointsDeducted}) => OutboxEntry(
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
    } catch (_) {}
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
    } catch (_) {}
  }

  Future<void> enqueue(OutboxEntry entry) async {
    await load();
    _items.removeWhere((e) => e.pendingId == entry.pendingId);
    _items.add(entry);
    _items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    while (_items.length > _maxItems) {
      _items.removeAt(0);
    }
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
