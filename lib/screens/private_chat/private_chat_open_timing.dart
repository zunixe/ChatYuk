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
  // P0 (2026-10-11): subscription KE STREAM ASLI (ChatStreamSession). WAJIB
  // disimpan & di-cancel di dispose — dulu tidak: `handle.stream.listen(...)`
  // tak disimpan → `ChatStreamSession.onCancel` TAK PERNAH fire →
  // RealtimeChannel + Timer.periodic(30s) + list _current BOCOR tiap
  // buka-tutup chat = "makin lama makin lambat" (pulih setelah restart).
  StreamSubscription<List<MessageModel>>? _msgsRealSub;
  // A1: revisi isi pesan dari ChatStreamSession (naik tiap isi berubah) —
  // kunci cache stabil untuk `_deriveItems` (dipakai di private_chat_core).
  int _msgsRevision = -1;
  // Handler stream pesan — diisi oleh `_startMessagesStream`.
  Future<void> Function() _loadOlder = () async {};
  Future<void> Function(String messageId) _msgsHandleFetchImage = (_) async {};
  Future<void> Function() _msgsHandleReload = () async {};
  // Warm voice/video sekali per buka chat (guard).
  bool _warmScheduled = false;

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
    _msgsRevision = handle.revision.value;
    // Simpan subscription ASLI → bisa di-cancel saat dispose (lihat _msgsRealSub).
    // A1: update revisi SETIAP emit (revisi naik tiap isi berubah) SEBELUM
    // forward ke controller → `_deriveItems` tahu kapan harus recompute.
    _msgsRealSub = handle.stream.listen((msgs) {
      _msgsRevision = handle.revision.value;
      if (!_msgsStreamCtrl.isClosed) _msgsStreamCtrl.add(msgs);
    }, onError: (e) {
      debugPrint('[NAV] msgs stream error: $e');
    });
  }

  /// P0: lepas subscription ASLI (memicu `ChatStreamSession.onCancel` →
  /// removeChannel + pollTimer.cancel). Dipanggil dari `dispose()`.
  void disposeMessagesStream() {
    _msgsRealSub?.cancel();
    _msgsRealSub = null;
  }

  /// Hangatkan cache voice (post-frame, fire-and-forget).
  ///
  /// ZERO-JANK (2026-10-11): video SENGAJA tidak di-warm saat open — dulu
  /// `VideoPrefetch.warmChat` + `warmOne` per video mengunduh video PENUH
  /// otomatis (s.d. 6 video) tiap buka chat. Sekarang video penuh hanya saat
  /// tap play; poster dibuat saat itu + persist untuk sesi berikutnya.
  /// Voice dipertahankan (file kecil, bounded 6 terbaru).
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
      });
    }
  }
}
