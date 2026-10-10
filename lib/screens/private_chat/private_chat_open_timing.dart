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
  // T3a: guard warm voice/video — sekali per buka chat, ditunda 400ms.
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
    handle.stream.listen(_msgsStreamCtrl.add, onError: (e) {
      debugPrint('[NAV] msgs stream error: $e');
    });
  }

  /// T3a/3c: hangatkan cache voice & POSTER VIDEO sesegera mungkin (post-frame,
  /// fire-and-forget) — TIDAK ditunda lagi. Alasan: generate poster video lawan
  /// butuh unduh video → lambat; menundanya (dulu 400ms) memperburuk
  /// ketersediaan poster. Semua kerja di sini async I/O (unawaited) → tidak
  /// memblok frame transisi; hanya pemanggilan yang dipindah ke post-frame.
  /// Guard sekali per buka chat + ambil snapshot TERBARU dari cache (bukan
  /// `msgs` emit pertama yang bisa sebagian) → video tertentu tak terlewat.
  void _scheduleWarmPrefetch(List<MessageModel> msgs) {
    if (msgs.isEmpty || _warmScheduled) return;
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
}
