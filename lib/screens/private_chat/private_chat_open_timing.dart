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

  /// T3a: tunda warm voice/video 400ms — unduhan + generate poster video tidak
  /// boleh berebut dengan animasi transisi. Guard sekali per buka chat.
  void _scheduleWarmPrefetch(List<MessageModel> msgs) {
    if (msgs.isEmpty || _warmScheduled) return;
    _warmScheduled = true;
    Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      unawaited(VoicePrefetch.warmChat(widget.chatId, msgs));
      unawaited(VideoPrefetch.warmChat(widget.chatId, msgs));
    });
  }
}
