import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/riverpod/message_reaction_provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/riverpod/storage_provider.dart';
import '../providers/call_provider.dart';
import '../providers/chat_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/riverpod/connectivity_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/riverpod/location_provider.dart';
import '../providers/points_provider.dart';
import 'story_camera_capture_screen.dart';
import '../providers/social_provider.dart';
import '../core/cache/message_cache.dart';
import '../core/cache/offline_outbox.dart';
import '../core/chat/read_receipt.dart';
import '../core/chat/pending_confirm.dart';
import '../core/nav_guard.dart';
import '../core/chat/chat_location.dart';
import '../core/media/chat_background.dart';
import '../widgets/private_chat_message.dart';
import '../widgets/date_chip.dart';
import '../utils/mention.dart';
import '../widgets/person_avatar.dart';
import '../widgets/chat_call_overlay.dart';
import '../widgets/chat_ui_shared.dart';
import '../main.dart';
import 'call_screen.dart';
import 'user_info_screen.dart';
import '../providers/theme_provider.dart';
import '../widgets/anon_prompt_dialog.dart';
import '../widgets/call_permission_dialog.dart';
import '../core/call/call_permissions.dart';
import '../utils.dart';
import '../mixins/chat_selection_mixin.dart';
import 'private_chat/widgets/coin_gift_dialogs.dart';
import '../mixins/chat_photo_send_mixin.dart';
import '../mixins/chat_send_mixin.dart';
import '../widgets/chat_composer_input.dart';
import '../widgets/chat_info_snack.dart';
import '../widgets/location_picker_sheet.dart';
import '../mixins/chat_outbox_mixin.dart';
import '../core/perf/perf_probe.dart';

/// Warna latar Scaffold private chat — WAJIB opaque (bukan transparent).
///
/// Route transparan bocor ke halaman DI BAWAH private chat selama transisi
/// push/pop (mis. buka profil dari avatar) → sekejap terlihat daftar
/// chat/online + avatar inisial. bgScreen identik visual dengan Container bg
/// di body, jadi tampilan tak berubah; hanya menutup kebocoran transisi.
/// Dikunci sebagai konstanta supaya invarian ini bisa di-unit-test.
@visibleForTesting
final Color privateChatScaffoldBg = AppTheme.bgScreen;

class PrivateChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String otherName;
  final String otherUid;
  final String otherGender;
  final String otherCountry;
  final String otherCity;
  final int otherAge;
  final bool otherRegistered;
  final bool initialOtherDeleted;
  const PrivateChatScreen({
    super.key,
    required this.chatId,
    required this.otherName,
    required this.otherUid,
    this.otherGender = '',
    this.otherCountry = '',
    this.otherCity = '',
    this.otherAge = 0,
    this.otherRegistered = false,
    this.initialOtherDeleted = false,
  });

  @override
  ConsumerState<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

/// Id pesan yang teksnya mengandung [query] (case-insensitive),
/// urut TERBARU dulu — untuk navigasi search chat ala WhatsApp.
/// Murni (tanpa context) supaya bisa di-unit-test.
List<String> searchChatMatches(List<MessageModel> msgs, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final out = <String>[];
  for (var i = msgs.length - 1; i >= 0 && out.length < 300; i--) {
    final m = msgs[i];
    if (m.isDeleted) continue;
    if (m.text.isNotEmpty && m.text.toLowerCase().contains(q)) {
      out.add(m.id);
    }
  }
  return out;
}

class _PrivateChatScreenState extends ConsumerState<PrivateChatScreen>
    with
        ChatOutboxMixin<PrivateChatScreen>,
        ChatSelectionMixin<PrivateChatScreen>,
        ChatPhotoSendMixin<PrivateChatScreen>,
        ChatSendMixin<PrivateChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();
  bool _showAttachRow = false;

  // ── Search dalam percakapan (ala WhatsApp) ──
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _searchQuery = '';
  List<String> _matchIds = const [];
  Set<String> _matchSet = const {};
  int _matchIndex = 0;
  // GlobalKey per pesan cocok — untuk lompat scroll ke hasil.
  // Hanya pesan cocok yang pakai ini (bukan ValueKey), sisanya tidak
  // tersentuh supaya state bubble lain (mis. voice) tidak ikut reset.
  final Map<String, GlobalKey> _searchKeys = {};
  int _searchJumpTries = 0;

  void _openSearch() {
    setState(() {
      _searching = true;
      _searchCtrl.clear();
      _searchQuery = '';
      _matchIds = const [];
      _matchSet = const {};
      _matchIndex = 0;
    });
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    setState(() {
      _searching = false;
      _searchQuery = '';
      _matchIds = const [];
      _matchSet = const {};
      _matchIndex = 0;
      _searchKeys.clear();
    });
  }

  void _onSearchChanged(String v) {
    setState(() {
      _searchQuery = v;
      _matchIndex = 0;
      _searchJumpTries = 0;
    });
    // Ketik = lompat ke cocok terbaru HANYA bila sudah ter-render
    // (tanpa jambak scroll untuk yang jauh — user pakai panah).
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToMatch(0));
  }

  /// Pindah ke hasil berikut/sebelumnya (dir +1 = lebih lama, -1 = lebih
  /// baru), bungkus melingkar ala WhatsApp.
  void _gotoMatch(int dir) {
    if (_matchIds.isEmpty) return;
    setState(() {
      _matchIndex = (_matchIndex + dir) % _matchIds.length;
      if (_matchIndex < 0) _matchIndex += _matchIds.length;
      _searchJumpTries = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToMatch(dir),
    );
  }

  /// Scroll ke cocok aktif. dir=0: hanya bila sudah ter-render (lembut,
  /// untuk saat mengetik). dir!=0: lompat bertahap ke arahnya lalu coba
  /// lagi (maks 5x) sampai ketemu.
  void _scrollToMatch(int dir) {
    if (!mounted || !_searching || _matchIds.isEmpty) return;
    if (_matchIndex < 0 || _matchIndex >= _matchIds.length) return;
    final id = _matchIds[_matchIndex];
    final ctx = _searchKeys[id]?.currentContext;
    if (ctx != null) {
      _searchJumpTries = 0;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.45,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    if (dir == 0 || _searchJumpTries >= 5 || !_scrollCtrl.hasClients) return;
    _searchJumpTries++;
    final pos = _scrollCtrl.position;
    // List reverse: offset 0 = paling baru (bawah). Hasil index naik =
    // makin lama = offset makin besar.
    final target = (pos.pixels + dir * pos.viewportDimension * 0.8)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _scrollCtrl.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToMatch(dir));
  }

  // ── Kontrak ChatSelectionMixin ──
  @override
  String get chatKind => 'private';

  @override
  String get chatId => widget.chatId;

  @override
  AuthProvider get chatAuth => context.read<AuthProvider>();

  @override
  ChatProvider get chatProvider => context.read<ChatProvider>();

  @override
  TextEditingController get chatMsgCtrl => _msgCtrl;

  @override
  void chatFocusComposer() => _inputFocus.requestFocus();

  @override
  void chatScrollToBottom() => _scrollToBottom();

  @override
  Future<bool> chatDeleteMessage(String id) async {
    final ok = await context.read<ChatProvider>().deletePrivateMessage(id);
    // Optimistic lokal: tandai terhapus SEGERA supaya UI tidak menunggu
    // realtime/refetch. DB sudah menyimpan semua id, tapi tampilan bisa
    // tertinggal (gejala "pilih beberapa, hanya 1 yang kelihatan terhapus").
    if (ok && mounted) {
      setState(() => _localDeletedIds.add(id));
    }
    return ok;
  }

  @override
  Future<bool> chatUndeleteMessage(String id) async {
    final ok = await context.read<ChatProvider>().undeletePrivateMessage(id);
    if (ok && mounted) {
      setState(() => _localDeletedIds.remove(id));
    }
    return ok;
  }

  /// Id pesan yang baru dihapus secara lokal — jaring supaya UI langsung
  /// menyembunyikannya walau stream realtime belum sempat memperbarui.
  final Set<String> _localDeletedIds = {};

  @override
  String chatDeletedLabel(S s) => s.messageDeleted;

  // ── YukCoin v2 (berbayar) ──
  @override
  bool get chatYukcoinV2Active => context.read<PointsProvider>().yukcoinV2Active;

  @override
  Future<bool> chatChargeYukcoin(String feature, int cost, String ref) async {
    try {
      await context.read<PointsProvider>().spendYukcoin(feature, cost, ref: ref);
      return true;
    } catch (e) {
      dlog('[PRIVATE] chargeYukcoin error: $e');
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> chatUndoMessage(String id) async {
    final n = int.tryParse(id);
    if (n == null) return {};
    return context.read<PointsProvider>().undoMessage(n);
  }

  @override
  Map<String, String> get chatReactionKnownNames =>
      {widget.otherUid: widget.otherName};

  // ── Kontrak ChatPhotoSendMixin ──
  @override
  Future<void> photoDispatch({
    required String imageData,
    required String type,
    required String senderId,
    required String senderName,
    required String senderGender,
    String text = '',
    String? repliedToId,
    String? repliedToText,
    String? repliedToSenderName,
    int? viewOnceSecs,
    int? videoDurationMs,
  }) async {
    await context.read<ChatProvider>().sendPrivateMessage(
      chatId: widget.chatId,
      senderId: senderId,
      senderName: senderName,
      senderGender: senderGender,
      text: text,
      type: type,
      imageData: imageData,
      // Video pakai durasi asli (bukan timer view-once).
      durationMs: videoDurationMs ?? viewOnceSecs,
      repliedToId: repliedToId,
      repliedToText: repliedToText,
      repliedToSenderName: repliedToSenderName,
    );
  }

  /// Tombol kamera → layar kamera in-app (SAMA seperti Story): preview live +
  /// toggle Foto/Video DI DALAM kamera. Foto → preview composer; video
  /// (maks 60 dtk) → kompres → preview.
  ///
  /// Bila kamera in-app GAGAL init (sebagian MIUI menutup pipeline kamera
  /// pihak-ketiga) → fallback ke kamera SISTEM (foto) supaya tombol tetap
  /// berfungsi.
  Future<void> _openCameraCapture() async {
    final result = await Navigator.of(context).push<StoryCaptureResult>(
      MaterialPageRoute(
        builder: (_) => const StoryCameraCaptureScreen(maxRecordSecs: 60),
      ),
    );
    if (!mounted) return;
    if (result == null) {
      if (StoryCameraCaptureScreen.lastInitFailed) {
        await photoTakeToPreview();
      }
      return;
    }
    if (result.isVideo) {
      await videoFromFileToPreview(result.file.path);
    } else {
      final bytes = await result.file.readAsBytes();
      if (!mounted) return;
      await photoFromFileToPreview(bytes);
    }
  }

  /// Izinkan → ambil posisi → sheet pilihan (lokasi saat ini / live / tempat
  /// sekitar) → LANGSUNG terkirim ke chat (tanpa preview/caption).
  Future<void> _sendLocation() async {
    setState(() => _showAttachRow = false);
    final picked = await pickChatLocation(
      context,
      messenger: ScaffoldMessenger.of(context),
    );
    if (picked == null || !mounted) return;
    await sendLocationFromPreviewAt(picked);
  }

  ChatLocation? _pendingLocation;

  @override
  ChatLocation? get sendPendingLocation => _pendingLocation;

  @override
  set sendPendingLocation(ChatLocation? v) => _pendingLocation = v;

  @override
  Future<void> sendLocationFromPreviewAt(
    ChatLocation loc, {
    String text = '',
    MessageModel? reply,
  }) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    // Caption ikut terkirim di dalam payload (bukan pesan terpisah);
    // place/live/expiresAt dibawa apa adanya (lokasi & lokasi live).
    final payload = ChatLocation(
      lat: loc.lat,
      lng: loc.lng,
      label: loc.label,
      caption: text.trim(),
      place: loc.place,
      live: loc.live,
      expiresAt: loc.expiresAt,
      accuracyM: loc.accuracyM,
    );
    String? sentId;
    try {
      sentId = await context.read<ChatProvider>().sendPrivateMessage(
        chatId: widget.chatId,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: payload.encode(),
        type: 'location',
        repliedToId: reply?.id,
        repliedToText: reply?.text,
        repliedToSenderName: reply?.senderName,
      );
    } catch (_) {
      if (!mounted) return;
      showChatSnack(context, context.read<LocaleProvider>().s.errSendFailed);
      return;
    }
    if (mounted) {
      setState(() => _pendingLocation = null);
      _scrollToBottom();
    }
    // Lokasi LIVE → mulai kirim pembaruan posisi berkala sampai kedaluwarsa.
    if (payload.live && sentId != null && payload.expiresAt != null) {
      _startLiveLocationUpdates(sentId, payload);
    }
  }

  Timer? _liveTimer;

  /// Kirim pembaruan koordinat lokasi live tiap 30 detik sampai kedaluwarsa.
  /// Berhenti otomatis saat waktu habis; update gagal diabaikan (best-effort).
  void _startLiveLocationUpdates(String messageId, ChatLocation initial) {
    _liveTimer?.cancel();
    final lp = ProviderScope.containerOf(context, listen: false).read(locationProvider);
    _liveTimer = Timer.periodic(const Duration(seconds: 30), (t) async {
      final exp = initial.expiresAt;
      if (exp == null || DateTime.now().toUtc().isAfter(exp)) {
        t.cancel();
        return;
      }
      final pos = await lp.precisePosition();
      if (pos == null) return;
      if (!mounted) return;
      final updated = initial.copyWith(lat: pos.$1, lng: pos.$2);
      await context
          .read<ChatProvider>()
          .updateLocationMessage(messageId, updated.encode());
    });
  }

  int? _viewTimerSecs;

  @override
  int? get photoViewTimerSecs => _viewTimerSecs;
  @override
  void photoClearViewTimer() {
    _viewTimerSecs = null;
    if (mounted) setState(() => _pendingPhotoBase64 = null);
  }

  // Caption & balasan untuk view-once dari picker (kirim langsung tanpa
  // preview) — dulu teks yang diketik diabaikan.
  @override
  String get photoComposerText => sendMsgCtrl.text;
  @override
  MessageModel? get photoReplyingTo => sendReplyingTo;
  @override
  void photoClearComposerText() {
    sendMsgCtrl.clear();
    if (mounted) setState(() => sendReplyingTo = null);
  }

  @override
  String get photoUploadChatId => widget.chatId;

  @override
  String get photoSeed => widget.otherUid;

  @override
  void photoOnSent(String kind) {
    _maybeNewChatBonus();
    _schedulePendingConfirmFallback();
  }

  @override
  void photoFirstBonus(PointsProvider pp) {
    // Bonus "first photo" DIHAPUS (overhaul coin: tidak ada poin gratis).
  }

  @override
  void photoSetPreview(String base64) {
    setState(() {
      _pendingPhotoBase64 = base64;
      // Foto, video, & lokasi tidak boleh tampil bareng di preview.
      _pendingVideoPath = null;
      _pendingVideoPoster = null;
      _pendingVideoMs = 0;
      _pendingVideoOnce = false;
      _pendingLocation = null;
      _viewTimerSecs = null;
      _inputFocus.requestFocus();
    });
    _scrollToBottom();
  }

  // ── Kontrak video (private) ──
  @override
  bool get videoSendEnabled => true;

  @override
  String? get pendingVideoPath => _pendingVideoPath;

  @override
  int get pendingVideoMs => _pendingVideoMs;

  /// Kontrak ChatSendMixin: video pending (router tombol kirim).
  @override
  String? get sendPendingVideoPath => _pendingVideoPath;

  @override
  bool get videoOnceSelected => _pendingVideoOnce;

  @override
  void videoSetOnce(bool value) {
    setState(() => _pendingVideoOnce = value);
  }

  @override
  void videoSetPreview({
    required String path,
    required String posterBase64,
    required int durationMs,
  }) {
    setState(() {
      _pendingVideoPath = path;
      _pendingVideoPoster = posterBase64;
      _pendingVideoMs = durationMs;
      _pendingVideoOnce = false; // default: video biasa
      // Video bukan foto: buang preview foto + timer view-once. Lokasi juga
      // (hanya satu preview yang boleh tampil).
      _pendingPhotoBase64 = null;
      _pendingLocation = null;
      _viewTimerSecs = null;
      _inputFocus.requestFocus();
    });
    _scrollToBottom();
  }

  @override
  void videoClearPreview() {
    if (!mounted) return;
    setState(() {
      _pendingVideoPath = null;
      _pendingVideoPoster = null;
      _pendingVideoMs = 0;
      _pendingVideoOnce = false;
    });
  }

  /// Dibaca composer untuk menampilkan pratinjau video (thumbnail base64).
  String? get pendingVideoPosterB64 => _pendingVideoPoster;

  // ── Kontrak ChatSendMixin ──
  @override
  TextEditingController get sendMsgCtrl => _msgCtrl;

  @override
  bool get sendIsSending => _isSending;

  @override
  set sendIsSending(bool v) => _isSending = v;

  @override
  MessageModel? get sendEditingMessage => editingMessage;

  @override
  set sendEditingMessage(MessageModel? v) => editingMessage = v;

  @override
  MessageModel? get sendReplyingTo => replyingTo;

  @override
  set sendReplyingTo(MessageModel? v) => replyingTo = v;

  @override
  String? get sendPendingPhotoBase64 => _pendingPhotoBase64;

  @override
  set sendPendingPhotoBase64(String? v) => _pendingPhotoBase64 = v;

  @override
  List<Mention> sendMentionCandidates() => _mentionCandidates;

  @override
  Future<bool> sendPreCheck() async {
    if (context.read<ChatProvider>().isBlocked(widget.otherUid)) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        showChatSnack(context, s.msgBlocked);
      }
      return false;
    }
    return true;
  }

  @override
  void sendCancelEdit() => cancelEdit();

  @override
  Future<bool> sendEditPersist(MessageModel editing, String raw) =>
      context.read<ChatProvider>().editPrivateMessage(editing.id, raw);

  @override
  Future<void> sendDispatchText({
    required String text,
    required MessageModel? reply,
    required List<Mention> mentions,
  }) async {
    await context.read<ChatProvider>().sendPrivateMessage(
      chatId: widget.chatId,
      senderId: context.read<AuthProvider>().uid!,
      senderName: context.read<AuthProvider>().profile!.nickname,
      senderGender: context.read<AuthProvider>().profile!.gender,
      text: text,
      repliedToId: reply?.id,
      repliedToText: reply?.text,
      repliedToSenderName: reply?.senderName,
      mentions: mentions,
    );
  }

  @override
  void sendOnSentText() {
    _maybeNewChatBonus();
    _schedulePendingConfirmFallback();
  }

  late Stream<List<MessageModel>> _msgsStream;
  late Stream<List<PrivateChatInfo>> _chatInfoStream;
  Future<void> Function() _loadOlder = () async {};
  Future<void> Function(String messageId) _msgsHandleFetchImage = (_) async {};
  Future<void> Function() _msgsHandleReload = () async {};
  bool _loadingOlder = false;

  // ── AUTO-LOAD image deferred ──
  // "harusnya muncul semua image yang dikirim user" — image pesan lama
  // (di luar window 50) di-fetch OTOMATIS saat emit masuk, tanpa tap.
  // Guard: in-flight (jangan dobel) + cooldown 10s per id (emit berikut
  // tidak spam retry kalau fetch gagal; tap manual tetap bisa kapan pun).
  final Set<String> _imgInFlight = {};
  final List<String> _imgQueue = [];
  final Set<String> _imgQueued = {};
  final Map<String, DateTime> _imgLastAttempt = {};
  static const int _maxImageFetches = 3;
  // Penanda id pesan yang SUDAH pernah dipindai auto-load — supaya pemindaian
  // tak mengulang SELURUH list tiap emit (dulu O(N) per emit → berat saat
  // chat panjang / scroll). Hanya pesan BARU yang dicek.
  final Set<String> _imgScannedIds = {};

  void _autoLoadMissingImages(List<MessageModel> msgs) {
    final now = DateTime.now();
    for (final m in msgs) {
      if (m.type != 'image') continue;
      // Sudah pernah dipindai → lewati (anti scan ulang O(N) tiap emit).
      if (!_imgScannedIds.add(m.id)) continue;
      if (m.imageData.isNotEmpty || m.isDeleted) continue;
      if (_imgInFlight.contains(m.id) || _imgQueued.contains(m.id)) continue;
      final last = _imgLastAttempt[m.id];
      if (last != null && now.difference(last) < const Duration(seconds: 10)) {
        continue;
      }
      _imgLastAttempt[m.id] = now;
      _imgQueue.add(m.id);
      _imgQueued.add(m.id);
    }
    // Bound map penanda (cegah tumbuh seumur sesi).
    if (_imgScannedIds.length > 2000) {
      _imgScannedIds.removeAll(_imgScannedIds.take(500).toList());
    }
    if (_imgLastAttempt.length > 2000) {
      _imgLastAttempt.remove(_imgLastAttempt.keys.first);
    }
    _drainImageQueue();
  }

  void _drainImageQueue() {
    while (_imgInFlight.length < _maxImageFetches && _imgQueue.isNotEmpty) {
      final id = _imgQueue.removeAt(0);
      _imgQueued.remove(id);
      if (!_imgInFlight.add(id)) continue;
      _fetchImageQueued(id);
    }
  }

  Future<void> _fetchImageQueued(String id) async {
    try {
      await _msgsHandleFetchImage(id);
    } catch (_) {
      // Gagal memuat satu foto tidak boleh menghentikan antrean foto lain.
    } finally {
      _imgInFlight.remove(id);
      _drainImageQueue();
    }
  }

  DateTime? _otherLastRead;
  DateTime? _lastIncomingSeen;
  /// Lawan sudah menghapus akunnya (penanda lokal) — label khusus, kirim
  /// dikunci, centang-2 diabaikan.
  bool _otherDeleted = false;
  StreamSubscription<List<PrivateChatInfo>>? _chatInfoSub;
  StreamSubscription<List<MessageModel>>? _msgsSub;
  StreamSubscription<String>? _statusSub;
  String _otherStatus = 'offline';
  DateTime? _otherLastSeen;
  String _otherCountry = '';
  String _otherCity = '';
  bool _otherRegistered = false;
  int _otherAgeLive = 0;
  String _otherGenderLive = '';
  bool _wasBlocked = false;

  final List<MessageModel> _pending = [];
  // Antrean offline: id pending yang belum terkirim ke server (centang-1).
  // Terkirim saat koneksi pulih → centang-2 (biru bila dibaca).
  final Set<String> _queuedIds = {};
  bool _connOnline = true;
  bool _flushingOutbox = false;
  // LayerLink per pesan — dipakai anchor bar reaksi ala WA tepat di atas
  // bubble. CompositedTransformFollower ikut mengikuti bubble saat list
  // di-scroll, jadi bar reaksi tidak "menempel" di layar.
  // Mode seleksi ala WA: tahan pesan → header jadi toolbar
  // (balas/bintang/hapus/teruskan), bar emoji mengambang di atas bubble.
  StreamSubscription<Map<String, Map<String, int>>>? _reactionsSub;
  StreamSubscription<Set<String>>? _starredSub;

  // Call video dalam chat: overlay panel draggable di atas layar chat.
  bool _callExpanded = false;

  // Foto yang sudah dikonfirmasi server (id pesan server) — dipakai dedupe
  // FIFO karena imageData di stream berupa thumbnail, bukan base64 penuh.
  // Hanya foto dengan timestamp setelah screen dibuka yang diproses, supaya
  // history lama tidak ikut menghapus pending.
  final Set<String> _confirmedPhotoIds = {};
  final Set<String> _confirmedVoiceIds = {};
  final Set<String> _confirmedVideoIds = {};
  // Gema teks yang sudah memakai satu pending (lihat consumeConfirmedText).
  final Set<String> _confirmedTextIds = {};
  late final DateTime _openedAt;

  // Batas id konfirmasi yang disimpan. Set ini HANYA dipakai untuk dedupe
  // FIFO jangka-pendek; menahannya tanpa batas sepanjang sesi = memori naik
  // terus (GC pressure = lag). LinkedHashSet menjaga urutan insert, jadi kita
  // buang yang paling lama saat lewat cap.
  static const _confirmedCap = 200;
  void _trimConfirmed(Set<String> ids) {
    while (ids.length > _confirmedCap) {
      ids.remove(ids.first);
    }
  }

  // ── Memo derivasi list (anti-lag ngetik/scroll/buka) ──────────────────────
  // `StreamBuilder.builder` ikut rebuild saat PARENT setState (ngetik, pilih
  // teks, buka menu, dsb), bukan cuma saat stream emit. Dulu tiap rebuild itu
  // menghitung ulang: salin list, set `deletedIds`, `searchChatMatches`, dan
  // bangun `items` (satu ChatItem per pesan) → O(N) tiap ketikan → "ngetik
  // ngelag" + scroll berat saat chat panjang.
  //
  // Sekarang derivasi (deletedIds + items) di-CACHE: dihitung ulang HANYA
  // saat (a) referensi list pesan berubah, (b) jumlah `_pending` berubah,
  // atau (c) label tanggal berubah (locale/hari). Rebuild parent lain = cache
  // hit → O(1).
  List<ChatItem> _cachedItems = const [];
  Set<String> _cachedDeletedIds = const {};
  List<MessageModel>? _cacheItemsMsgsSrc;
  int _cacheItemsPendingLen = -1;
  String _cacheItemsLocale = '';
  DateTime? _cacheItemsDay;

  /// Derivasikan `(items, deletedIds)` di-cache berbasis IDENTITAS list
  /// pesan sumber ([msgsSrc], dari stream — referensinya stabil antar rebuild
  /// parent) + jumlah `_pending` + locale + hari. [all] dipakai untuk hasil.
  (List<ChatItem>, Set<String>) _deriveItems(
    S s,
    List<MessageModel> msgsSrc,
    List<MessageModel> all, {
    required DateTime day,
  }) {
    final locale = s.isId ? 'id' : 'en';
    if (identical(_cacheItemsMsgsSrc, msgsSrc) &&
        _cacheItemsPendingLen == _pending.length &&
        _cacheItemsLocale == locale &&
        _cacheItemsDay == day) {
      return (_cachedItems, _cachedDeletedIds);
    }
    final deletedIds = <String>{
      for (final m in all)
        if (m.isDeleted) m.id,
    };
    final items = <ChatItem>[];
    String? prevDateKey;
    for (final m in all) {
      final local = m.timestamp.toLocal();
      final dateKey = '${local.year}-${local.month}-${local.day}';
      if (prevDateKey != dateKey) {
        items.add(ChatItem.date(dateChipLabel(m.timestamp, s)));
      }
      prevDateKey = dateKey;
      items.add(ChatItem.message(m));
    }
    _cacheItemsMsgsSrc = msgsSrc;
    _cacheItemsPendingLen = _pending.length;
    _cacheItemsLocale = locale;
    _cacheItemsDay = day;
    _cachedItems = items;
    _cachedDeletedIds = deletedIds;
    return (items, deletedIds);
  }

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    // Ukuran font chat berubah (slider) → rebuild bubble & composer langsung.
    ChatTextScale.notifier.addListener(_onFontScaleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) activeChatId.value = widget.chatId;
    });
    // Lazy load centang-2: baca last-read tersimpan dari disk DULU supaya
    // pesan yang sudah dibaca langsung centang 2 — tanpa menunggu network.
    // Network tetap sumber kebenaran dan me-refresh diam-diam bila berubah.
    // JALUR CEPAT (sinkron): snapshot list chat di MEMORI (sudah di-preload
    // saat bootstrap) — `lastReadAt` langsung terisi sebelum frame pertama
    // dirender, jadi centang-2 tidak menunggu satu hop async apa pun.
    _primeReadFromCache();
    // Fallback: kv `read:` (bila snapshot memori belum ada) — async.
    _loadCachedRead();
    // Prime bintang SINKRON: baca id pesan berbintang dari MEMORI sebelum
    // frame pertama → bintang tampil instan, tanpa "di-load dulu" (anti-glich).
    // Stream realtime + fallback async menimpa sesudahnya.
    _primeStarredFromCache();
    // Rebuild saat status call berubah (overlay video dalam chat muncul/hilang).
    CallProvider.instance.addListener(_onCallChanged);
    // Buka keyboard → tutup baris menu attach (mirip WhatsApp)
    _inputFocus.addListener(() {
      if (_inputFocus.hasFocus && _showAttachRow) {
        setState(() => _showAttachRow = false);
      }
    });
    // Anti-screenshot dikontrol setting admin global (ScreenSecureService).
    // Privasi view_once tetap terjaga via enterViewOnce/exitViewOnce.

    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();

    // Prime sinkron supaya akun terhapus langsung tampil banner di frame
    // pertama — tanpa kedip composer "Ketik pesan..." dulu menunggu stream.
    _otherDeleted = widget.initialOtherDeleted;
    if (!_otherDeleted && auth.uid != null) {
      final snap = chat.lastPrivateChatsSnapshot(auth.uid!);
      if (snap != null) {
        for (final c in snap) {
          if (c.chatId == widget.chatId && c.otherDeleted) {
            _otherDeleted = true;
            break;
          }
        }
      }
    }

    final msgsHandle = chat.getPrivateChatMessages(widget.chatId);
    _msgsStream = msgsHandle.stream;
    _loadOlder = msgsHandle.loadOlder;
    _msgsHandleFetchImage = msgsHandle.fetchImage;
    _msgsHandleReload = msgsHandle.reload;
    // Scroll ke atas → load pesan lama (pagination)
    _scrollCtrl.addListener(_onScrollToLoadOlder);
    _chatInfoStream = chat.getMyPrivateChats(auth.uid ?? '');

    // Dedupe _pending: hapus satu per satu saat server konfirmasi — aman utk double-send text sama
    _msgsSub = _msgsStream.listen((msgs) {
      // Pesan BARU dari lawan yang masuk sementara chat terbuka → tandai baca
      // agar last_read_at lawan maju → centang 2 (read) pengirim langsung terisi.
      // Tanpa ini, centang 2 baru muncul setelah keluar-masuk chat.
      final myUid = auth.uid;
      if (myUid != null) {
        final latestIncoming = msgs
            .where((m) => m.senderId != myUid && m.timestamp.isAfter(_openedAt))
            .map((m) => m.timestamp)
            .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
        if (latestIncoming != null &&
            (_lastIncomingSeen == null ||
                latestIncoming.isAfter(_lastIncomingSeen!))) {
          _lastIncomingSeen = latestIncoming;
          chat.markAsRead(widget.chatId, myUid);
        }
      }
      if (_pending.isEmpty || !mounted) return;
      final mySenderIds = _pending.map((p) => p.senderId).toSet();
      var changed = false;
      // Teks: cocokkan via consumeConfirmedText (recency + sekali pakai +
      // FIFO). JANGAN cocokkan mentah via isi (pesan lama yang sama isinya
      // membuang pending baru → "kirim lalu hilang, muncul telat").
      for (final m in msgs) {
        if (!mySenderIds.contains(m.senderId)) continue;
        final idx = consumeConfirmedText(
          server: m,
          openedAt: _openedAt,
          consumedIds: _confirmedTextIds,
          pendings: _pending,
        );
        _trimConfirmed(_confirmedTextIds);
        if (idx != -1) {
          _queuedIds.remove(_pending[idx].id);
          _pending.removeAt(idx);
          changed = true;
        }
      }
      // Call (Call ended dll) — optimistic: hapus pending-call tertua saat
      // pesan call terkonfirmasi tiba (durasi bisa beda 1 detik, jadi FIFO).
      for (final m in msgs) {
        if (mySenderIds.contains(m.senderId) &&
            m.type == 'call' &&
            m.timestamp.isAfter(_openedAt)) {
          final idx = _pending.indexWhere((p) => p.type == 'call');
          if (idx != -1) {
            _pending.removeAt(idx);
            changed = true;
            break;
          }
        }
      }
      // Foto & view-once: FIFO via id pesan server. ImageData di stream berupa
      // THUMBNAIL (bukan base64 penuh seperti pending), jadi tidak bisa
      // cocokkan konten — setiap pesan foto terkonfirmasi menghapus satu
      // pending foto tertua (urutan kirim). Hanya pesan yang tiba setelah
      // screen dibuka yang diproses (history lama di-skip via _openedAt).
      //
      // PENTING: sertakan 'view_once_expired' — foto sekali-lihat yang sudah
      // dilihat penerima ditandai server jadi type ini. Pending optimistik
      // dibuat dengan type 'view_once'; bila versi server datang sebagai
      // 'view_once_expired' dan TIDAK dicocokkan, pending tidak pernah dibuang
      // → muncul DUA bubble (bug "foto sekali lihat dobel"). Video sudah
      // menangani 'video_once_expired'; foto kini disamakan.
      for (final m in msgs) {
        if (mySenderIds.contains(m.senderId) &&
            (m.type == 'image' ||
                m.type == 'view_once' ||
                m.type == 'view_once_expired') &&
            m.timestamp.isAfter(_openedAt) &&
            _confirmedPhotoIds.add(m.id)) {
          _trimConfirmed(_confirmedPhotoIds);
          final idx = _pending.indexWhere(
            (p) =>
                (p.type == 'image' ||
                    p.type == 'view_once' ||
                    p.type == 'view_once_expired'),
          );
          if (idx != -1) {
            _pending.removeAt(idx);
            changed = true;
          }
        }
      }
      // Voice: FIFO sama seperti foto — tiap voice terkonfirmasi menghapus
      // satu pending voice tertua supaya tidak dobel & urutan tetap benar.
      for (final m in msgs) {
        if (mySenderIds.contains(m.senderId) &&
            m.type == 'voice' &&
            m.timestamp.isAfter(_openedAt) &&
            _confirmedVoiceIds.add(m.id)) {
          _trimConfirmed(_confirmedVoiceIds);
          final idx = _pending.indexWhere((p) => p.type == 'voice');
          if (idx != -1) {
            _pending.removeAt(idx);
            changed = true;
          }
        }
      }
      // Video (biasa / sekali lihat): FIFO seperti foto — pending berisi
      // base64, versi server berisi PATH, jadi dicocokkan via FIFO bukan isi.
      // Tanpa cabang ini bubble pending TIDAK pernah dibuang → tetap kotak
      // (dan balapan dengan versi server yang sudah tampil).
      for (final m in msgs) {
        if (mySenderIds.contains(m.senderId) &&
            (m.type == 'video' ||
                m.type == 'video_once' ||
                m.type == 'video_once_expired') &&
            m.timestamp.isAfter(_openedAt) &&
            _confirmedVideoIds.add(m.id)) {
          _trimConfirmed(_confirmedVideoIds);
          final idx = _pending.indexWhere(
            (p) =>
                p.type == 'video' ||
                p.type == 'video_once' ||
                p.type == 'video_once_expired',
          );
          if (idx != -1) {
            _pending.removeAt(idx);
            changed = true;
          }
        }
      }
      if (changed && mounted) setState(() {});
    }, onError: (e) {
      // OFFLINE: stream pesan bisa error (realtime putus). TANPA onError,
      // error tak tertangkap ini merusak frame/dispatcher → back mati.
      debugPrint('[NAV] msgs stream error private-chat: $e');
    });

    // Subscription non-kritis ditunda ke post-frame supaya frame pertama
    // (list pesan) tidak tertahan — ala WhatsApp: pesan tampil dulu,
    // status/typing/centang-2 menyusul di frame berikutnya.
    _wasBlocked = context.read<ChatProvider>().isBlocked(widget.otherUid);
    _chatInfoSub = _chatInfoStream.listen((chats) {
      final info = chats.cast<PrivateChatInfo?>().firstWhere(
        (c) => c?.chatId == widget.chatId,
        orElse: () => null,
      );
      // Lawan sudah menghapus akunnya → tandai + buang centang-2 "hantu".
      // Tanpa ini, lastReadAt lama yang tersimpan di cache membuat pesan
      // kita tetap terlihat centang-2 padahal tidak ada perangkat lawan
      // yang pernah menerimanya.
      final gone = info?.otherDeleted ?? false;
      if (gone != _otherDeleted) {
        _otherDeleted = gone;
        if (gone) _otherLastRead = null;
        _scheduleRebuild();
      }
      if (gone) return;
      final read = info?.lastReadAt[widget.otherUid];
      // Monoton maju: yang sudah centang-2 tidak boleh balik centang-1
      // walau network/disk menyusul dengan nilai null atau lebih tua.
      final merged = ReadReceipt.merge(_otherLastRead, read);
      if (read != null && merged != _otherLastRead) {
        _otherLastRead = merged;
        _scheduleRebuild();
        // Persist untuk cold start berikutnya.
        if (merged != null) _persistRead(merged);
      }
    }, onError: (e) {
      // OFFLINE: chat-info stream error → jangan biarkan tak tertangkap.
      debugPrint('[NAV] chatInfo stream error private-chat: $e');
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // markAsRead: RPC tanpa render → aman dijalankan langsung (centang-2
      // lawan cepat maju). Bukan beban frame.
      if (auth.uid != null) chat.markAsRead(widget.chatId, auth.uid!);
      // ── Sisa pekerjaan (reaksi, starred, status, typing, profil) TIDAK
      // dijalankan di frame pertama: dulu semuanya nembak bersamaan TEPAT
      // saat animasi buka private chat mulai → 7 tugas (disk+setState+RPC)
      // bersaing dengan transisi = jank "pas mau kebuka". Ditunda ~220ms
      // (di atas durasi transisi 150ms) supaya frame animasi bersih; fitur
      // (badge reaksi) menyusul sekejap setelah chat tampil.
      _openWorkTimer = Timer(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        _openWorkTimer = null;
        // Cache dulu (tampil instan), stream menimpa sesudahnya.
        ProviderScope.containerOf(context, listen: false).read(messageReactionProvider).loadCachedReactions(widget.chatId).then((
          cached,
        ) {
          if (!mounted || cached.isEmpty || reactions.isNotEmpty) return;
          reactions = cached;
          _scheduleRebuild();
        });
        _reactionsSub = ProviderScope.containerOf(context, listen: false).read(messageReactionProvider)
            .watchReactions(widget.chatId)
            .listen((m) {
          reactions = m;
          _scheduleRebuild();
          ProviderScope.containerOf(context, listen: false).read(messageReactionProvider).saveCachedReactions(widget.chatId, m);
        }, onError: (e) {
          debugPrint('[NAV] reactions stream error: $e');
        });
        _starredSub = ProviderScope.containerOf(context, listen: false).read(messageReactionProvider)
            .watchStarred(widget.chatId)
            .listen((m) {
          starredIds = m;
          _scheduleRebuild();
          ProviderScope.containerOf(context, listen: false).read(messageReactionProvider).saveCachedStarred(
            widget.chatId,
            m,
          );
        }, onError: (e) {
          debugPrint('[NAV] starred stream error: $e');
        });
        // Fallback async: bila prime sinkron (initState) belum terisi (cache
        // memori kosong di sesi ini), muat dari disk. Jangan timpa bila
        // `starredIds` sudah terisi (stream/prime lebih akurat). Dulu TANPA
        // cache → tiap buka chat bintang "di-load dulu" menunggu round-trip.
        ProviderScope.containerOf(context, listen: false).read(messageReactionProvider).loadCachedStarred(
          widget.chatId,
        ).then((cached) {
          if (!mounted || cached.isEmpty || starredIds.isNotEmpty) return;
          starredIds = cached;
          _scheduleRebuild();
        });
        // ── Yang MEMBUAT channel realtime + RPC profil dipisah ke tahap
        // kedua (~500ms) — pembuatan channel Supabase (handshake join) &
        // getOtherProfile bisa "ketahan" tepat saat transisi buka chat baru
        // selesai sempurna. Reaksi cache (di atas, murah) tetap 220ms.
        _channelWorkTimer = Timer(const Duration(milliseconds: 280), () {
          if (!mounted) return;
          _channelWorkTimer = null;
          // Subscribe status realtime lawan bicara
          if (!_wasBlocked) {
            _subscribeStatus();
            _subscribeTyping();
          }
          final otherId = widget.otherUid;
          context.read<AuthProvider>().getOtherProfile(otherId).then((p) {
            if (!mounted || p == null) return;
            _otherCity = p.city.trim();
            _otherCountry = p.country.trim();
            _otherRegistered = p.isRegistered;
            _otherAgeLive = p.age;
            _otherGenderLive = p.gender;
            _scheduleRebuild();
          });
        });
      });
    });
    // Antrean offline: koneksi pulih → kirim otomatis; muat sisa antrean
    // sesi lalu (app sempat ditutup saat offline).
    // CATATAN: `ref.listen` TIDAK boleh di initState (harus di build) —
    // lihat build(): ref.listen(connectivityProvider) dipasang di sana.
    _connOnline = ref.read(connectivityProvider);
    loadQueuedForChat();
  }

  /// Baca last-read lawan SECARA SINKRON sebelum frame pertama, dari DUA
  /// sumber memori (diambil yang terbaru): snapshot live `_privateChatsLast`
  /// (ter-fresh — update tiap event realtime) + `peekRawList` (hasil preload
  /// bootstrap). Tidak ada await → centang-2 tampil instan sejak buka chat.
  void _primeReadFromCache() {
    try {
      final myUid = context.read<AuthProvider>().uid;
      if (myUid == null) return;
      final candidates = <DateTime?>[];
      // 1) Snapshot live — paling fresh di sesi ini.
      final snap = context.read<ChatProvider>().lastPrivateChatsSnapshot(myUid);
      if (snap != null) {
        for (final c in snap) {
          if (c.chatId != widget.chatId) continue;
          candidates.add(c.lastReadAt[widget.otherUid]);
          break;
        }
      }
      // 2) Snapshot list chat di memori MessageCache (isian bootstrap).
      final rows = MessageCache.instance.peekRawList(myUid);
      for (final row in rows) {
        if ('${row['chatId']}' != widget.chatId) continue;
        final raw = row['lastReadAt'];
        if (raw is Map) candidates.add(ReadReceipt.parse(raw[widget.otherUid]));
        break;
      }
      final best = ReadReceipt.best(candidates);
      if (best != null) _otherLastRead = best;
    } catch (_) {}
  }

  /// Prime bintang secara SINKRON: ambil id pesan berbintang dari MEMORI
  /// (tanpa await) sebelum frame pertama — jadi bintang langsung tampil saat
  /// chat dibuka, tidak menunggu satu hop async apa pun (anti-glich).
  /// Stream realtime + fallback `_loadCachedStarredAsync` menimpa sesudahnya.
  void _primeStarredFromCache() {
    try {
      final cached = ProviderScope.containerOf(context, listen: false)
          .read(messageReactionProvider)
          .peekCachedStarred(widget.chatId);
      if (cached.isNotEmpty) starredIds = cached;
    } catch (_) {}
  }

  /// Baca last-read tersimpan (kv terenkripsi) — dipanggil di initState agar
  /// centang-2 tampil instan. Hanya mengisi bila lebih baru dari state
  /// (read receipt monoton maju — tidak pernah mundur).
  Future<void> _loadCachedRead() async {
    try {
      final obj = await MessageCache.instance
          .loadRawObj('read:${widget.chatId}');
      final t = ReadReceipt.parse(obj[widget.otherUid]);
      final merged = ReadReceipt.merge(_otherLastRead, t);
      if (t != null && mounted && merged != _otherLastRead) {
        setState(() => _otherLastRead = merged);
      }
    } catch (_) {}
  }

  /// Simpan last-read network (fire-and-forget) untuk cold start berikutnya.
  void _persistRead(DateTime t) {
    try {
      MessageCache.instance.saveRawObj('read:${widget.chatId}', {
        widget.otherUid: t.toIso8601String(),
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    hideActionBar();
    _reactionsSub?.cancel();
    _starredSub?.cancel();
    ChatTextScale.notifier.removeListener(_onFontScaleChanged);
    _pendingConfirmTimer?.cancel();
    // conn listener dikelola Riverpod (ref.listen) — tak perlu close manual.
    CallProvider.instance.removeListener(_onCallChanged);
    // Keluar chat TIDAK memutus panggilan — call lanjut berjalan dan notifikasi
    // ongoing "sedang call" tetap tampil. Tap notifikasi → kembali ke chat ini.
    _chatInfoSub?.cancel();
    _msgsSub?.cancel();
    _statusSub?.cancel();
    _typingSub?.cancel();
    _typingClearTimer?.cancel();
    _typingState.dispose();
    _openWorkTimer?.cancel();
    _channelWorkTimer?.cancel();
    _liveTimer?.cancel();
    _imgQueue.clear();
    _imgQueued.clear();
    // Voice recording: hentikan timer + native recorder — tanpa ini keluar
    // screen saat rekam = timer jalan terus + setState after dispose + leak.
    // DEFER: dispose saat tree terkunci (unmount IndexedStack) — penulisan
    // notifier memicu markNeedsBuild pada CallBanner → glitch.
    final chatToClear = widget.chatId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (activeChatId.value == chatToClear) activeChatId.value = null;
    });
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  CallPhase? _prevCallPhase;
  /// Slider ukuran font chat berubah → rebuild bubble & composer langsung.
  void _onFontScaleChanged() {
    if (mounted) setState(() {});
  }

  // ── Koalesensi rebuild pekerjaan pasca-buka (FIX jank "buka chat") ──
  // Saat buka chat, beberapa timer (220ms reaksi/starred, 280ms channel +
  // profil lawan) masing-masing memicu setState → layar penuh di-build
  // 2-3× dalam ~300ms (terukur di logcat: dua [CHAT-BUILD] hanya 17ms
  // terpisah). Helper ini menggabungkan rebuild yang jatuh di frame yang
  // sama jadi SATU setState — mengurangi jumlah build penuh tanpa mengubah
  // kapan data muncul (tetap menyusul setelah transisi).
  bool _rebuildScheduled = false;

  void _scheduleRebuild() {
    if (!mounted || _rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  void _onCallChanged() {
    final sess = CallProvider.instance.activeSession;
    // Signature state call yang RELEVAN untuk layar ini: overlay hidup/mati
    // ditentukan oleh (ada sesi? uid lawan? phase?). Dulu cukup `sess == null
    // || remoteUid==other` → setState SELALU saat chat biasa (sess==null
    // selalu true) tiap CallProvider.notify → rebuild penuh tak perlu.
    // Kini setState hanya bila signature benar-benar berubah.
    final relevantForThisChat =
        sess != null && sess.remoteUid == widget.otherUid;
    final sig = relevantForThisChat
        ? '${sess.callId}|${sess.phase}'
        : '_none';
    // Call baru berakhir di chat ini → tampilkan bubble "Call ended" INSTAN
    // (optimistic) agar tidak nunggu Realtime 1-2 detik. Nanti saat pesan
    // server tiba, dedup di _msgsSub akan hapus pending.
    if (sess != null &&
        sess.remoteUid == widget.otherUid &&
        sess.phase == CallPhase.ended &&
        _prevCallPhase != CallPhase.ended) {
      final auth = context.read<AuthProvider>();
      final uid = auth.uid;
      final profile = auth.profile;
      if (uid != null && profile != null) {
        final dur = sess.connectedAt != null
            ? DateTime.now().difference(sess.connectedAt!).inSeconds
            : 0;
        final statusText = switch (sess.endReason) {
          CallEndReason.ended => 'Call ended',
          CallEndReason.declined => 'Call declined',
          CallEndReason.missed => 'Missed call',
          CallEndReason.canceled => 'Call canceled',
          CallEndReason.busy => 'Busy',
          CallEndReason.error => 'Call failed',
        };
        final durText = dur > 0
            ? ' (${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')})'
            : '';
        final text =
            '${sess.callType == 'video' ? '📹' : '📞'} $statusText$durText';
        final pendingCall = MessageModel(
          id: 'pending-call-${DateTime.now().microsecondsSinceEpoch}',
          senderId: uid,
          senderName: profile.nickname,
          senderGender: profile.gender,
          isRegistered: profile.isRegistered,
          text: text,
          type: 'call',
          imageData: '',
          timestamp: DateTime.now(),
        );
        setState(() => _pending.add(pendingCall));
        _scrollToBottom();
      }
    }
    _prevCallPhase = sess?.phase ?? _prevCallPhase;
    // Overlay hidup/mati bergantung pada `activeSession` — termasuk saat sesi
    // di-NULL-kan (clearSession setelah tombol end). Dulu `sess == null` lolos
    // ke `return` (null != otherUid) TANPA setState → overlay TIDAK hilang
    // sampai ada rebuild lain ("end call lama matinya", terutama di MIUI).
    // GRANULAR: rebuild hanya bila signature relevan berubah (bukan tiap
    // notify CallProvider) — hindari rebuild penuh saat chat tanpa call.
    if (sig != _prevCallSig) {
      _prevCallSig = sig;
      if (relevantForThisChat || _prevCallSig == '_none') {
        if (mounted) setState(() {});
      }
    }
  }

  /// Signature state call terakhir yang memicu rebuild — dipakai untuk
  /// memfilter rebuild `_onCallChanged` (lihat penjelasan di sana).
  String _prevCallSig = '_none';

  bool get _showCallOverlay {
    final prov = CallProvider.instance;
    final sess = prov.activeSession;
    return sess != null &&
        prov.activeMode == CallMode.chat &&
        sess.remoteUid == widget.otherUid &&
        !_callExpanded;
  }

  bool _expandingCall = false;
  Future<void> _expandCall() async {
    // Guard anti tap-ganda: dua push beruntun membuat stack kacau &
    // `_callExpanded` salah reset → tombol perbesar terasa "tidak jalan".
    if (_expandingCall) return;
    final sess = CallProvider.instance.activeSession;
    if (sess == null) return;
    _expandingCall = true;
    setState(() => _callExpanded = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          settings: const RouteSettings(name: kCallScreenRoute),
          builder: (_) => CallScreen(
            callId: sess.callId,
            remoteUid: sess.remoteUid,
            remoteName: sess.remoteName,
            callType: sess.callType,
            isCaller: sess.isCaller,
            pendingSignals: const [],
            session: sess,
            onMinimize: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } finally {
      _expandingCall = false;
      if (mounted) setState(() => _callExpanded = false);
    }
  }

  DateTime? _lastSeenFetchedAt;
  void _subscribeStatus() {
    _statusSub?.cancel();
    _statusSub = context
        .read<ChatProvider>()
        .getUserStatus(widget.otherUid)
        .listen((status) {
          if (!mounted) return;
          // Fetch last_seen saat status TIDAK online agar bisa tampilkan
          // "terakhir dilihat" di header; saat online tidak perlu (null).
          // Throttle 30 dtk — status flapping tidak memicu N+1 query.
          if (status == 'online') {
            if (_otherStatus != status || _otherLastSeen != null) {
              _otherStatus = status;
              _otherLastSeen = null;
              _scheduleRebuild();
            }
          } else {
            final now = DateTime.now();
            final lastFetch = _lastSeenFetchedAt;
            // Guard perubahan: stream status bisa emit nilai SAMA berulang
            // (heartbeat presence). Tanpa guard ini, `_scheduleRebuild()`
            // tiap emit → storm rebuild ~tiap frame (jank saat ngetik).
            final statusChanged = _otherStatus != status;
            _otherStatus = status;
            if (statusChanged) _scheduleRebuild();
            if (lastFetch != null &&
                now.difference(lastFetch).inSeconds < 30) {
              return;
            }
            _lastSeenFetchedAt = now;
            context
                .read<ChatProvider>()
                .getUserLastSeen(widget.otherUid)
                .then((t) {
              if (!mounted || t == null) return;
              _otherLastSeen = t;
              _scheduleRebuild();
            });
          }
        }, onError: (e) {
          // OFFLINE: stream status realtime error → jangan tak tertangkap.
          debugPrint('[NAV] status stream error private-chat: $e');
        });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        // reverse: true → offset 0 = paling bawah (pesan terbaru)
        _scrollCtrl.jumpTo(0);
      }
    });
  }

  // Scroll ke atas (reverse list, offset menuju maxScrollExtent = pesan lama)
  // → trigger load pesan lama dari server.
  void _onScrollToLoadOlder() {
    if (!_scrollCtrl.hasClients || _loadingOlder) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    final px = _scrollCtrl.position.pixels;
    // 200px dari paling atas (pesan tertua) → load older
    if (max - px < 200) {
      _loadingOlder = true;
      _loadOlder().whenComplete(() => _loadingOlder = false);
    }
  }

  bool _isSending = false;
  Timer? _pendingConfirmTimer;
  StreamSubscription<(String, int)>? _typingSub;
  Timer? _typingClearTimer;
  // Timer penunda kerja non-kritis saat buka chat (reaksi/starred/status/
  // typing/profil) — supaya tidak jatuh bersamaan animasi transisi. Di-cancel
  // di dispose agar kotak buka-tutup cepat tak menyisakan subscribe nyangkut.
  Timer? _openWorkTimer;
  // Tahap kedua: channel realtime (status/typing) + RPC profil — dipisah dari
  // _openWorkTimer supaya handshake channel tak "ketahan" di frame transisi.
  Timer? _channelWorkTimer;
  DateTime _lastTypingSent = DateTime(2000);
  /// Status bubble typing/recording lawan — 0=off, 1=typing, 2=recording.
  /// ValueNotifier (bukan setState) supaya perubahan typing TIDAK me-rebuild
  /// SELURUH layar CHAT maupun seluruh ListView pesan — dulu ValueListenableBuilder
  /// membungkus SELURUH daftar (items O(n) + semua MessageBubble + avatar)
  /// sehingga tiap pulse typing = list ke-load semua ulang = "ngetik jeda".
  /// Sekarang HANYA bubble typing (item index 0) yang di-drive notifier ini;
  /// list & bubble lain tidak tersentuh.
  final ValueNotifier<int> _typingState = ValueNotifier<int>(0);
  // Id + waktu pesan terakhir dari lawan bicara — dipakai mematikan
  // bubble typing begitu balasan masuk (otoritatif, anti stuck) dan
  // mengabaikan pulse basi dari invokasi lama.
  String? _lastPartnerMsgId;
  DateTime? _lastPartnerMsgTime;
  String? _pendingPhotoBase64;

  // ── Preview VIDEO (private chat) ──
  String? _pendingVideoPath;
  String? _pendingVideoPoster; // base64 JPEG (thumbnail)
  int _pendingVideoMs = 0;
  // Sekali lihat (bukan timer detik — video durasinya = panjang video).
  bool _pendingVideoOnce = false;

  void _subscribeTyping() {
    _typingSub?.cancel();
    dlog('[TYPING] screen subscribing for ${widget.chatId}');
    _typingSub = context
        .read<ChatProvider>()
        .getTypingPulseStream(widget.chatId)
        .listen((event) {
          final kind = event.$1;
          final ts = event.$2;
          // Pulse basi: dikirim SEBELUM/SESAAT SETELAH balasan terakhir
          // dibuat (race delivery: pulse terkirim duluan tapi tiba belakangan)
          // → abaikan. Toleransi +1 detik; typing asli berikutnya (burst /
          // balasan baru, ≥2 detik kemudian) tetap menyalakan bubble.
          final lastMsg = _lastPartnerMsgTime;
          if (lastMsg != null &&
              ts < lastMsg.millisecondsSinceEpoch + 1000) {
            dlog('[TYPING] skipped stale pulse');
            return;
          }
          dlog('[TYPING] stream got kind=$kind -> bubble on');
          if (!mounted) return;
          // Tidak setState: hanya notifier typing (rebuild terbatas).
          _typingState.value = kind == 'recording' ? 2 : 1;
          _typingClearTimer?.cancel();
          _typingClearTimer = Timer(const Duration(seconds: 3), () {
            if (!mounted) return;
            _typingState.value = 0;
          });
        }, onError: (e) {
          // OFFLINE: stream typing error → jangan tak tertangkap.
          debugPrint('[NAV] typing stream error private-chat: $e');
        });
  }

  /// Matikan bubble typing/recording segera (tanpa menunggu timer 3 detik).
  /// Dipanggil saat pesan baru dari lawan bicara masuk — pesan = bukti
  /// otoritatif bahwa fase mengetik selesai (anti bubble nyangkut).
  void _hideTyping() {
    _typingClearTimer?.cancel();
    if (!mounted) return;
    if (_typingState.value != 0) _typingState.value = 0;
  }

  void _sendTypingSignal() {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inMilliseconds < 2500) return;
    _lastTypingSent = now;
    context.read<ChatProvider>().sendTyping(widget.chatId);
  }

  void _sendRecordingSignal() {
    context.read<ChatProvider>().sendTyping(widget.chatId, kind: 'recording');
  }

  bool _newChatBonusClaimed = false;
  bool _bonusToastScheduled = false;

  /// Misi "chat orang baru": bonus hanya diberikan saat user BENAR-BENAR
  /// mengirim pesan pertama ke lawan bicara (bukan pas membuka chat kosong).
  /// RPC new_chat_bonus tetap punya guard sendiri (sekali per user + limit
  /// harian), jadi aman dipanggil dari semua jalur kirim.
  void _maybeNewChatBonus() {
    if (_newChatBonusClaimed) return;
    _newChatBonusClaimed = true;
    context.read<PointsProvider>().newChatBonus(widget.otherUid);
  }

  /// Kandidat mention private 1:1 — hanya lawan bicara. `@all` tidak pernah.
  List<Mention> get _mentionCandidates => widget.otherUid.isEmpty
      ? const []
      : [Mention(uid: widget.otherUid, name: widget.otherName)];

  

  /// Jaring pengaman konfirmasi pending: kalau 3 detik setelah insert sukses
  /// bubble masih belum terkonfirmasi (event Realtime miss / channel drop),
  /// fetch ulang pesan dari server supaya tidak nyangkut sampai polling 30s.
  void _schedulePendingConfirmFallback() {
    _pendingConfirmTimer?.cancel();
    _pendingConfirmTimer = Timer(const Duration(seconds: 3), () async {
      if (!mounted || _pending.isEmpty) return;
      try {
        await _msgsHandleReload();
      } catch (_) {}
    });
  }

  // ── Antrean offline: implementasi BERSAMA di ChatOutboxMixin ──
  bool get outboxIsOnline => _connOnline;

  @override
  String get outboxKind => 'private';

  @override
  String get outboxChatId => widget.chatId;

  @override
  String get outboxUploadChatId => widget.chatId;

  @override
  List<MessageModel> get outboxPending => _pending;

  @override
  Set<String> get outboxQueuedIds => _queuedIds;

  @override
  bool get outboxIsFlushing => _flushingOutbox;

  @override
  set outboxIsFlushing(bool v) => _flushingOutbox = v;

  @override
  void outboxScrollToBottom() => _scrollToBottom();

  @override
  Future<void> outboxSendEntry(OutboxEntry e, String imageData) async {
    await context.read<ChatProvider>().sendPrivateMessage(
      chatId: widget.chatId,
      senderId: e.senderId,
      senderName: e.senderName,
      senderGender: e.senderGender,
      text: e.text,
      type: e.type,
      imageData: imageData,
      durationMs: e.durationMs,
      repliedToId: e.repliedToId,
      repliedToText: e.repliedToText,
      repliedToSenderName: e.repliedToSenderName,
      isForwarded: e.isForwarded,
      mentions: e.mentions,
    );
  }

  @override
  void outboxOnSent() {
    _maybeNewChatBonus();
    _schedulePendingConfirmFallback();
  }


  // ── Voice message 60s — perekam kini di ChatComposerInput ──

  Future<void> voiceFinishRecording(String path, int recordedMs) async {
    final f = File(path);
    final bytes = await f.readAsBytes();
    final chatId = widget.chatId;
    final auth = context.read<AuthProvider>();
    final uid = auth.uid; final profile = auth.profile;
    if (uid == null || profile == null) return;
    // Offline: bubble tetap tampil (centang-1) + antre, terkirim otomatis
    // saat koneksi pulih. Voice tidak pakai poin (pointsKind 'none').
    if (!outboxIsOnline) {
      final optimisticOffline = MessageModel(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        isRegistered: profile.isRegistered,
        text: '',
        type: 'voice',
        imageData: base64Encode(bytes),
        timestamp: DateTime.now(),
        durationMs: recordedMs,
      );
      setState(() => _pending.add(optimisticOffline));
      _scrollToBottom();
      try { await f.delete(); } catch (_) {}
      await queueOffline(
        pending: optimisticOffline,
        pointsKind: 'none',
        pointsDeducted: true,
        imagePayload: base64Encode(bytes),
        needsUpload: true,
        uploadKind: 'voice',
        durationMs: recordedMs,
      );
      return;
    }
    final storagePath = await ProviderScope.containerOf(context, listen: false).read(storageProvider).uploadVoice(chatId: chatId, bytes: bytes);
    if (storagePath == null || storagePath.isEmpty) {
      if (!outboxIsOnline) {
        final optimisticOffline = MessageModel(
          id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
          senderId: uid,
          senderName: profile.nickname,
          senderGender: profile.gender,
          isRegistered: profile.isRegistered,
          text: '',
          type: 'voice',
          imageData: base64Encode(bytes),
          timestamp: DateTime.now(),
          durationMs: recordedMs,
        );
        setState(() => _pending.add(optimisticOffline));
        _scrollToBottom();
        try { await f.delete(); } catch (_) {}
        await queueOffline(
          pending: optimisticOffline,
          pointsKind: 'none',
          pointsDeducted: true,
          imagePayload: base64Encode(bytes),
          needsUpload: true,
          uploadKind: 'voice',
          durationMs: recordedMs,
        );
        return;
      }
      if (mounted) showChatSnack(context, context.read<LocaleProvider>().s.errVoiceUploadFailed);
      return;
    }
    // Optimistic: tampilkan bubble voice langsung
    final optimistic = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
      isRegistered: profile.isRegistered,
      text: '',
      type: 'voice',
      imageData: storagePath,
      timestamp: DateTime.now(),
      durationMs: recordedMs,
    );
    setState(() => _pending.add(optimistic));
    _scrollToBottom();
    try {
      await context.read<ChatProvider>().sendPrivateMessage(chatId: chatId, senderId: uid, senderName: profile.nickname, senderGender: profile.gender, text: '', type: 'voice', imageData: storagePath, durationMs: recordedMs);
      try { await f.delete(); } catch (_) {}
    } catch (e) {
      dlog('[Voice] send error: $e');
      if (OfflineOutbox.isNetworkError(e) || !outboxIsOnline) {
        await queueOffline(
          pending: optimistic,
          pointsKind: 'none',
          pointsDeducted: true,
          imagePayload: storagePath,
          durationMs: recordedMs,
        );
      } else if (mounted) {
        setState(() => _pending.remove(optimistic));
        showChatSnack(context, context.read<LocaleProvider>().s.errSendFailed);
      }
    }
  }







  void _toggleAttachRow() {
    if (!_showAttachRow) {
      FocusScope.of(context).unfocus(); // tutup keyboard saat buka menu
    }
    setState(() => _showAttachRow = !_showAttachRow);
  }

  Future<void> _showSendCoinDialog() async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final points = context.read<PointsProvider>();

    if (!auth.canUsePaid) {
      showChatSnack(
        context,
        auth.profile?.isRegistered != true
            ? s.errCoinRegisterOnly
            : s.msgVerifyToUsePaid,
      );
      return;
    }
    final amount = await showSendCoinDialog(
      context,
      otherName: widget.otherName,
      pointsEnabled: points.enabled,
      paidBalance: points.paidBalance,
    );
    if (amount == null || !mounted) return;
    await _sendCoins(amount);
  }


  Future<void> _sendCoins(int amount) async {
    final s = context.read<LocaleProvider>().s;
    final chat = context.read<ChatProvider>();
    final points = context.read<PointsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await chat.sendCoins(widget.chatId, widget.otherUid, amount);
      if (res['ok'] == true) {
        if (res['points'] != null)
          points.setPoints((res['points'] as num).toInt());
        _maybeNewChatBonus();
        if (mounted) points.showPointsToast(context, s.coinSentToast(amount));
        _scrollToBottom();
      }
    } catch (e) {
      final msg = e.toString();
      final show = msg.contains('Not enough paid') || msg.contains('Not enough')
          ? s.errCoinInsufficient
          : msg.contains('registered')
          ? s.errCoinRegisterOnly
          : s.errSendCoin;
      showChatSnackVia(messenger, context, show);
    }
  }

  Future<void> _sendGift(String giftId, String name, int coins) async {
    final s = context.read<LocaleProvider>().s;
    final chat = context.read<ChatProvider>();
    final points = context.read<PointsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await chat.sendGift(widget.chatId, widget.otherUid, giftId);
      if (res['ok'] == true) {
        if (res['points'] != null)
          points.setPoints((res['points'] as num).toInt());
        _maybeNewChatBonus();
        if (mounted) points.showPointsToast(context, s.giftSentToast(name));
        _scrollToBottom();
      }
    } catch (e) {
      final msg = e.toString();
      final show = msg.contains('Not enough')
          ? s.giftInsufficient
          : msg.contains('registered')
          ? s.errCoinRegisterOnly
          : s.errSendCoin;
      showChatSnackVia(messenger, context, show);
    }
  }

  Future<void> _showGiftPicker() async {
    final s = context.read<LocaleProvider>().s;
    final points = context.read<PointsProvider>();
    final auth = context.read<AuthProvider>();

    if (!auth.canUsePaid) {
      showChatSnack(
        context,
        auth.profile?.isRegistered != true
            ? s.errCoinRegisterOnly
            : s.msgVerifyToUsePaid,
      );
      return;
    }

    final gift = await showGiftPickerSheet(
      context,
      pointsEnabled: points.enabled,
      paidBalance: points.paidBalance,
      bonusBalance: points.bonusBalance,
      bonusMultiplier: points.bonusMultiplier,
    );
    if (gift != null && mounted) {
      setState(() => _showAttachRow = false);
      await _sendGift(gift.id, s.isId ? gift.nameId : gift.nameEn, gift.coins);
    }
  }


  /// AppBar mode search (ala WhatsApp): tombol kembali + field cari +
  /// penghitung hasil + panah atas/bawah.
  AppBar _buildSearchAppBar() {
    final s = context.read<LocaleProvider>().s;
    final total = _matchIds.length;
    final label = total == 0 ? '0/0' : '${_matchIndex + 1}/$total';
    return AppBar(
      toolbarHeight: 56.0,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        tooltip: s.btnCancel,
        onPressed: _closeSearch,
      ),
      title: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        autofocus: true,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        style: AppText.body.copyWith(color: Colors.white),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          isDense: true,
          hintText: s.chatSearchHint,
          hintStyle: AppText.body.copyWith(color: Colors.white70),
          border: InputBorder.none,
        ),
      ),
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_searchQuery.trim().isNotEmpty)
              Text(
                label,
                style: AppText.label.copyWith(color: Colors.white),
              ),
            _SearchNavButton(
              icon: Icons.keyboard_arrow_up,
              enabled: total > 0,
              onTap: () => _gotoMatch(-1),
            ),
            _SearchNavButton(
              icon: Icons.keyboard_arrow_down,
              enabled: total > 0,
              onTap: () => _gotoMatch(1),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('PrivateChat');
    context.watch<ThemeProvider>();
    // Koneksi pulih → flush outbox. `ref.listen` WAJIB di build (bukan
    // initState) — Riverpod mengelolanya (aman saat dispose).
    ref.listen<bool>(connectivityProvider, (prev, next) {
      _connOnline = next;
      if (mounted && next) flushOutbox();
    });
    // select per field (bukan watch penuh): heartbeat presence AuthProvider
    // berubah tiap beberapa detik — watch membuat SELURUH layar chat
    // rebuild tiap kali. Field yang dipakai render tercantum di bawah.
    final callAllEnabled = context.select<AuthProvider, bool>(
      (a) => a.callAllEnabled,
    );
    final meRegistered = context.select<AuthProvider, bool>(
      (a) => a.profile?.isRegistered ?? false,
    );
    final myUid = context.select<AuthProvider, String?>((a) => a.uid);
    final chat = context.read<ChatProvider>();
    // select: rebuild hanya saat isBlocked untuk UID lawan bicara berubah
    final isBlocked = context.select<ChatProvider, bool>(
      (c) => c.isBlocked(widget.otherUid),
    );
    final s = context.watch<LocaleProvider>().s;
    dlog('[CHAT-BUILD] callAllEnabled=$callAllEnabled '
        'meRegistered=$meRegistered '
        'otherRegistered=$_otherRegistered/${widget.otherRegistered}');
    // Saat unblock: re-subscribe status realtime
    if (_wasBlocked && !isBlocked) {
      _wasBlocked = false;
      _subscribeStatus();
      _subscribeTyping();
    } else if (!_wasBlocked && isBlocked) {
      _wasBlocked = true;
      _statusSub?.cancel();
      _statusSub = null;
      _typingSub?.cancel();
      _typingSub = null;
    }
    final displayStatus = isBlocked ? 'offline' : _otherStatus;
    // Efektif: param snapshot dulu, fallback profil live (chat lama
    // snapshot-nya 0/kosong → umur/icon hilang-timbul).
    final effGender = widget.otherGender.isNotEmpty
        ? widget.otherGender
        : _otherGenderLive;
    final effAge = widget.otherAge > 0 ? widget.otherAge : _otherAgeLive;
    final effRegistered = widget.otherRegistered || _otherRegistered;
    final genderEmoji = effGender == 'male'
        ? '👨'
        : effGender == 'female'
        ? '👩'
        : '';
    final agePart = effAge > 0 ? '$effAge' : '';
    final cityPart = _otherCity.isNotEmpty ? _otherCity : widget.otherCity;
    final countryPart = _otherCountry.isNotEmpty
        ? _otherCountry
        : widget.otherCountry;
    // Label gender teks ("Perempuan"/"Laki-laki") TIDAK dipakai — sudah
    // diwakilkan oleh emoji gender (👨/👩) di depan subtitle.
    final subtitle = [
      if (agePart.isNotEmpty) agePart,
      if (cityPart.isNotEmpty && cityPart != countryPart) cityPart,
      if (countryPart.isNotEmpty) countryPart,
    ].where((e) => e.isNotEmpty).join(', ');
    final points = context.select<PointsProvider, int>((p) => p.points);
    final pointsEnabled = context.select<PointsProvider, bool>(
      (p) => p.enabled,
    );

    // Show online bonus toast jika ada yang nunggu (sekali per buka chat).
    if (!_bonusToastScheduled) {
      _bonusToastScheduled = true;
      Future.microtask(() {
        if (!mounted) return;
        final pp = context.read<PointsProvider>();
        pp.checkAndShowOnlineToast(context, s.isId);
        pp.checkAndShowStreakToast(context, s.isId);
      });
    }

    // Header rapat seperti semula: maks 2 baris (nama + subtitle atau
    // status) — AppBar standar 56px. Hashtag tidak lagi di header.
    final headerRows =
        1 + ((subtitle.isNotEmpty || (!isBlocked && _otherStatus == 'online') || (!isBlocked && _otherLastSeen != null)) ? 1 : 0);
    final toolbarH = headerRows <= 2 ? 56.0 : 56.0 + (headerRows - 2) * 15.0;

    return PopScope(
      // Back menutup search dulu, lalu mode seleksi, baru keluar layar.
      canPop: !inSelection && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // Back benar-benar menutup layar: lepas fokus keyboard SEGERA
          // supaya animasi tutup keyboard tidak berebut frame dengan
          // transisi pop (dulu tombol back "kadang ngelag dikit").
          FocusManager.instance.primaryFocus?.unfocus();
          return;
        }
        // Jejak diagnosa "back mati": catat kenapa back di-veto.
        debugPrint(
            '[NAV] back veto private-chat searching=$_searching selection=${selectedIds.length}');
        try {
          if (_searching) {
            _closeSearch();
          } else if (inSelection) {
            clearSelection();
          }
        } catch (e) {
          // Handler back TIDAK BOLEH melempar — exception di sini merusak
          // dispatcher back (back mati permanen sampai restart).
          debugPrint('[NAV] back handler error private-chat: $e');
        }
      },
      child: Scaffold(
      extendBody: true,
      // OPAQUE (dulu Colors.transparent) — lihat [privateChatScaffoldBg].
      backgroundColor: privateChatScaffoldBg,
      // FALSE: background chat TIDAK ikut bergeser saat keyboard muncul
      // (satu halaman tetap). List & composer mengatur inset sendiri
      // via viewInsets/MediaQuery — layout konten tidak meng-krem bg.
      resizeToAvoidBottomInset: false,
      appBar: inSelection
          ? buildSelectionAppBar()
          : _searching
          ? _buildSearchAppBar()
          : AppBar(
        toolbarHeight: toolbarH,
        titleSpacing: 0,
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                final navKey = navKeyUser(widget.otherUid);
                if (!tryClaimNav(navKey)) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserInfoScreen(
                      userId: widget.otherUid,
                      fallbackName: widget.otherName,
                    ),
                  ),
                ).then((_) => releaseNav(navKey));
              },
              // PersonAvatar: SAMA PERSIS dengan kartu daftar "Pengguna
              // Online" (latar tint + ring WARNA GENDER) → warna orang yang
              // sama konsisten di list Online, header chat, profil, dll.
              // Badge: titik presence (atau ikon blokir bila diblokir).
              child: PersonAvatar(
                uid: widget.otherUid,
                name: widget.otherName,
                gender: effGender,
                size: 40,
                status: isBlocked ? null : displayStatus,
                badge: isBlocked
                    ? Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: AppTheme.danger,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.block,
                          size: 10,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                widget.otherName,
                                style: AppText.titleEmphasis.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (effRegistered) ...[
                              SizedBox(width: 4),
                              Icon(
                                Icons.verified,
                                size: 15,
                                color: Color(0xFF8AB4F8),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (genderEmoji.isNotEmpty) ...[
                        Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Text(genderEmoji, style: AppText.bodySmall),
                        ),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: AppText.bodySmall.copyWith(
                              color: Colors.white70,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        // Baris status/last-seen — lebih kecil & kurus
                        // dari subtitle di atasnya (micro 10, tanpa bold).
                        // Hijau saat online, "terakhir dilihat …" saat tidak.
                            if (!isBlocked && _otherStatus == 'online')
                              Text(
                                s.statusOnline,
                                style: AppText.micro.copyWith(
                                  color: AppTheme.online,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            else if (!isBlocked && _otherLastSeen != null)
                              Text(
                                '${s.lastSeenAt} ${formatRelativeTime(_otherLastSeen!, isId: s.isId)}',
                                style: AppText.micro.copyWith(
                                  color: Colors.white70,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Admin bisa membuka tombol call untuk SEMUA user (termasuk
          // anon) via app_settings.call_all_enabled — realtime mengikuti
          // perubahan toggle di panel admin.
          if (callAllEnabled ||
              (meRegistered &&
                  (_otherRegistered || widget.otherRegistered)))
            PopupMenuButton(
              padding: EdgeInsets.zero,
              iconSize: 22,
              // Rapat ke kanan: perkecil kotak tap IconButton bawaan (48dp)
              // supaya ikon call dekat ke titik-3. `constraints` BUKAN untuk
              // ini — field itu mengatur ukuran menu popup, bukan tombol.
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(32, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(Icons.call, color: Colors.white, size: 22),
              color: AppTheme.bgCard,
              tooltip: s.callAudio,
              onSelected: (val) {
                if (val == 'audio') {
                  _startCall(context, 'audio', CallMode.fullscreen);
                } else if (val == 'video') {
                  _startCall(context, 'video', CallMode.chat);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'audio',
                  child: Text(
                    s.callAudio,
                    style: TextStyle(color: AppTheme.textPrimary),
                  ),
                ),
                PopupMenuItem(
                  value: 'video',
                  child: Text(
                    s.callVideo,
                    style: TextStyle(color: AppTheme.textPrimary),
                  ),
                ),
              ],
            ),
          PopupMenuButton(
            padding: EdgeInsets.zero,
            iconSize: 24,
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(32, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(Icons.more_vert, color: Colors.white),
            color: AppTheme.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (val) {
              if (val == 'search') {
                _openSearch();
              } else if (val == 'follow') {
                // Dinamis: sudah follow → berhenti ikuti.
                final social = context.read<SocialProvider>();
                if (social.isFollowing(widget.otherUid)) {
                  social.unfollow(widget.otherUid);
                  showChatSnack(context, s.btnUnfollow);
                } else {
                  social.follow(widget.otherUid);
                  showChatSnack(context, s.btnFollow);
                }
              } else if (val == 'friend') {
                final social = context.read<SocialProvider>();
                final messenger = ScaffoldMessenger.of(context);
                social.sendFriendRequest(widget.otherUid).then((res) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        (res == 'pending' || res == 'friends')
                            ? s.friendRequestSentMutual
                            : s.errGeneric,
                      ),
                    ),
                  );
                });
              } else if (val == 'block') {
                chat.blockUser(myUid!, widget.otherUid);
                showChatSnack(context, s.blockSuccess);
              } else if (val == 'report') {
                _showReportDialog();
              }
            },
            itemBuilder: (_) {
              final social = context.watch<SocialProvider>();
              final following = social.isFollowing(widget.otherUid);
              // Sudah teman / permintaan terkirim → sembunyikan "Tambah Teman"
              // (putus teman / batalkan dilakukan di profil, daftar chat, dll).
              final friendLocked = social.isFriend(widget.otherUid) ||
                  social.isPendingFriendRequest(widget.otherUid);
              return <PopupMenuEntry<String>>[
                PopupMenuItem(
                  value: 'search',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.search_rounded, size: 20),
                    title: Text(s.btnSearch),
                  ),
                ),
                const PopupMenuDivider(height: 1),
                PopupMenuItem(
                  value: 'follow',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      following
                          ? Icons.person_remove_rounded
                          : Icons.person_add_rounded,
                      size: 20,
                    ),
                    title: Text(following ? s.menuUnfollow : s.menuFollow),
                  ),
                ),
                if (!friendLocked) ...[
                  const PopupMenuDivider(height: 1),
                  PopupMenuItem(
                    value: 'friend',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading:
                          const Icon(Icons.person_add_alt_rounded, size: 20),
                      title: Text(s.menuAddFriend),
                    ),
                  ),
                ],
                const PopupMenuDivider(height: 1),
                PopupMenuItem(
                  value: 'block',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.block_rounded,
                      size: 20,
                      color: AppTheme.danger,
                    ),
                    title: Text(
                      s.btnBlock,
                      style: const TextStyle(color: AppTheme.danger),
                    ),
                  ),
                ),
                const PopupMenuDivider(height: 1),
                PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.flag_outlined,
                      size: 20,
                      color: Colors.orange,
                    ),
                    title: Text(
                      s.btnReport,
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      // RepaintBoundary AKAR: saat tombol back ditekan, transisi reverse
      // menggeser seluruh layar. Dengan layer ter-cache, GPU tinggal
      // meng-composite (tanpa re-raster list pesan + bubble + background)
      // → tombol back konsisten mulus (dulu "kadang ngelag dikit").
      body: RepaintBoundary(
        child: Stack(
        children: [
          // Background chat — gambar 30% transparan, di-decode sekali di
          // startup (warmChatBackground) lalu render sinkron via RawImage
          // supaya frame pertama langsung final → tidak ada blink.
          // Ditaruh di layer terluar (Positioned.fill) agar TIDAK ikut
          // bergeser saat keyboard muncul (resizeToAvoidBottomInset: false).
          Positioned.fill(
            child: RepaintBoundary(
              // Background statis: RawImage (opaque) + lapisan warna
              // bgScreen 45% DI ATASNYA → efek "55% terlihat" TANPA `Opacity`
              // widget. `Opacity` full-screen memaksa GPU bikin offscreen
              // layer penuh tiap frame transisi (raster berat = jank buka/
              // tutup chat). Dua draw sederhana ini jauh lebih murah.
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (chatBackgroundImage != null)
                    RawImage(image: chatBackgroundImage, fit: BoxFit.cover)
                  else
                    const SizedBox.shrink(),
                  Container(
                    color: AppTheme.bgScreen.withValues(alpha: 0.45),
                  ),
                ],
              ),
            ),
          ),
          // Konten (list + composer). PENTING: jangan baca viewInsets di
          // sini — dulu `Padding(bottom: MediaQuery.viewInsetsOf...)` di level
          // ini membungkus Column(list+composer) → tiap keyboard muncul
          // (viewInsets 0→~300) SELURUH list pesan rebuild = buka keyboard
          // terasa lambat. Insets sekarang hanya membungkus composer (di
          // bawah), list tak ikut rebuild.
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      // PERF: JANGAN bungkus seluruh ListView dengan
                      // ValueListenableBuilder(_typingState) — dulu itu
                      // me-rebuild SELURUH daftar pesan (items O(n) + semua
                      // MessageBubble + avatar) tiap typing berubah, jadi
                      // "ngetik → semua ke-load ulang → jeda". Sekarang
                      // hanya bubble typing (item index 0) yang di-drive
                      // ValueNotifier — list & bubble lain tak tersentuh.
                      StreamBuilder<List<MessageModel>>(
                        stream: _msgsStream,
                        // FRAME PERTAMA LANGSUNG: data awal dari cache memori
                        // (sinkron) → pesan "nempel" sejak frame pertama
                        // (ala WhatsApp), bukan layar kosong lalu muncul.
                        initialData:
                            MessageCache.instance.peekMessages(
                              cacheKeyFor(widget.chatId),
                            ) ??
                            const <MessageModel>[],
                        builder: (_, snap) {
                          final msgs = snap.data ?? [];
                          // PERF (Fase 3.3): `_pending` biasanya kosong. Jangan
                          // alokasi list gabungan tiap build kalau tidak perlu —
                          // pakai `msgs` apa adanya (identitasnya stabil dari
                          // stream, jadi `_deriveItems` tetap cache-hit).
                          final all = _pending.isEmpty
                              ? msgs
                              : [...msgs, ..._pending];
                          // Pesan baru dari lawan bicara = typing selesai.
                          // Matikan bubble via post-frame (anti setState saat build).
                          // Ini otoritatif: pulse telat dari invokasi lama yang
                          // masih jalan tidak bisa menghidupkan bubble lagi
                          // setelah balasan masuk.
                          for (var i = all.length - 1; i >= 0; i--) {
                            final m = all[i];
                            if (m.senderId != widget.otherUid) continue;
                            if (m.id != _lastPartnerMsgId) {
                              _lastPartnerMsgId = m.id;
                              _lastPartnerMsgTime = m.timestamp;
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => _hideTyping(),
                              );
                            }
                            break;
                          }
                          // Bubble typing/recording jadi item paling bawah list
                          // (ala WhatsApp) supaya ikut scroll bersama pesan.
                          if (all.isEmpty) {
                            // Chat kosong: hanya bubble typing yang mungkin
                            // tampil → cukup listen ValueNotifier di sini
                            // (murah; chat kosong = tak ada list pesan).
                            return ValueListenableBuilder<int>(
                              valueListenable: _typingState,
                              builder: (_, tv, __) {
                                if (tv == 0) return const SizedBox.shrink();
                                return ListView(
                                  controller: _scrollCtrl,
                                  reverse: true,
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    12,
                                    10,
                                    12,
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        4,
                                        0,
                                        6,
                                        6,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: ChatTypingBubble(
                                          isRecording: tv == 2,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          }
                          // Auto-load image deferred (di luar window 50) —
                          // fire-and-forget, hasil masuk via stream emit.
                          _autoLoadMissingImages(all);
                          // Derivasikan deletedIds + items via CACHE (lihat
                          // _deriveItems): hanya dihitung ulang saat list
                          // pesan/pending/locale/hari berubah — bukan tiap
                          // rebuild parent (ngetik/scroll/menu).
                          final now0 = DateTime.now();
                          final day0 = DateTime(now0.year, now0.month, now0.day);
                          final (items, deletedIds) =
                              _deriveItems(s, msgs, all, day: day0);
                          // Search chat: cocokkan sekali per emission juga
                          // (bukan per bubble). Urutan terbaru-dulu untuk
                          // navigasi ala WhatsApp.
                          final searching = _searching &&
                              _searchQuery.trim().isNotEmpty;
                          _matchIds = searching
                              ? searchChatMatches(all, _searchQuery)
                              : const [];
                          _matchSet = _matchIds.toSet();
                          if (_matchIndex >= _matchIds.length) {
                            _matchIndex = 0;
                          }
                          if (searching) {
                            for (final id in _matchIds) {
                              _searchKeys.putIfAbsent(id, () => GlobalKey());
                            }
                            _searchKeys.removeWhere(
                              (id, _) => !_matchSet.contains(id),
                            );
                          } else if (_searchKeys.isNotEmpty) {
                            _searchKeys.clear();
                          }
                          // `items` (pesan + chip tanggal) sudah dihitung di
                          // _deriveItems (cache) — langsung pakai.
                          return ListView.builder(
                            controller: _scrollCtrl,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                            // Slot index 0 SELALU ada untuk bubble typing —
                            // isinya di-drive ValueNotifier (bubble atau
                            // kosong) sehingga perubahan typing TIDAK
                            // me-rebuild list/bubble lain.
                            itemCount: items.length + 1,
                            itemBuilder: (_, i) {
                              // Index 0 = paling bawah (list reverse): bubble
                              // typing/recording nempel di bawah pesan terbaru
                              // dan ikut scroll seperti bubble biasa.
                              if (i == 0) {
                                return ValueListenableBuilder<int>(
                                  valueListenable: _typingState,
                                  builder: (_, tv, __) {
                                    if (tv == 0) return const SizedBox.shrink();
                                    return Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        4,
                                        0,
                                        6,
                                        6,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: ChatTypingBubble(
                                          isRecording: tv == 2,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              }
                              final di = i - 1;
                              final item = items[items.length - 1 - di];
                              if (item.dateLabel != null) {
                                return DateChip(label: item.dateLabel!);
                              }
                              final msg = item.msg!;
                              final isMe = msg.senderId == myUid;
                              final isPending = msg.id.startsWith('pending-');
                              final isRead =
                                  isMe &&
                                  !isPending &&
                                  ReadReceipt.isRead(
                                    msg.timestamp,
                                    _otherLastRead,
                                  );
                              // Image kosong & pesan lama (> 50 dari terbaru) → deferred (icon refresh)
                              final isImageDeferred =
                                  msg.type == 'image' &&
                                  msg.imageData.isEmpty &&
                                  di >= 50;
                              final searchKey = searching
                                  ? _searchKeys[msg.id]
                                  : null;
                              return MessageBubble(
                                key: searchKey ?? ValueKey(msg.id),
                                link: linkFor(msg.id),
                                msg: msg,
                                searchQuery: searching
                                    ? _searchQuery.trim()
                                    : '',
                                chatKey: cacheKeyFor(widget.chatId),
                                isMe: isMe,
                                isRead: isRead,
                                isPending: isPending,
                                isQueued: _queuedIds.contains(msg.id),
                                isImageDeferred: isImageDeferred,
                                onRetryImage: _msgsHandleFetchImage,
                                onLongPressMenu: onMessageLongPress,
                                // Mode seleksi: tap = tambah/kurangi seleksi.
                                onTapSelect: inSelection
                                    ? () => toggleSelect(msg)
                                    : null,
                                selected: selectedIds.contains(msg.id),
                                reactions: reactions[msg.id],
                                starred: starredIds.contains(msg.id),
                                onTapBadge: reactions[msg.id]?.isNotEmpty == true
                                    ? () => openReactionDetail(msg)
                                    : null,
                                // Geser ke kanan = balas. Hanya pesan lawan
                                // (gaya WhatsApp) — pesan sendiri tidak,
                                // supaya tidak bentrok dengan swipe-back
                                // sistem di iOS. Mati saat mode seleksi.
                                onSwipeReply: inSelection || isMe || msg.isDeleted
                                    ? null
                                    : () => replyMessage(msg),
                                deletedIds: deletedIds,
                              );
                            },
                          );
                        },
                      ),
                      if (pointsEnabled)
                        Positioned(
                          top: 8,
                          right: 12,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              '🪙 $points',
                              style: AppText.label.copyWith(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: Offset(0, -1),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Lawan sudah hapus akun → ganti composer dengan
                        // banner info. Tidak bisa kirim apa pun lagi.
                        if (_otherDeleted)
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person_off_outlined,
                                  size: 18,
                                  color: AppTheme.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    s.accountDeletedHint,
                                    style: AppText.bodySmall.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                        if (_queuedIds.isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(12, 6, 12, 2),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.done,
                                  size: 14,
                                  color: AppTheme.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    s.msgQueuedCount(_queuedIds.length),
                                    style: AppText.caption.copyWith(
                                      color: AppTheme.textSecondary,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (replyingTo != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.reply,
                                  size: 16,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.replyingTo,
                                        style: AppText.chatCaption.copyWith(
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                      Text(
                                        replyingTo!.text,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.chatBodySmall.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: AppTheme.textSecondary,
                                  ),
                                  onPressed: cancelReply,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        if (editingMessage != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    s.editingMessage,
                                    style: AppText.chatBodySmall.copyWith(
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: AppTheme.textSecondary,
                                  ),
                                  onPressed: cancelEdit,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        // Insets keyboard HANYA di composer. PENTING:
                        // `MediaQuery.viewInsetsOf` JANGAN dibaca di build
                        // PrivateChatScreen — itu mendaftarkan ELEMENT layar
                        // sebagai depend → tiap IME frame MIUI (puluhan/detik)
                        // rebuild SELURUH layar. `_KeyboardInset` membacanya di
                        // element kecil sendiri → hanya composer yang rebuild.
                        _KeyboardInset(
                          child: ChatComposerInput(
                          controller: _msgCtrl,
                          focusNode: _inputFocus,
                          onSend: sendMessage,
                          showAttachRow: _showAttachRow,
                          onToggleAttach: _toggleAttachRow,
                          onTakePhoto: () {
                            setState(() => _showAttachRow = false);
                            _openCameraCapture();
                          },
                          onSendPhoto: () {
                            setState(() => _showAttachRow = false);
                            photoPickFromGalleryToPreview();
                          },
                          onSendViewOnce: () {
                            setState(() => _showAttachRow = false);
                            sendViewOnceFromPicker();
                          },
                          onSendVoice: (path, ms) => voiceFinishRecording(path, ms),
                          onRecordingSignal: _sendRecordingSignal,
                          onTyping: _sendTypingSignal,
                          // Koin & hadiah hanya bila sistem koin aktif —
                          // hilang total saat dimatikan admin.
                          onSendCoin: pointsEnabled
                              ? _showSendCoinDialog
                              : null,
                          onSendLocation: _sendLocation,
                          pendingLocation: _pendingLocation,
                          onCancelLocation: _pendingLocation != null
                              ? () => setState(() => _pendingLocation = null)
                              : null,
                          onOpenGiftPanel: pointsEnabled
                              ? _showGiftPicker
                              : null,
                          pendingPhotoBase64: _pendingPhotoBase64,
                          onCancelPhoto: _pendingPhotoBase64 != null
                              ? () => setState(() {
                                    _pendingPhotoBase64 = null;
                                    _viewTimerSecs = null;
                                    photoClearPreviewState();
                                  })
                              : null,
                          photoHd: photoHd,
                          onHdChanged: _pendingPhotoBase64 != null
                              ? (v) => setState(() => photoHd = v)
                              : null,
                          viewTimerSecs: _viewTimerSecs,
                          onViewTimerChanged: _pendingPhotoBase64 != null
                              ? (v) =>
                                  setState(() => _viewTimerSecs = v)
                              : null,
                          // ── Video (private) ──
                          onSendVideo: () {
                            if (mounted) {
                              setState(() => _showAttachRow = false);
                            }
                            unawaited(videoPickToPreview());
                          },
                          pendingVideoPoster: _pendingVideoPoster,
                          pendingVideoPath: _pendingVideoPath,
                          pendingVideoMs: _pendingVideoMs,
                          videoOnce: _pendingVideoOnce,
                          onVideoOnceChanged: (v) =>
                              setState(() => _pendingVideoOnce = v),
                          videoCompressing: videoCompressProgress,
                          onCancelVideo: () {
                            if (mounted) {
                              setState(() => _showAttachRow = false);
                            }
                            videoClearPreview();
                          },
                          mentionCandidates: _mentionCandidates,
                          mentionAllowAll: false,
                        )
                        ),
                        ],
                       ],
                     ),
                   ),
                 ),
                ],
              ),
            ),
            if (_showCallOverlay)
            Positioned.fill(
              child: ChatCallOverlay(
                session: CallProvider.instance.activeSession!,
                onExpand: _expandCall,
                onEnd: () =>
                    unawaited(CallProvider.instance.hangup()),
              ),
            ),
        ],
      ),
      ),
      ), // RepaintBoundary
    );
  }

  /// Mulai panggilan audio/video ke lawan bicara.
  /// [mode] menentukan fullscreen atau video dalam chat (overlay).
  Future<void> _startCall(
    BuildContext ctx,
    String callType,
    CallMode mode,
  ) async {
    final s = context.read<LocaleProvider>().s;
    if (CallProvider.instance.inCall) {
      showChatSnack(ctx, s.msgCallInProgress);
      return;
    }
    final messenger = ScaffoldMessenger.of(ctx);
    final auth = context.read<AuthProvider>();
    final profile = auth.profile;
    // Gate anon & dummy: hanya boleh call bila toggle admin
    // app_settings.call_anon_enabled ON (server RLS juga menegakkan).
    // User terdaftar (bukan sesi dummy) selalu boleh.
    final registeredCaller =
        (profile?.isRegistered ?? false) && !auth.dummySessionActive;
    if (!registeredCaller && !auth.callAnonEnabled) {
      final ls = context.read<LocaleProvider>().s;
      showAnonPromptDialog(
        context,
        title: ls.promptCompleteEmailCallTitle,
        message: ls.promptCompleteEmailCallMsg,
        icon: Icons.call_outlined,
      );
      return;
    }
    // Nelp pakai COIN (tanpa gratis). Bila saldo < tarif 1 menit → edukasi +
    // topup, batalkan. Hanya untuk penelepon (isCaller).
    {
      final pp = context.read<PointsProvider>();
      if (pp.callBillingPublished) {
        final ok = await pp.ensureEnoughForCall(context, callType, s.isId);
        if (!ok) return;
      }
    }
    // Izin kamera/mikrofon WAJIB sebelum getUserMedia — tanpa ini video call
    // pertama (izin belum ada) langsung gagal senyap (CallPhase.error).
    final perm = await ensureCallPermissions(video: callType == 'video');
    if (perm != CallPermissionResult.granted) {
      if (!mounted) return;
      showCallPermissionDialog(
        context,
        video: callType == 'video',
        permanentlyDenied: perm == CallPermissionResult.permanentlyDenied,
      );
      return;
    }
    try {
      final callId = await context.read<CallProvider>().startCall(
        widget.otherUid,
        callType,
      );
      if (!mounted) return;
      final session = await CallProvider.instance.startSession(
        callId: callId,
        remoteUid: widget.otherUid,
        remoteName: widget.otherName,
        callType: callType,
        isCaller: true,
        mode: mode,
        myName: profile?.nickname ?? '',
        myGender: profile?.gender ?? 'other',
        notifBody: callType == 'video'
            ? s.callNotifActiveVideo
            : s.callNotifActiveAudio,
        notifChannel: s.callNotifActiveAudio,
        notifDesc: s.callNotifActiveAudio,
        chatId: widget.chatId,
      );
      // Tarif per menit untuk banner (server kirim ulang tiap tick).
      session.setBillingPerMinute(
        context.read<PointsProvider>().callCostPerMin(callType),
      );
      if (!mounted) return;
      if (mode == CallMode.fullscreen) {
        Navigator.of(ctx).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            settings: const RouteSettings(name: kCallScreenRoute),
            builder: (_) => CallScreen(
              callId: callId,
              remoteUid: widget.otherUid,
              remoteName: widget.otherName,
              callType: callType,
              isCaller: true,
              session: session,
            ),
          ),
        );
      }
      // Mode chat: overlay muncul otomatis dari provider.activeSession.
    } catch (e) {
      // Jangan telan error mentah-mentah: tulis ke logcat (dlog di-strip di
      // release) + petakan ke pesan yang menjelaskan penyebab (RLS/jaringan).
      debugPrint('[CALL-START] _startCall gagal ($callType): $e');
      final low = e.toString().toLowerCase();
      final denied = low.contains('policy') ||
          low.contains('permission denied') ||
          low.contains('unauthorized') ||
          low.contains('401') ||
          low.contains('403') ||
          low.contains('jwt');
      final offline = low.contains('socketexception') ||
          low.contains('failed host lookup') ||
          low.contains('network is unreachable') ||
          low.contains('connection refused') ||
          low.contains('timeout');
      showChatSnackVia(
        messenger,
        ctx,
        denied
            ? s.msgCallRegisterOnly
            : offline
                ? s.errCallNetwork
                : s.errGeneric,
      );
    }
  }

  void _showReportDialog() {
    showReportUserDialog(
      context,
      reportedId: widget.otherUid,
      reportedName: widget.otherName,
    );
  }

}

/// Tombol panah navigasi hasil search — rapat tanpa jeda atas-bawah
/// (InkWell 32x32, tanpa padding IconButton bawaan).
class _SearchNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _SearchNavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          icon,
          color: enabled ? Colors.white : Colors.white38,
          size: 24,
        ),
      ),
    );
  }
}




/// Padding bawah = tinggi keyboard (viewInsets). Dibuat widget TERPISAH
/// supaya `MediaQuery.viewInsetsOf` hanya mendaftarkan element INI sebagai
/// depend — bukan element `PrivateChatScreen`. Tanpa ini, IME frame MIUI yang
/// redundan (puluhan/detik) me-rebuild SELURUH layar chat.
class _KeyboardInset extends StatelessWidget {
  final Widget child;
  const _KeyboardInset({required this.child});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}
