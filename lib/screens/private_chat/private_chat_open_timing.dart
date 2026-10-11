part of '../private_chat_screen.dart';

/// T1b/T1c/T3a (2026-10-11) — pengaturan WAKTU buka chat.
///
/// Tujuan: saat layar chat dibuka dari list (transisi 150ms), frame animasi
/// harus BEBAS dari I/O berat. Semua kerja yang MEMBUAT channel realtime,
/// menembak RPC, atau mengunduh file DITUNDA ke post-frame / beberapa ratus ms
/// SETELAH transisi. Frame pertama tetap terisi dari `initialData:
/// peekMessages` (cache memori sinkron) — jadi tak ada layar kosong.
///
/// Dipisah ke `part` agar `private_chat_screen.dart` (sudah raksasa, ratchet
/// ukuran file) tidak tumbuh.
mixin _PcOpenTimingMx on ConsumerState<PrivateChatScreen> {
  // T1c: stream pesan lewat controller broadcast — listener dipasang di
  // initState TANPA memulai ChatStreamSession.start() (channel + reload berat);
  // start() dipanggil post-frame.
  final _msgsStreamCtrl = StreamController<List<MessageModel>>.broadcast();
  Stream<List<MessageModel>>? _msgsStreamReal;
  // Handler stream pesan — diisi oleh `_startMessagesStream`.
  Future<void> Function() _loadOlder = () async {};
  Future<void> Function(String messageId) _msgsHandleFetchImage = (_) async {};
  Future<void> Function() _msgsHandleReload = () async {};
  // Warm voice/video sekali per buka chat (guard) + set video yang sudah
  // di-warm poster-nya (anti-ulang tiap emit stream).
  bool _warmScheduled = false;
  final Set<String> _warmedVideoPaths = {};

  /// Akses provider chat (getter lokal mixin, nama beda dari getter kelas).
  chatRiverpod.ChatNotifier get _pcChat => ref.read(
        chatRiverpod.chatProvider.notifier,
      );

  /// T1c: mulai ChatStreamSession (channel+reload) SETELAH frame pertama —
  /// idempoten. Frame pertama dari `initialData: peekMessages` (sinkron).
  void _startMessagesStream() {
    if (_msgsStreamReal != null) return;
    final handle = _pcChat.getPrivateChatMessages(widget.chatId);
    _msgsStreamReal = handle.stream;
    _loadOlder = handle.loadOlder;
    _msgsHandleFetchImage = handle.fetchImage;
    _msgsHandleReload = handle.reload;
    handle.stream.listen(_msgsStreamCtrl.add, onError: (e) {
      debugPrint('[NAV] msgs stream error: $e');
    });
  }

  /// Hangatkan cache voice & POSTER VIDEO (post-frame, fire-and-forget).
  ///
  /// Dua bagian:
  /// 1. `_warmScheduled` (sekali per buka chat): warmChat N video terbaru →
  ///    poster siap sebelum user scroll/jump ke video lama.
  /// 2. **Video BARU masuk** (bukan sekali): tiap emit, warm `warmOne` untuk
  ///    video yang belum punya poster di disk → poster siap SEBELUM bubble
  ///    sempat render = hilangkan "poster telat muncul" (2026-10-11).
  ///
  /// Semua async I/O (unawaited) → tidak memblok frame.
  void _scheduleWarmPrefetch(List<MessageModel> msgs) {
    if (msgs.isEmpty) return;
    if (!_warmScheduled) {
      _warmScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final latest =
            MessageCache.instance.peekMessages(cacheKeyFor(widget.chatId)) ??
                const <MessageModel>[];
        final target = latest.isNotEmpty ? latest : msgs;
        unawaited(VoicePrefetch.warmChat(widget.chatId, target));
        unawaited(VideoPrefetch.warmChat(widget.chatId, target));
      });
    }
    // Video baru (belum di-warm) → hangatkan poster segera. Gunakan set
    // id agar tak mengulang video yang sama tiap emit.
    for (final m in msgs) {
      if (!_isVideoMsg(m)) continue;
      final path = m.imageData;
      if (path.isEmpty || !path.contains('/') || path.startsWith('data:')) {
        continue;
      }
      if (!_warmedVideoPaths.add(path)) continue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(VideoPrefetch.warmOne(path));
      });
    }
  }

  /// True bila pesan ini video (biasa / sekali lihat / kadaluarsa).
  bool _isVideoMsg(MessageModel m) =>
      m.type == 'video' ||
      m.type == 'video_once' ||
      m.type == 'video_once_expired';
}
