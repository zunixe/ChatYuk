import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/message_reaction_provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/storage_provider.dart';
import '../providers/call_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../providers/social_provider.dart';
import '../services/chat_service.dart';
import '../core/cache/message_cache.dart';
import '../core/cache/offline_outbox.dart';
import '../core/media/chat_background.dart';
import '../services/call_service.dart';
import '../widgets/private_chat_message.dart';
import '../widgets/date_chip.dart';
import '../utils/mention.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/chat_call_overlay.dart';
import '../widgets/chat_ui_shared.dart';
import '../main.dart';
import 'call_screen.dart';
import 'user_info_screen.dart';
import '../providers/theme_provider.dart';
import '../widgets/anon_prompt_dialog.dart';
import '../utils.dart';
import '../mixins/chat_selection_mixin.dart';
import 'private_chat/widgets/coin_gift_dialogs.dart';
import '../mixins/chat_photo_send_mixin.dart';
import '../mixins/chat_send_mixin.dart';
import '../widgets/chat_composer_input.dart';
import '../mixins/chat_outbox_mixin.dart';

class PrivateChatScreen extends StatefulWidget {
  final String chatId;
  final String otherName;
  final String otherUid;
  final String otherGender;
  final String otherCountry;
  final String otherCity;
  final int otherAge;
  final bool otherRegistered;
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
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen>
    with
        ChatOutboxMixin<PrivateChatScreen>,
        ChatSelectionMixin<PrivateChatScreen>,
        ChatPhotoSendMixin<PrivateChatScreen>,
        ChatSendMixin<PrivateChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _inputFocus = FocusNode();
  bool _showAttachRow = false;

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
  Future<bool> chatDeleteMessage(String id) =>
      context.read<ChatProvider>().deletePrivateMessage(id);

  @override
  String chatDeletedLabel(S s) => s.messageDeleted;

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
  }) async {
    await context.read<ChatProvider>().sendPrivateMessage(
      chatId: widget.chatId,
      senderId: senderId,
      senderName: senderName,
      senderGender: senderGender,
      text: text,
      type: type,
      imageData: imageData,
      repliedToId: repliedToId,
      repliedToText: repliedToText,
      repliedToSenderName: repliedToSenderName,
    );
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
    if (!pp.enabled) return;
    pp.oneTimeBonus('first_photo', 10).then((earned) {
      if (earned && mounted) {
        final s = context.read<LocaleProvider>().s;
        pp.showPointsToast(context, s.pointsGain(10, s.reasonFirstPhoto));
      }
    });
  }

  @override
  void photoSetPreview(String base64) {
    setState(() {
      _pendingPhotoBase64 = base64;
      _inputFocus.requestFocus();
    });
    _scrollToBottom();
  }

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgBlocked)));
      }
      return false;
    }
    return true;
  }

  @override
  void sendCancelEdit() => cancelEdit();

  @override
  Future<bool> sendEditPersist(MessageModel editing, String raw) =>
      ChatService().editPrivateMessage(editing.id, raw);

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
  final Map<String, DateTime> _imgLastAttempt = {};
  void _autoLoadMissingImages(List<MessageModel> msgs) {
    final now = DateTime.now();
    for (final m in msgs) {
      if (m.type != 'image' || m.imageData.isNotEmpty) continue;
      if (m.isDeleted) continue;
      if (_imgInFlight.contains(m.id)) continue;
      final last = _imgLastAttempt[m.id];
      if (last != null && now.difference(last) < const Duration(seconds: 10)) {
        continue;
      }
      _imgInFlight.add(m.id);
      _imgLastAttempt[m.id] = now;
      _msgsHandleFetchImage(m.id).whenComplete(() {
        _imgInFlight.remove(m.id);
      });
    }
  }

  DateTime? _otherLastRead;
  DateTime? _lastIncomingSeen;
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
  ConnectivityProvider? _connProv;
  VoidCallback? _connListener;
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
  late final DateTime _openedAt;

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
      final confirmedTexts = msgs
          .where((m) => mySenderIds.contains(m.senderId) && m.type == 'text')
          .map((m) => m.text)
          .toList();
      var changed = false;
      for (final text in confirmedTexts) {
        final idx = _pending.indexWhere(
          (p) => p.type == 'text' && p.text == text,
        );
        if (idx != -1) {
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
      for (final m in msgs) {
        if (mySenderIds.contains(m.senderId) &&
            (m.type == 'image' || m.type == 'view_once') &&
            m.timestamp.isAfter(_openedAt) &&
            _confirmedPhotoIds.add(m.id)) {
          final idx = _pending.indexWhere(
            (p) => (p.type == 'image' || p.type == 'view_once'),
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
          final idx = _pending.indexWhere((p) => p.type == 'voice');
          if (idx != -1) {
            _pending.removeAt(idx);
            changed = true;
          }
        }
      }
      if (changed && mounted) setState(() {});
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
      final read = info?.lastReadAt[widget.otherUid];
      // Monoton maju: yang sudah centang-2 tidak boleh balik centang-1
      // walau network/disk menyusul dengan nilai null atau lebih tua.
      if (read != null &&
          (_otherLastRead == null || read.isAfter(_otherLastRead!))) {
        if (mounted) setState(() => _otherLastRead = read);
        // Persist untuk cold start berikutnya.
        _persistRead(read);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (auth.uid != null) chat.markAsRead(widget.chatId, auth.uid!);
      // Cache dulu (tampil instan), stream menimpa sesudahnya.
      context.read<MessageReactionProvider>().loadCachedReactions(widget.chatId).then((
        cached,
      ) {
        if (!mounted || cached.isEmpty || reactions.isNotEmpty) return;
        setState(() => reactions = cached);
      });
      _reactionsSub = context.read<MessageReactionProvider>()
          .watchReactions(widget.chatId)
          .listen((m) {
        if (mounted) setState(() => reactions = m);
        context.read<MessageReactionProvider>().saveCachedReactions(widget.chatId, m);
      });
      _starredSub = context.read<MessageReactionProvider>()
          .watchStarred(widget.chatId)
          .listen((m) {
        if (mounted) setState(() => starredIds = m);
      });
      // Subscribe status realtime lawan bicara
      // Kalau diblokir, tampilkan offline langsung tanpa fetch DB
      if (!_wasBlocked) {
        _subscribeStatus();
        _subscribeTyping();
      }
      // Ambil profil lawan sekali untuk lengkapi kota (mis. dibuka dari room chat
      // yang hanya mengirim gender tanpa country/city).
      final otherId = widget.otherUid;
      context.read<AuthProvider>().getOtherProfile(otherId).then((p) {
        if (!mounted || p == null) return;
        final city = p.city.trim();
        final country = p.country.trim();
        setState(() {
          _otherCity = city;
          _otherCountry = country;
          // Fix: profil lawan di-fetch live — bukan cuma dari param,
          // supaya chat yang dibuka lewat notifikasi ikut tahu status
          // terdaftar lawan (tombol call & icon verified).
          _otherRegistered = p.isRegistered;
          // Fix umur/gender hilang-timbul: snapshot participantAges/
          // participantGenders di baris chat bisa 0/kosong (chat lama
          // belum ke-backfill). Lengkapi dari profil live.
          _otherAgeLive = p.age;
          _otherGenderLive = p.gender;
        });
      });
    });
    // Antrean offline: koneksi pulih → kirim otomatis; muat sisa antrean
    // sesi lalu (app sempat ditutup saat offline).
    _connProv = context.read<ConnectivityProvider>();
    _connListener = () {
      if (mounted && (_connProv?.online ?? false)) flushOutbox();
    };
    _connProv!.addListener(_connListener!);
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
      DateTime? best;
      // 1) Snapshot live — paling fresh di sesi ini.
      final snap = context.read<ChatProvider>().lastPrivateChatsSnapshot(myUid);
      if (snap != null) {
        for (final c in snap) {
          if (c.chatId != widget.chatId) continue;
          best = c.lastReadAt[widget.otherUid];
          break;
        }
      }
      // 2) Snapshot list chat di memori MessageCache (isian bootstrap).
      final rows = MessageCache.instance.peekRawList(myUid);
      for (final row in rows) {
        if ('${row['chatId']}' != widget.chatId) continue;
        final raw = row['lastReadAt'];
        if (raw is Map) {
          final v = raw[widget.otherUid];
          final t = v is DateTime ? v : DateTime.tryParse('$v');
          if (t != null && (best == null || t.isAfter(best))) best = t;
        }
        break;
      }
      if (best != null) _otherLastRead = best;
    } catch (_) {}
  }

  /// Baca last-read tersimpan (kv terenkripsi) — dipanggil di initState agar
  /// centang-2 tampil instan. Hanya mengisi bila lebih baru dari state
  /// (read receipt monoton maju — tidak pernah mundur).
  Future<void> _loadCachedRead() async {
    try {
      final obj = await MessageCache.instance
          .loadRawObj('read:${widget.chatId}');
      final iso = obj[widget.otherUid] as String?;
      final t = iso == null ? null : DateTime.tryParse(iso);
      if (t != null &&
          mounted &&
          (_otherLastRead == null || t.isAfter(_otherLastRead!))) {
        setState(() => _otherLastRead = t);
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
    try {
      final l = _connListener;
      if (l != null) _connProv?.removeListener(l);
    } catch (_) {}
    _connListener = null;
    _connProv = null;
    CallProvider.instance.removeListener(_onCallChanged);
    // Keluar chat TIDAK memutus panggilan — call lanjut berjalan dan notifikasi
    // ongoing "sedang call" tetap tampil. Tap notifikasi → kembali ke chat ini.
    _chatInfoSub?.cancel();
    _msgsSub?.cancel();
    _statusSub?.cancel();
    _typingSub?.cancel();
    _typingClearTimer?.cancel();
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
    super.dispose();
  }

  CallPhase? _prevCallPhase;
  /// Slider ukuran font chat berubah → rebuild bubble & composer langsung.
  void _onFontScaleChanged() {
    if (mounted) setState(() {});
  }

  void _onCallChanged() {
    final sess = CallProvider.instance.activeSession;
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
    if (sess?.remoteUid != widget.otherUid) return;
    if (mounted) setState(() {});
  }

  bool get _showCallOverlay {
    final prov = CallProvider.instance;
    final sess = prov.activeSession;
    return sess != null &&
        prov.activeMode == CallMode.chat &&
        sess.remoteUid == widget.otherUid &&
        !_callExpanded;
  }

  Future<void> _expandCall() async {
    final sess = CallProvider.instance.activeSession;
    if (sess == null) return;
    setState(() => _callExpanded = true);
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
    if (mounted) setState(() => _callExpanded = false);
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
              setState(() {
                _otherStatus = status;
                _otherLastSeen = null;
              });
            }
          } else {
            final now = DateTime.now();
            final lastFetch = _lastSeenFetchedAt;
            setState(() => _otherStatus = status);
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
              setState(() => _otherLastSeen = t);
            });
          }
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
  DateTime _lastTypingSent = DateTime(2000);
  bool _showTyping = false;
  bool _showRecording = false;
  // Id + waktu pesan terakhir dari lawan bicara — dipakai mematikan
  // bubble typing begitu balasan masuk (otoritatif, anti stuck) dan
  // mengabaikan pulse basi dari invokasi lama.
  String? _lastPartnerMsgId;
  DateTime? _lastPartnerMsgTime;
  String? _pendingPhotoBase64;

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
          setState(() {
            if (kind == 'recording') {
              _showRecording = true;
              _showTyping = false;
            } else {
              _showTyping = true;
              _showRecording = false;
            }
          });
          _typingClearTimer?.cancel();
          _typingClearTimer = Timer(const Duration(seconds: 3), () {
            if (!mounted) return;
            setState(() {
              _showTyping = false;
              _showRecording = false;
            });
          });
        });
  }

  /// Matikan bubble typing/recording segera (tanpa menunggu timer 3 detik).
  /// Dipanggil saat pesan baru dari lawan bicara masuk — pesan = bukti
  /// otoritatif bahwa fase mengetik selesai (anti bubble nyangkut).
  void _hideTyping() {
    _typingClearTimer?.cancel();
    if (!mounted) return;
    if (_showTyping || _showRecording) {
      setState(() {
        _showTyping = false;
        _showRecording = false;
      });
    }
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
  bool get outboxIsOnline => _connProv?.online ?? true;

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
    final storagePath = await context.read<StorageProvider>().uploadVoice(chatId: chatId, bytes: bytes);
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<LocaleProvider>().s.errVoiceUploadFailed)));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<LocaleProvider>().s.errSendFailed)));
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            auth.profile?.isRegistered != true
                ? s.errCoinRegisterOnly
                : s.msgVerifyToUsePaid,
          ),
        ),
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
      messenger.showSnackBar(SnackBar(content: Text(show)));
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
      messenger.showSnackBar(SnackBar(content: Text(show)));
    }
  }

  Future<void> _showGiftPicker() async {
    final s = context.read<LocaleProvider>().s;
    final points = context.read<PointsProvider>();
    final auth = context.read<AuthProvider>();

    if (!auth.canUsePaid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            auth.profile?.isRegistered != true
                ? s.errCoinRegisterOnly
                : s.msgVerifyToUsePaid,
          ),
        ),
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


  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    // watch (bukan read): toggle callAllEnabled dari panel admin harus
    // langsung memunculkan/menyembunyikan tombol call tanpa restart.
    final auth = context.watch<AuthProvider>();
    final chat = context.read<ChatProvider>();
    // select: rebuild hanya saat isBlocked untuk UID lawan bicara berubah
    final isBlocked = context.select<ChatProvider, bool>(
      (c) => c.isBlocked(widget.otherUid),
    );
    final s = context.watch<LocaleProvider>().s;
    dlog('[CHAT-BUILD] callAllEnabled=${auth.callAllEnabled} '
        'meRegistered=${auth.profile?.isRegistered} '
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
    final points = context.watch<PointsProvider>().points;

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
      canPop: !inSelection,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inSelection) clearSelection();
      },
      child: Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      // FALSE: background chat TIDAK ikut bergeser saat keyboard muncul
      // (satu halaman tetap). List & composer mengatur inset sendiri
      // via viewInsets/MediaQuery — layout konten tidak meng-krem bg.
      resizeToAvoidBottomInset: false,
      appBar: inSelection ? buildSelectionAppBar() : AppBar(
        toolbarHeight: toolbarH,
        titleSpacing: 0,
        title: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserInfoScreen(
                    userId: widget.otherUid,
                    fallbackName: widget.otherName,
                  ),
                ),
              ),
              child: ProfileAvatar(
                uid: widget.otherUid,
                name: widget.otherName,
                size: 40,
                borderRadius: 0,
                // Samakan dengan kartu list Pesan (beda ukuran saja):
                // border warna gender, bg aksen 15%, teks primer, badge
                // titik presence 11px (atau ikon blokir bila diblokir).
                borderColor: isBlocked
                    ? null
                    : effGender == 'male'
                    ? AppTheme.male
                    : effGender == 'female'
                    ? AppTheme.female
                    : AppTheme.accent,
                bgColor: isBlocked
                    ? AppTheme.avatarBgBlocked
                    : AppTheme.avatarBg,
                textColor: isBlocked
                    ? AppTheme.textSecondary
                    : AppTheme.textPrimary,
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
                    : Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: AppTheme.statusColor(displayStatus),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
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
          if (auth.callAllEnabled ||
              ((auth.profile?.isRegistered ?? false) &&
                  (_otherRegistered || widget.otherRegistered)))
            PopupMenuButton(
              padding: EdgeInsets.zero,
              iconSize: 22,
              // Rapatkan ke kanan: kurangi area sentuh bawaan PopupMenuButton
              // (default ~48px) supaya jarak ke ikon more_vert tidak lebar.
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
            icon: Icon(Icons.more_vert, color: Colors.white),
            color: AppTheme.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (val) {
              if (val == 'follow') {
                final social = context.read<SocialProvider>();
                social.follow(widget.otherUid);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(s.btnFollow)));
              } else if (val == 'friend') {
                final social = context.read<SocialProvider>();
                social.sendFriendRequest(widget.otherUid);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(s.friendRequestSent)));
              } else if (val == 'block') {
                chat.blockUser(auth.uid!, widget.otherUid);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(s.blockSuccess)));
              } else if (val == 'report') {
                _showReportDialog();
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem(
                value: 'follow',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_add_rounded, size: 20),
                  title: Text(s.menuFollow),
                ),
              ),
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
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background chat — gambar 30% transparan, di-decode sekali di
          // startup (warmChatBackground) lalu render sinkron via RawImage
          // supaya frame pertama langsung final → tidak ada blink.
          // Ditaruh di layer terluar (Positioned.fill) agar TIDAK ikut
          // bergeser saat keyboard muncul (resizeToAvoidBottomInset: false).
          Positioned.fill(
            child: Container(
              color: AppTheme.bgScreen,
              child: chatBackgroundImage == null
                  ? const SizedBox.shrink()
                  : Opacity(
                      opacity: 0.55,
                      child: RawImage(
                        image: chatBackgroundImage,
                        fit: BoxFit.cover,
                      ),
                    ),
            ),
          ),
          // Konten (list + composer) naik di atas keyboard via padding
          // viewInsets sendiri — bg tetap fullscreen diam (tidak ikut
          // bergeser), karena resizeToAvoidBottomInset: false di atas.
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
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
                          final all = [...msgs, ..._pending];
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
                          final typingOn = _showTyping || _showRecording;
                          if (all.isEmpty && !typingOn) {
                            // Chat baru/kosong — tampilkan layar kosong saja,
                            // tanpa ikon/teks "mulai percakapan".
                            return const SizedBox.shrink();
                          }
                          // Auto-load image deferred (di luar window 50) —
                          // fire-and-forget, hasil masuk via stream emit.
                          _autoLoadMissingImages(all);
                          // Selipkan chip tanggal (Hari ini/Kemarin/tanggal) di antara grup hari,
                          // pola WhatsApp — item list berisi pesan + separator tanggal.
                          final items = <ChatItem>[];
                          String? prevDateKey;
                          for (final m in all) {
                            final local = m.timestamp.toLocal();
                            final dateKey =
                                '${local.year}-${local.month}-${local.day}';
                            if (prevDateKey != dateKey) {
                              items.add(
                                ChatItem.date(dateChipLabel(m.timestamp, s)),
                              );
                            }
                            prevDateKey = dateKey;
                            items.add(ChatItem.message(m));
                          }
                          return ListView.builder(
                            controller: _scrollCtrl,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                            itemCount: items.length + (typingOn ? 1 : 0),
                            itemBuilder: (_, i) {
                              // Index 0 = paling bawah (list reverse): bubble
                              // typing/recording nempel di bawah pesan terbaru
                              // dan ikut scroll seperti bubble biasa.
                              if (typingOn && i == 0) {
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    0,
                                    0,
                                    6,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: ChatTypingBubble(
                                      isRecording: _showRecording,
                                    ),
                                  ),
                                );
                              }
                              final di = typingOn ? i - 1 : i;
                              final item = items[items.length - 1 - di];
                              if (item.dateLabel != null) {
                                return DateChip(label: item.dateLabel!);
                              }
                              final msg = item.msg!;
                              final isMe = msg.senderId == auth.uid;
                              final isPending = msg.id.startsWith('pending-');
                              final isRead =
                                  isMe &&
                                  !isPending &&
                                  _otherLastRead != null &&
                                  !msg.timestamp.isAfter(_otherLastRead!);
                              // Image kosong & pesan lama (> 50 dari terbaru) → deferred (icon refresh)
                              final isImageDeferred =
                                  msg.type == 'image' &&
                                  msg.imageData.isEmpty &&
                                  di >= 50;
                              // PRIVASI: kumpulan id pesan terhapus — quote
                              // reply yang menunjuk pesan ini dirender
                              // "Pesan dihapus", bukan isinya.
                              final deletedIds = {
                                for (final m in all)
                                  if (m.isDeleted) m.id,
                              };
                              return MessageBubble(
                                key: ValueKey(msg.id),
                                link: linkFor(msg.id),
                                msg: msg,
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
                      if (context.watch<PointsProvider>().enabled)
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
                        ChatComposerInput(
                          controller: _msgCtrl,
                          focusNode: _inputFocus,
                          onSend: sendMessage,
                          showAttachRow: _showAttachRow,
                          onToggleAttach: _toggleAttachRow,
                          onTakePhoto: () {
                            setState(() => _showAttachRow = false);
                            photoTakeToPreview();
                          },
                          onSendPhoto: () {
                            setState(() => _showAttachRow = false);
                            photoPickFromGalleryAndSend();
                          },
                          onSendViewOnce: () {
                            setState(() => _showAttachRow = false);
                            sendViewOnceFromPicker();
                          },
                          onSendVoice: (path, ms) => voiceFinishRecording(path, ms),
                          onRecordingSignal: _sendRecordingSignal,
                          onTyping: _sendTypingSignal,
                          onSendCoin: _showSendCoinDialog,
                          onOpenGiftPanel: _showGiftPicker,
                          pendingPhotoBase64: _pendingPhotoBase64,
                          onCancelPhoto: _pendingPhotoBase64 != null
                              ? () => setState(() => _pendingPhotoBase64 = null)
                              : null,
                          mentionCandidates: _mentionCandidates,
                          mentionAllowAll: false,
                        )
                       ],
                     ),
                   ),
                 ),
               ],
             ),
           ),
           ),
           if (_showCallOverlay)
            Positioned.fill(
              child: ChatCallOverlay(
                session: CallProvider.instance.activeSession!,
                onExpand: _expandCall,
                onEnd: () async {
                  final sess = CallProvider.instance.activeSession;
                  if (sess != null) await sess.end();
                  unawaited(CallProvider.instance.clearSession());
                },
              ),
            ),
        ],
      ),
      ),
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
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(SnackBar(content: Text(s.msgCallInProgress)));
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
      showAnonPromptDialog(context);
      return;
    }
    try {
      final callId = await CallService.instance.startCall(
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
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.errGeneric)));
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



// ── View Once / Photo Viewer — pindah ke ../widgets/private_chat_message.dart ──
