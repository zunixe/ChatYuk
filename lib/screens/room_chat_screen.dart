import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:provider/provider.dart';
import '../providers/message_reaction_provider.dart';
import '../providers/notification_prefs_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../models/room_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/storage_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/chat_service.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../core/cache/offline_outbox.dart';
import '../services/room_service.dart';
import '../utils.dart';
import '../main.dart';
import '../services/private_room_service.dart';
import '../services/room_broadcast_service.dart';
import 'room_members_sheet.dart';
import 'group_info_screen.dart';
import 'group_media_screen.dart';
import '../widgets/app_gesture.dart';
import '../widgets/date_chip.dart';
import '../widgets/private_chat_message.dart';
import 'room_chat/widgets/room_widgets.dart';
import 'room_chat/widgets/room_message_bubble.dart';
import 'private_chat/widgets/coin_gift_dialogs.dart';
import '../widgets/chat_composer_input.dart';
import '../utils/mention.dart';
import '../widgets/gift_fly_overlay.dart';
import '../widgets/room_gift_panel.dart';
import '../config/gifts.dart';
import 'private_chat_screen.dart';
import 'user_info_screen.dart';
import '../providers/theme_provider.dart';
import '../services/call_notification.dart';
import 'package:flutter/services.dart';
import '../widgets/message_reaction_bar.dart';
import '../mixins/chat_selection_mixin.dart';
import '../mixins/chat_outbox_mixin.dart';
import '../mixins/chat_photo_send_mixin.dart';
import '../mixins/chat_send_mixin.dart';

// Isolate helpers untuk proses foto (sama seperti private chat).
class RoomChatScreen extends StatefulWidget {
  final RoomModel room;
  const RoomChatScreen({super.key, required this.room});

  @override
  State<RoomChatScreen> createState() => _RoomChatScreenState();
}

class _RoomChatScreenState extends State<RoomChatScreen>
    with
        WidgetsBindingObserver,
        ChatOutboxMixin<RoomChatScreen>,
        ChatSelectionMixin<RoomChatScreen>,
        ChatPhotoSendMixin<RoomChatScreen>,
        ChatSendMixin<RoomChatScreen> {
  final _msgCtrl = TextEditingController();

  // ── Kontrak ChatSelectionMixin ──
  @override
  String get chatKind => 'room';

  @override
  String get chatId => widget.room.id;

  @override
  AuthProvider get chatAuth => _auth;

  @override
  ChatProvider get chatProvider => _chat;

  @override
  TextEditingController get chatMsgCtrl => _msgCtrl;

  @override
  void chatFocusComposer() {}

  @override
  void chatScrollToBottom() => _scrollToBottom();

  @override
  Future<bool> chatDeleteMessage(String id) =>
      _chat.deleteRoomMessage(id);

  @override
  String chatDeletedLabel(S s) => s.msgDeletedRoom;

  @override
  Map<String, String> get chatReactionKnownNames => const {};

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
    await _chat.sendRoomMessage(
      roomId: widget.room.id,
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
  String get photoUploadChatId => 'room_${widget.room.id}';

  @override
  String get photoSeed => widget.room.id;

  @override
  void photoOnSent(String kind) {}

  @override
  void photoFirstBonus(PointsProvider pp) {}

  @override
  void photoSetPreview(String base64) {
    setState(() => _pendingPhotoBase64 = base64);
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
    // Private room: cek role SEBELUM kirim — komposer interaktif sejak
    // awal (tanpa gerbang loading). Bukan member → snackbar ajak join.
    if (isPrivateRoom && !_roleChecked) {
      _myRole = await PrivateRoomService.instance.myRole(widget.room.id);
      _roleChecked = true;
      if (!mounted) return false;
      setState(() {});
      if (_myRole == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<LocaleProvider>().s.privateRoomNeedApproval,
            ),
          ),
        );
        return false;
      }
    }
    return true;
  }

  @override
  void sendCancelEdit() => cancelEdit();

  @override
  Future<bool> sendEditPersist(MessageModel editing, String raw) =>
      ChatService().editRoomMessage(editing.id, raw);

  @override
  Future<void> sendDispatchText({
    required String text,
    required MessageModel? reply,
    required List<Mention> mentions,
  }) async {
    await _chat.sendRoomMessage(
      roomId: widget.room.id,
      senderId: _auth.uid!,
      senderName: _auth.profile!.nickname,
      senderGender: _auth.profile!.gender,
      text: text,
      repliedToId: reply?.id,
      repliedToText: reply?.text,
      repliedToSenderName: reply?.senderName,
      mentions: mentions,
    );
  }

  @override
  void sendOnSentText() {
    final pp = context.read<PointsProvider>();
    if (pp.enabled) {
      pp.showPointsToast(
        context,
        context.read<LocaleProvider>().s.pointsDeduct(1),
      );
    }
    _roomSendCount++;
    if (_roomSendCount == 5) {
      _pointsProv?.oneTimeBonus('first_room_chat', 5).then((earned) {
        if (earned && mounted) {
          final s = context.read<LocaleProvider>().s;
          _pointsProv?.showPointsToast(
            context,
            s.pointsGain(5, s.reasonRoomChat),
          );
        }
      });
    }
    _scrollToBottom();
  }
  final _scrollCtrl = ScrollController();
  bool _showUsers = false;
  bool _sheetOpen = false;
  late AuthProvider _auth;
  late ChatProvider _chat;
  int _lastMsgCount = 0;
  bool _readBonusClaimed = false;
  int _roomSendCount = 0;
  PointsProvider? _pointsProv;
  Timer? _presenceTimer;
  String? _pendingPhotoBase64;

  late Stream<List<MessageModel>> _msgsStream;
  late Stream<List<UserModel>> _usersStream;

  // ── Optimistic + antrean offline (centang-1 → centang-2 saat online) ──
  final List<MessageModel> _pending = [];
  final Set<String> _queuedIds = {};
  final Set<String> _confirmedPhotoIds = {};
  final Set<String> _confirmedVoiceIds = {};
  late final DateTime _openedAt;
  ConnectivityProvider? _connProv;
  VoidCallback? _connListener;
  bool _flushingOutbox = false;

  // ── Room gift (live) ──
  final _giftFly = GiftFlyController();
  // Insertion-order terjaga — cap FIFO (skip terlama) tanpa clear().
  Set<String> _seenGiftMsgIds = {};

  // ── Private room v2 ──
  String? _myRole;
  bool _muted = false;
  String? _highlightId;
  final Map<String, GlobalKey> _msgKeys = {};
  ChatMessageStream? _msgsHandle;
  StreamSubscription<List<MessageModel>>? _msgsSub;
  List<MessageModel> _lastMsgs = const [];
  StreamSubscription<List<UserModel>>? _usersSub;
  // Strip user online persisten: tahan list terakhir saat stream blip
  // kosong; teks "tidak ada yang online" hanya setelah kosong terkonfirmasi.
  List<UserModel> _lastRoomUsers = const [];
  Timer? _roomUsersEmptyTimer;
  bool _roomUsersEmpty = false;
  String? _liveUid;
  int _pendingCount = 0;
  RoomBroadcastSession? _broadcastSession;
  Timer? _livePoll;
  bool _isGrantedBroadcast = false;
  StreamSubscription<Map<String, Map<String, int>>>? _reactionsSub;
  StreamSubscription<Set<String>>? _starredSub;
  bool get isPrivateRoom => widget.room.isPrivate == true;
  bool get canModerate =>
      isPrivateRoom && (_myRole == 'owner' || _myRole == 'admin');
  bool get iAmBroadcasting =>
      _broadcastSession != null &&
      _broadcastSession!.isBroadcaster &&
      _liveUid == _auth.uid;
  bool get isGrantedBroadcast => _isGrantedBroadcast;
  bool get watchingLive =>
      _broadcastSession != null && !iAmBroadcasting;

  /// Slider ukuran font chat berubah → rebuild bubble & composer room.
  void _onFontScaleChanged() {
    if (mounted) setState(() {});
  }

  // ── Mention @ ──
  // Grup/private room → anggota (termasuk offline). Global room → user online.
  List<Map<String, dynamic>> _roomMembers = const [];
  List<Mention> get _mentionCandidates {
    final myUid = _auth.uid;
    final seen = <String>{};
    final out = <Mention>[];
    if (isPrivateRoom) {
      for (final m in _roomMembers) {
        final uid = '${m['user_id'] ?? ''}';
        final name = '${m['nickname'] ?? ''}';
        if (uid.isEmpty || uid == myUid || !seen.add(uid)) continue;
        out.add(Mention(uid: uid, name: name));
      }
    } else {
      for (final u in _lastRoomUsers) {
        if (u.uid.isEmpty || u.uid == myUid || !seen.add(u.uid)) continue;
        out.add(Mention(uid: u.uid, name: u.nickname));
      }
    }
    return out;
  }

  /// Target `@all` (owner/admin) — dibatasi 100 uid agar payload aman.
  List<Mention> _mentionAllExpansion() =>
      _mentionCandidates.take(100).toList();

  /// Resolusi teks → mention ber-uid. `@all` hanya di grup oleh owner/admin.
  
  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    // Ukuran font chat berubah (slider) → rebuild bubble & composer room.
    ChatTextScale.notifier.addListener(_onFontScaleChanged);
    _auth = context.read<AuthProvider>();
    _chat = context.read<ChatProvider>();
    // DEFER seperti private chat — hindari setState-during-build glitch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) activeChatId.value = widget.room.id;
    });
    final msgsHandle = _chat.getRoomMessages(widget.room.id);
    _msgsHandle = msgsHandle;
    _msgsStream = msgsHandle.stream;
    _usersStream = _chat.getOnlineUsersInRoom(widget.room.id);
    _pointsProv = context.read<PointsProvider>();
    _msgsSub = _msgsStream.listen(_onMessagesForGift);
    // Kandidat mention room global butuh daftar user online walau strip
    // horizontal sedang disembunyikan — simpan snapshot di _lastRoomUsers.
    _usersSub = _usersStream.listen((users) {
      if (users.isNotEmpty) _lastRoomUsers = users;
    });
    if (isPrivateRoom) {
      unawaited(_initPrivate());
    }
    _joinRoom();
    _startPresenceHeartbeat();
    _scrollCtrl.addListener(_onRoomScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Cache dulu (tampil instan), stream menimpa sesudahnya.
      context.read<MessageReactionProvider>().loadCachedReactions(widget.room.id).then((
        cached,
      ) {
        if (!mounted || cached.isEmpty || reactions.isNotEmpty) return;
        setState(() => reactions = cached);
      });
      _reactionsSub = context.read<MessageReactionProvider>()
          .watchReactions(widget.room.id)
          .listen((m) {
        if (mounted) setState(() => reactions = m);
        context.read<MessageReactionProvider>().saveCachedReactions(widget.room.id, m);
      });
      _starredSub = context.read<MessageReactionProvider>()
          .watchStarred(widget.room.id)
          .listen((m) {
        if (mounted) setState(() => starredIds = m);
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

  // ── Private room v2 ──
  bool _roleChecked = false;
  bool _broadcastStarting = false;
  bool _stageMinimized = false;
  Offset? _pipPos;
  Size _pipSize = const Size(140, 190);
  bool _pipResizing = false;
  Size _pipResizeStartSize = Size.zero;
  Offset _pipResizeStartLocal = Offset.zero;

  /// Satu pintu mulai broadcast — cegah double-tap (toggle ke stop) dan
  /// beri feedback loading di tombol/banner.
  Future<void> _onStartBroadcastTap() async {
    if (_broadcastStarting || iAmBroadcasting) return;
    setState(() => _broadcastStarting = true);
    try {
      if (_liveUid != _auth.uid) {
        await PrivateRoomService.instance.startBroadcast(widget.room.id);
        await _refreshLiveUid();
      }
      await _startBroadcastSession();
    } finally {
      if (mounted) setState(() => _broadcastStarting = false);
    }
  }

  Future<void> _initPrivate() async {
    dlog('[BDBG] initPrivate start room=${widget.room.id} uid=${_auth.uid}');
    try {
      _myRole = await PrivateRoomService.instance.myRole(widget.room.id);
      dlog('[BDBG] myRole=$_myRole isPrivate=${widget.room.isPrivate}');
      // Anggota untuk kandidat mention grup (termasuk yang offline).
      try {
        _roomMembers =
            await PrivateRoomService.instance.listMembers(widget.room.id);
      } catch (_) {}
      if (canModerate) {
        try {
          final req = await PrivateRoomService.instance
              .listJoinRequests(widget.room.id);
          _pendingCount = req.length;
        } catch (_) {}
      }
      await _refreshLiveUid();
      try {
        _muted = await context.read<NotificationPrefsProvider>().isChatMuted(widget.room.id);
      } catch (_) {}
      try {
        final granted = await PrivateRoomService.instance.myBroadcastGranted(widget.room.id);
        _isGrantedBroadcast = granted || _liveUid == _auth.uid;
        dlog('[BDBG] init granted=$_isGrantedBroadcast live=$_liveUid');
      } catch (e) {
        dlog('[BDBG] init myBroadcastGranted error: $e');
      }
      _listenRoomLive();
      // Fallback poll JARANG (30s): realtime channel (_listenRoomLive)
      // adalah jalur utama update live_uid/grant — poll 5s seumur room
      // buang-buang RPC & battery.
      _livePoll?.cancel();
      _livePoll = Timer.periodic(const Duration(seconds: 30), (_) {
        _refreshLiveUid();
        _refreshGrant();
        _ensureViewerSession();
      });
    } catch (e) {
      dlog('[BDBG] initPrivate ERROR: $e');
    }
    _roleChecked = true;
    if (!mounted) return;
    setState(() {});
  }

  RealtimeChannel? _roomLiveChannel;

  void _listenRoomLive() {
    try {
      final old = _roomLiveChannel;
      _roomLiveChannel = null;
      if (old != null) unawaited(Supabase.instance.client.removeChannel(old));
    } catch (_) {}
    try {
      final ch = Supabase.instance.client.channel('room-live-${widget.room.id}');
      ch.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'rooms',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.room.id),
        callback: (payload) {
          if (!mounted) return;
          final live = payload.newRecord['live_uid']?.toString();
          dlog('[BDBG] realtime rooms update live=$live current=$_liveUid');
          if (live != _liveUid) {
            _liveUid = (live != null && live.isNotEmpty) ? live : null;
            setState(() {});
          }
          // Selalu sync — kalau live_uid sama dengan sebelumnya (broadcast
          // restart), viewer tetap harus mulai sesi.
          _refreshGrant();
          _syncBroadcastSession();
        },
      );
      ch.subscribe();
      _roomLiveChannel = ch;
    } catch (_) {}
  }

  Future<void> _refreshGrant() async {
    try {
      final granted = await PrivateRoomService.instance.myBroadcastGranted(widget.room.id);
      final g = granted || _liveUid == _auth.uid;
      dlog('[BDBG] refreshGrant granted=$granted live=$_liveUid uid=${_auth.uid} g=$g');
      if (mounted && g != _isGrantedBroadcast) setState(() => _isGrantedBroadcast = g);
    } catch (e) {
      dlog('[BDBG] refreshGrant error: $e');
    }
  }

  // ── Room gift (live) ──

  /// Setiap batch pesan masuk, ambil type='gift' yang belum ditampilkan
  /// → mainkan animasi fly. Stream mengirim snapshot penuh, jadi
  /// dedup via id pesan.
  void _onMessagesForGift(List<MessageModel> msgs) {
    _lastMsgs = msgs;
    // Cap peta key lompat-pesan — tanpa ini tumbuh tanpa batas di
    // sesi panjang (GlobalKey per pesan yang pernah dirender).
    if (_msgKeys.length > 500) {
      final keep = msgs.map((m) => m.id).toSet();
      _msgKeys.removeWhere((k, _) => !keep.contains(k));
    }
    final gifts = msgs.where((m) => m.type == 'gift');
    for (final m in gifts) {
      final id = m.id;
      if (_seenGiftMsgIds.contains(id)) continue;
      _seenGiftMsgIds.add(id);
      final gift = giftById(m.text);
      if (gift == null) continue;
      // Snapshot lama tidak diputar ulang: hanya gift yang masuk live
      // (timestamp < 5 detik lalu) yang dianimasikan. Guard fresh ini
      // yang mencegah re-play — cap seen-set tidak perlu clear() (clear
      // bikin gift lama yang masih di list dianggap baru lagi).
      final fresh =
          DateTime.now().difference(m.timestamp) < const Duration(seconds: 5);
      if (!fresh) continue;
      _giftFly.push(gift, m.senderName, 1);
    }
    // Dedupe bubble optimistik milik sendiri (centang-1 → centang-2):
    // teks dicocokkan isi, foto/voice FIFO via id server (thumbnail di
    // stream beda dari base64 pending). Hanya pesan setelah layar dibuka
    // yang menghapus pending foto/voice (history lama di-skip).
    if (_pending.isNotEmpty) {
      var changed = false;
      final myId = _auth.uid;
      if (myId != null) {
        final confirmedTexts = msgs
            .where((m) => m.senderId == myId && m.type == 'text')
            .map((m) => m.text)
            .toList();
        for (final text in confirmedTexts) {
          final idx = _pending.indexWhere(
            (p) => p.type == 'text' && p.text == text,
          );
          if (idx != -1) {
            _queuedIds.remove(_pending[idx].id);
            _pending.removeAt(idx);
            changed = true;
          }
        }
        for (final m in msgs) {
          if (m.senderId == myId &&
              (m.type == 'image' || m.type == 'view_once') &&
              m.timestamp.isAfter(_openedAt) &&
              _confirmedPhotoIds.add(m.id)) {
            final idx = _pending.indexWhere(
              (p) => p.type == 'image' || p.type == 'view_once',
            );
            if (idx != -1) {
              _queuedIds.remove(_pending[idx].id);
              _pending.removeAt(idx);
              changed = true;
            }
          }
        }
        for (final m in msgs) {
          if (m.senderId == myId &&
              m.type == 'voice' &&
              m.timestamp.isAfter(_openedAt) &&
              _confirmedVoiceIds.add(m.id)) {
            final idx = _pending.indexWhere((p) => p.type == 'voice');
            if (idx != -1) {
              _queuedIds.remove(_pending[idx].id);
              _pending.removeAt(idx);
              changed = true;
            }
          }
        }
      }
      if (changed && mounted) setState(() {});
    }
    // Cap seen-set TANPA clear: buang yang paling lama (FIFO) — id gift
    // lama tidak bisa re-play karena guard fresh di atas sudah memfilter.
    if (_seenGiftMsgIds.length > 500) {
      _seenGiftMsgIds = _seenGiftMsgIds
          .skip(_seenGiftMsgIds.length - 300)
          .toSet();
    }
  }

  Future<void> _openRoomGiftPanel() async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    if (!auth.canUsePaid) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(auth.profile?.isRegistered != true
            ? s.errCoinRegisterOnly
            : s.msgVerifyToUsePaid),
      ));
      return;
    }
    final pick = await RoomGiftPanel.show(context);
    if (pick == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await _chat.sendRoomGift(
        widget.room.id,
        pick.gift.id,
        qty: pick.qty,
      );
      if (res['ok'] == true) {
        if (res['points'] != null) {
          _pointsProv?.setPoints((res['points'] as num).toInt());
        }
        if (mounted) {
          _pointsProv?.showPointsToast(
            context,
            s.giftSentToast(s.isId ? pick.gift.nameId : pick.gift.nameEn),
          );
        }
      }
    } catch (e) {
      final msg = e.toString();
      messenger.showSnackBar(SnackBar(
        content: Text(msg.contains('Not enough')
            ? s.giftInsufficient
            : msg.contains('registered')
                ? s.errCoinRegisterOnly
                : s.errSendCoin),
      ));
    }
  }

  /// Pastikan viewer session jalan kalau ada orang lain yang broadcast.
  /// Menutup celah: live_uid tidak berubah (broadcast restart) atau event
  /// realtime terlewat → tanpa ini viewer harus keluar-masuk room dulu.
  Future<void> _ensureViewerSession() async {
    if (!isPrivateRoom || !mounted) return;
    if (_liveUid == null || _liveUid == _auth.uid) return;
    if (_broadcastSession != null && !_broadcastSession!.isBroadcaster) return;
    try {
      final cnt = await PrivateRoomService.instance.broadcastCount(widget.room.id);
      if (!mounted) return;
      if (cnt == 0) return;
      unawaited(_startViewerSession());
    } catch (_) {}
  }

  Future<void> _refreshLiveUid() async {
    final row = await RoomService().fetchRoomById(widget.room.id);
    final live = row?['live_uid']?.toString();
    dlog('[BDBG] refreshLiveUid fetched=$live current=$_liveUid');
    if (!mounted) return;
    if (live == _liveUid) return;
    setState(() {
      _liveUid = (live != null && live.isNotEmpty) ? live : null;
    });
    _syncBroadcastSession();
  }

  void _syncBroadcastSession() {
    final iAmLive = _liveUid != null && _liveUid == _auth.uid;
    final someoneElse = _liveUid != null &&
        _liveUid != _auth.uid;

    if (iAmLive) {
      // Jangan auto-start — biarkan user klik manual dari chip/broadcast button.
    } else if (someoneElse) {
      if (_broadcastSession == null || _broadcastSession!.isBroadcaster) {
        unawaited(_startViewerSession());
      }
    } else {
      // Tidak ada live → bersihkan.
      unawaited(_broadcastSession?.stop());
      _broadcastSession = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _startBroadcastSession() async {
    // cap 4
    try {
      final cnt = await PrivateRoomService.instance.broadcastCount(widget.room.id);
      if (cnt >= 4) {
        if (!mounted) return;
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.roomBroadcastFull), backgroundColor: AppTheme.danger),
        );
        return;
      }
    } catch (_) {}
    unawaited(_broadcastSession?.stop());
    _broadcastSession = null;
    final session = RoomBroadcastSession(
      roomId: widget.room.id,
      isBroadcaster: true,
      onEnded: () {
        CallNotification.stopLive();
        if (mounted) {
          setState(() {
            _broadcastSession = null;
            _liveUid = null;
          });
        }
      },
    );
    _broadcastSession = session;
    try {
      await session.start();
      if (!mounted) return;
      // Foreground service: broadcast tetap hidup saat app di-background
      CallNotification.startLive(
          text: context.read<LocaleProvider>().s.broadcastLiveNotif);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('Broadcast full') ? context.read<LocaleProvider>().s.roomBroadcastFull : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _broadcastSession = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _startViewerSession() async {
    unawaited(_broadcastSession?.stop());
    _broadcastSession = null;
    final session = RoomBroadcastSession(
      roomId: widget.room.id,
      isBroadcaster: false,
      onEnded: () {
        CallNotification.stopLive();
        if (mounted) {
          setState(() => _broadcastSession = null);
        }
      },
    );
    _broadcastSession = session;
    await session.start();
    if (!mounted) return;
    // Foreground service: menonton broadcast tetap hidup di background
    CallNotification.startLive(
        text: context.read<LocaleProvider>().s.broadcastWatchingNotif);
    await session.requestStream();
    if (mounted) setState(() {});
  }


  /// Hand raise — kirim signal ke admin.
  Future<void> _raiseHand() async {
    await PrivateRoomService.instance.sendSignal(
      widget.room.id,
      type: 'hand_raise',
      payload: {'nickname': _auth.profile?.nickname ?? ''},
    );
    if (!mounted) return;
    final s = context.read<LocaleProvider>().s;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.roomHandRaised),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Menu ⋮ grup ala WA: tambah anggota, info, media, cari, bisu, lainnya.
  void _onGroupMenu(String v) {
    switch (v) {
      case 'add':
        unawaited(() async {
          // Exclude MEMBER ASLI (bukan tebakan dari pengirim pesan) —
          // tanpa ini member lama bisa muncul lagi di picker.
          final memberIds = <String>{};
          try {
            final members = await PrivateRoomService.instance
                .listMembers(widget.room.id);
            for (final m in members) {
              memberIds.add('${m['user_id'] ?? ''}');
            }
          } catch (_) {}
          if (!mounted) return;
          await showGroupInvitePicker(
            context: context,
            roomId: widget.room.id,
            excludeUids: memberIds,
            onInvited: () {},
          );
        }());
        break;
      case 'info':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupInfoScreen(
              room: widget.room,
              myRole: _myRole ?? 'member',
            ),
          ),
        );
        break;
      case 'media':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupMediaScreen(room: widget.room),
          ),
        );
        break;
      case 'search':
        _openRoomSearch();
        break;
      case 'mute':
        _toggleMute();
        break;
      case 'more':
        _showMoreMenu();
        break;
    }
  }

  Future<void> _toggleMute() async {
    final s = context.read<LocaleProvider>().s;
    final next = !_muted;
    try {
      // Sinkron ke server (rooms.muted_by) + cermin lokal — model sama
      // dengan mute private chat, biar konsisten antar device.
      await _chat.muteRoom(widget.room.id, next);
      if (!mounted) return;
      setState(() => _muted = next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next ? s.roomMutedOn : s.roomMutedOff)),
      );
    } catch (_) {}
  }

  /// Cari pesan dalam room: sheet hasil → tap lompat ke pesan
  /// (loadOlder berulang bila belum termuat, maks 10x).
  Future<void> _openRoomSearch() async {
    final s = context.read<LocaleProvider>().s;
    final qCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool searching = false;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> doSearch(String q) async {
            final query = q.trim();
            if (query.length < 2) {
              setSheet(() => results = []);
              return;
            }
            setSheet(() => searching = true);
            try {
              final rows = await Supabase.instance.client
                  .from('messages')
                  .select('id,text,sender_name,sender_id,created_at')
                  .eq('room_id', widget.room.id)
                  .ilike('text', '%$query%')
                  .order('created_at', ascending: false)
                  .limit(30);
              if (ctx.mounted) {
                setSheet(() {
                  results = (rows as List)
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList();
                  searching = false;
                });
              }
            } catch (_) {
              if (ctx.mounted) setSheet(() => searching = false);
            }
          }

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: TextField(
                      autofocus: true,
                      style:
                          AppText.body.copyWith(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon:
                            const Icon(Icons.search_rounded, size: 20),
                        hintText: s.roomSearchHint,
                      ),
                      onChanged: (q) {
                        // Debounce: guard sheet tertutup dulu, baru sentuh
                        // controller (setelah dispose = exception).
                        Future.delayed(
                            const Duration(milliseconds: 350), () {
                          if (!ctx.mounted) return;
                          if (qCtrl.text != q) return;
                          doSearch(q);
                        });
                      },
                    ),
                  ),
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  else if (results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(s.roomSearchEmpty,
                          style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary)),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (_, i) {
                          final r = results[i];
                          return ListTile(
                            dense: true,
                            title: Text('${r['text'] ?? ''}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.bodySmall),
                            subtitle: Text(
                                '${r['sender_name'] ?? '?'}',
                                style: AppText.caption.copyWith(
                                    color: AppTheme.textSecondary)),
                            onTap: () {
                              Navigator.pop(ctx);
                              _jumpToMessage('${r['id'] ?? ''}');
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
    qCtrl.dispose();
  }

  /// Lompat ke pesan: loadOlder berulang bila belum termuat (maks 10x),
  /// lalu scroll + highlight 2 detik.
  Future<void> _jumpToMessage(String id) async {
    if (id.isEmpty || _msgsHandle == null) return;
    for (var i = 0;
        i < 10 && !_lastMsgs.any((m) => m.id == id);
        i++) {
      try {
        await _msgsHandle!.loadOlder();
      } catch (_) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }
    if (!mounted) return;
    final key = _msgKeys[id];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    setState(() => _highlightId = id);
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _highlightId = null);
  }

  /// Submenu "Lainnya": keluar grup (+ hapus grup khusus owner).
  void _showMoreMenu() {
    final s = context.read<LocaleProvider>().s;
    final isOwner = _myRole == 'owner';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.exit_to_app_rounded),
              title: Text(s.menuExitGroup),
              onTap: () {
                Navigator.pop(ctx);
                _confirm(s.exitGroupTitle, s.exitGroupBody, _exitGroup);
              },
            ),
            if (isOwner)
              ListTile(
                leading:
                    Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
                title: Text(s.menuDeleteGroup,
                    style: TextStyle(color: AppTheme.danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirm(
                      s.deleteGroupTitle, s.deleteGroupBody, _deleteGroup);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirm(String title, String body, Future<void> Function() fn) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.read<LocaleProvider>().s.btnCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await fn();
            },
            child: Text(context.read<LocaleProvider>().s.btnDelete),
          ),
        ],
      ),
    );
  }

  Future<void> _exitGroup() async {
    try {
      await PrivateRoomService.instance.leave(widget.room.id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<LocaleProvider>().s.errGeneric), backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _deleteGroup() async {
    try {
      await RoomService().deleteRoom(widget.room.id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<LocaleProvider>().s.errGeneric), backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _openMembersSheet() async {    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.bgScreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => RoomMembersSheet(
        roomId: widget.room.id,
        myRole: _myRole ?? 'member',
        onChanged: () async {
          if (canModerate) {
            try {
              final req = await PrivateRoomService.instance
                  .listJoinRequests(widget.room.id);
              _pendingCount = req.length;
            } catch (_) {}
          }
          await _refreshLiveUid();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  /// Heartbeat presence: refresh joined_at tiap 60 detik selama room terbuka.
  /// Kalau app di-kill/force-stop, heartbeat berhenti → row presence basi
  /// dan otomatis hilang dari daftar online room setelah 5 menit.
  void _startPresenceHeartbeat() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      final profile = _auth.profile;
      if (profile == null) return;
      _chat.joinRoom(widget.room.id, profile);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = _auth.uid;
    if (uid == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // App di-background/ditutup → keluar dari room supaya tidak jadi
      // ghost "online" di daftar member room.
      // Hentikan heartbeat presence juga — kalau tidak, timer terus
      // re-join tiap 60s dan membangkitkan row presence ghost.
      _presenceTimer?.cancel();
      _chat.leaveRoom(widget.room.id, uid);
    } else if (state == AppLifecycleState.resumed) {
      if (mounted && _auth.profile != null) {
        _chat.joinRoom(widget.room.id, _auth.profile!);
        _startPresenceHeartbeat();
      }
    }
  }

  Future<void> _joinRoom() async {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    if (auth.profile != null) {
      await chat.joinRoom(widget.room.id, auth.profile!);
      await chat.loadBlockedUids(auth.uid!);
    }
  }

  void _onRoomScroll() {
    if (_readBonusClaimed) return;
    if (_scrollCtrl.hasClients && _scrollCtrl.position.pixels < 300) {
      _readBonusClaimed = true;
      _pointsProv?.roomReadBonus().then((_) {
        if (mounted && _pointsProv?.enabled == true) {
          final s = context.read<LocaleProvider>().s;
          _pointsProv?.showPointsToast(
            context,
            s.pointsGain(2, s.reasonRoomRead),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    hideActionBar();
    _reactionsSub?.cancel();
    _starredSub?.cancel();
    try {
      final l = _connListener;
      if (l != null) _connProv?.removeListener(l);
    } catch (_) {}
    _connListener = null;
    _connProv = null;
    ChatTextScale.notifier.removeListener(_onFontScaleChanged);
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _roomUsersEmptyTimer?.cancel();
    _livePoll?.cancel();
    _giftFly.dispose();
    unawaited(_msgsSub?.cancel());
    _msgsSub = null;
    unawaited(_usersSub?.cancel());
    _usersSub = null;
    try {
      final ch = _roomLiveChannel;
      _roomLiveChannel = null;
      if (ch != null) unawaited(Supabase.instance.client.removeChannel(ch));
    } catch (_) {}
    unawaited(_broadcastSession?.stop());
    // DEFER: dispose berjalan saat widget tree terkunci (unmount IndexedStack
    // saat pindah tab) — menulis ValueNotifier sekarang memicu
    // markNeedsBuild pada CallBanner → glitch "widget tree was locked".
    final roomToClear = widget.room.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (activeChatId.value == roomToClear) activeChatId.value = null;
    });
    final uid = _auth.uid;
    if (uid != null) {
      _chat.leaveRoom(widget.room.id, uid);
    }
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool get _isNearBottom {
    if (!_scrollCtrl.hasClients) return true;
    return _scrollCtrl.position.pixels < 100;
  }

  bool _isSending = false;

  // ── Antrean offline: implementasi BERSAMA di ChatOutboxMixin ──
  bool get outboxIsOnline => _connProv?.online ?? true;

  @override
  String get outboxKind => 'room';

  @override
  String get outboxChatId => widget.room.id;

  @override
  String get outboxUploadChatId => 'room_${widget.room.id}';

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
    await _chat.sendRoomMessage(
      roomId: widget.room.id,
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
    _roomSendCount++;
    if (_roomSendCount == 5) {
      _pointsProv?.oneTimeBonus('first_room_chat', 5).then((earned) {
        if (earned && mounted) {
          final s = context.read<LocaleProvider>().s;
          _pointsProv?.showPointsToast(
            context,
            s.pointsGain(5, s.reasonRoomChat),
          );
        }
      });
    }
  }


  Future<void> _sendVoiceMessage(String filePath, int durationMs) async {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    // Offline: bubble tetap tampil (centang-1) + antre, terkirim otomatis
    // saat koneksi pulih. Voice tidak pakai poin.
    Future<void> queueVoiceOffline(Uint8List bytes, File f) async {
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
        durationMs: durationMs,
      );
      setState(() => _pending.add(optimisticOffline));
      _scrollToBottom();
      try {
        await f.delete();
      } catch (_) {}
      await queueOffline(
        pending: optimisticOffline,
        pointsKind: 'none',
        pointsDeducted: true,
        imagePayload: base64Encode(bytes),
        needsUpload: true,
        uploadKind: 'voice',
        durationMs: durationMs,
      );
    }

    try {
      final f = File(filePath);
      if (!await f.exists()) return;
      final bytes = await f.readAsBytes();
      if (!outboxIsOnline) {
        await queueVoiceOffline(bytes, f);
        return;
      }
      final storagePath = await context.read<StorageProvider>().uploadVoice(
        chatId: 'room_${widget.room.id}',
        bytes: bytes,
      );
      if (storagePath == null || storagePath.isEmpty) {
        if (!outboxIsOnline) {
          await queueVoiceOffline(bytes, f);
          return;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.read<LocaleProvider>().s.errVoiceUploadFailed)),
          );
        }
        return;
      }
      final pendingVoice = MessageModel(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        isRegistered: profile.isRegistered,
        text: '',
        type: 'voice',
        imageData: storagePath,
        timestamp: DateTime.now(),
        durationMs: durationMs,
      );
      setState(() => _pending.add(pendingVoice));
      _scrollToBottom();
      await chat.sendRoomMessage(
        roomId: widget.room.id,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: '',
        type: 'voice',
        imageData: storagePath,
        durationMs: durationMs,
      );
      try { await f.delete(); } catch (_) {}
      _scrollToBottom();
    } catch (e) {
      dlog('[RoomVoice] send error: $e');
      if (OfflineOutbox.isNetworkError(e) || !outboxIsOnline) {
        try {
          final f = File(filePath);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            await queueVoiceOffline(bytes, f);
            return;
          }
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.read<LocaleProvider>().s.errSendFailed)),
        );
      }
    }
  }


  // LayerLink per pesan — anchor action bar (Balas / Hapus) tepat di atas bubble.


  bool _showAttachRow = false;

  void _toggleAttachRow() {
    if (!_showAttachRow) FocusScope.of(context).unfocus();
    setState(() => _showAttachRow = !_showAttachRow);
  }




  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final auth = context.read<AuthProvider>();
    final s = context.watch<LocaleProvider>().s;
    final points = context.watch<PointsProvider>();

    return PopScope(
      canPop: !inSelection,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inSelection) clearSelection();
      },
      child: Scaffold(
      backgroundColor: AppTheme.bgCard,
      appBar: inSelection ? buildSelectionAppBar() : AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.room.icon, style: TextStyle(fontSize: AppGlyph.sm)),
            SizedBox(width: 8),
            Text(widget.room.name),
          ],
        ),
        actions: [
          if (isPrivateRoom) ...[
            // Hand-raise utk member biasa; Start broadcast utk yang live_uid == saya (di-grant)
            if (_liveUid == null && !canModerate && !isGrantedBroadcast)
              IconButton(
                tooltip: s.roomActionHandRaise,
                icon: const Icon(Icons.pan_tool_rounded),
                onPressed: _raiseHand,
              ),
            if (((_liveUid == _auth.uid && !iAmBroadcasting) || (_liveUid == null && isGrantedBroadcast && !iAmBroadcasting)) || _broadcastStarting)
              GestureDetector(
                onTap: _broadcastStarting ? null : _onStartBroadcastTap,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: _broadcastStarting ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_broadcastStarting)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(Icons.videocam_rounded, color: AppTheme.primary, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        _broadcastStarting
                            ? (s.roomBroadcastConnecting)
                            : s.privateRoomsStartBroadcast,
                        style: AppText.label.copyWith(
                          color: AppTheme.primary.withValues(alpha: _broadcastStarting ? 0.6 : 1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (iAmBroadcasting)
              IconButton(
                tooltip: s.privateRoomsStopBroadcast,
                icon: Icon(Icons.cancel_rounded, color: AppTheme.danger),
                onPressed: () async {
                  await PrivateRoomService.instance.stopBroadcast(widget.room.id);
                  await _broadcastSession?.stop();
                  if (mounted) setState(() { _broadcastSession = null; });
                },
              ),
            IconButton(
              tooltip: s.privateRoomsMembersTitle,
              icon: Badge(
                isLabelVisible:
                    canModerate && _pendingCount > 0,
                label: Text('$_pendingCount'),
                child: const Icon(Icons.group_outlined),
              ),
              onPressed: _openMembersSheet,
            ),
            PopupMenuButton<String>(
              tooltip: s.menuMore,
              icon: const Icon(Icons.more_vert),
              onSelected: _onGroupMenu,
              itemBuilder: (_) => [
                if (canModerate)
                  PopupMenuItem(
                    value: 'add',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_add_alt_rounded,
                          size: 20),
                      title: Text(s.menuAddMembers),
                    ),
                  ),
                PopupMenuItem(
                  value: 'info',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading:
                        const Icon(Icons.info_outline_rounded, size: 20),
                    title: Text(s.menuGroupInfo),
                  ),
                ),
                PopupMenuItem(
                  value: 'media',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.photo_library_outlined,
                        size: 20),
                    title: Text(s.menuGroupMedia),
                  ),
                ),
                PopupMenuItem(
                  value: 'search',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.search_rounded, size: 20),
                    title: Text(s.menuSearchMessages),
                  ),
                ),
                PopupMenuItem(
                  value: 'mute',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        _muted
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_outlined,
                        size: 20),
                    title: Text(
                        _muted ? s.menuUnmuteNotif : s.menuMuteNotif),
                  ),
                ),
                PopupMenuItem(
                  value: 'more',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading:
                        const Icon(Icons.more_horiz_rounded, size: 20),
                    title: Text(s.menuMore),
                  ),
                ),
              ],
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: RoomHeaderToggle(
                showUsers: _showUsers,
                onTap: () => setState(() => _showUsers = !_showUsers),
              ),
            ),
          ],
        ],
      ),
      body: Builder(builder: (context) {
        final showStageInline = isPrivateRoom &&
            !_stageMinimized &&
            _liveUid != null &&
            _broadcastSession != null;
        final showPip = isPrivateRoom &&
            _stageMinimized &&
            _liveUid != null &&
            _broadcastSession != null;
        // Bottom bar 3-state (private room): sebelum role selesai dicek,
        // tampilkan composer yang SAMA tapi non-interaktif — layout stabil
        // sejak frame pertama, tidak ada fase aktif-palsu lalu hilang.
        // SafeArea bawah: composer tidak kepotong nav bar Android.
        final Widget bottomBar;
        if (isPrivateRoom && _roleChecked && _myRole == null) {
          // Pending approval: composer diganti bar info — jangan biarkan user
          // mencoba kirim lalu gagal diam-diam.
          bottomBar = Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            color: AppTheme.bgCard,
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.privateRoomNeedApproval,
                    style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          );
        } else {
          final input = ChatComposerInput(
            controller: _msgCtrl,
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
            onSendVoice: _sendVoiceMessage,
            // Gift (fitur koin) hanya bila sistem koin aktif — hilang
            // total saat dimatikan admin (ikut flag points.enabled).
            onOpenGiftPanel: points.enabled &&
                    isPrivateRoom &&
                    _myRole != 'owner'
                ? _openRoomGiftPanel
                : null,
            pendingPhotoBase64: _pendingPhotoBase64,
            onCancelPhoto: _pendingPhotoBase64 != null
                ? () => setState(() => _pendingPhotoBase64 = null)
                : null,
            mentionCandidates: _mentionCandidates,
            mentionAllowAll: isPrivateRoom && canModerate,
            mentionAllExpansion: _mentionAllExpansion(),
          );
          bottomBar = input;
        }
        final column = Column(
        children: [
          // Banner "menunggu persetujuan" kini mengambang di atas list pesan
          // (overlay) — tidak menggeser layout saat muncul.
          if (isPrivateRoom && isGrantedBroadcast && (!iAmBroadcasting || _broadcastStarting))
            GestureDetector(
              onTap: _broadcastStarting ? null : _onStartBroadcastTap,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: AppTheme.primary.withValues(alpha: 0.12),
                child: Row(
                  children: [
                    if (_broadcastStarting)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(Icons.videocam_rounded, color: AppTheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _broadcastStarting
                            ? s.roomBroadcastConnecting
                            : s.privateRoomsStartBroadcast,
                        style: AppText.bodySmall.copyWith(color: AppTheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppTheme.primary, size: 18),
                  ],
                ),
              ),
            ),
          if (showStageInline) ...[
            _BroadcastStage(
              session: _broadcastSession!,
              isBroadcaster: iAmBroadcasting,
              onMinimize: () => setState(() => _stageMinimized = true),
            ),
          ],
          // User list horizontal — private room selalu tampil, global room via toggle
          if (isPrivateRoom || _showUsers)
            Container(
              height: 90,
              color: AppTheme.bgCard,
              child: StreamBuilder<List<UserModel>>(
                stream: _usersStream,
                builder: (_, snap) {
                  // Persisten anti-glitch: stream presence bisa blip kosong
                  // sesaat (realtime/heartbeat race). Tahan list terakhir;
                  // kosong hanya diakui setelah 4 detik konsisten.
                  final data = snap.data;
                  if (data != null && data.isNotEmpty) {
                    _lastRoomUsers = data;
                    _roomUsersEmpty = false;
                    _roomUsersEmptyTimer?.cancel();
                  } else if (data != null &&
                      data.isEmpty &&
                      _lastRoomUsers.isNotEmpty &&
                      !_roomUsersEmpty) {
                    _roomUsersEmptyTimer?.cancel();
                    _roomUsersEmptyTimer = Timer(
                      const Duration(seconds: 4),
                      () {
                        if (mounted) {
                          setState(() => _roomUsersEmpty = true);
                        }
                      },
                    );
                  }
                  final cached =
                      _roomUsersEmpty ? const <UserModel>[] : _lastRoomUsers;
                  // "Kamu" optimistis: presence sendiri (joinRoom upsert)
                  // butuh roundtrip network → chip sendiri telat muncul
                  // dan menggeser strip. Sisipkan langsung dari profil.
                  final users = [...cached];
                  final myUid = auth.uid;
                  final me = auth.profile;
                  if (myUid != null &&
                      me != null &&
                      !users.any((u) => u.uid == myUid)) {
                    final now = DateTime.now();
                    users.insert(
                      0,
                      UserModel(
                        uid: myUid,
                        nickname: me.nickname,
                        gender: me.gender,
                        age: me.age,
                        country: me.country,
                        city: me.city,
                        ipAddress: '',
                        status: 'online',
                        avatar: me.avatar,
                        isRegistered: me.isRegistered,
                        loginAt: now,
                        createdAt: now,
                        lastSeen: now,
                      ),
                    );
                  }
                  if (users.isEmpty) {
                    // Belum pernah load → placeholder bulat (tinggi sama,
                    // tanpa teks kedip). Sudah load & kosong → teks info.
                    if (data == null) {
                      return ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: 4,
                        itemBuilder: (_, __) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: AppTheme.primary.withValues(
                                  alpha: 0.10,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 36,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: Text(
                        s.noOnlineUsers,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: users.length,
                    itemBuilder: (_, i) => RoomUserChip(
                      key: ValueKey(users[i].uid),
                      user: users[i],
                      myUid: auth.uid,
                      color: Color(
                        userColorPalette[colorHashForUid(users[i].uid) %
                            userColorPalette.length],
                      ),
                    ),
                  );
                },
              ),
            ),

          Expanded(
            child: Stack(
              children: [
                StreamBuilder<List<MessageModel>>(
                  stream: _msgsStream,
              builder: (_, snap) {
                final s = context.read<LocaleProvider>().s;
                // Persisten anti-glitch bawah: saat stream belum emit /
                // blip kosong, tampilkan batch terakhir (_lastMsgs diisi
                // listener tiap emisi) — list tidak kedip hilang.
                final raw = snap.data;
                final msgs = (raw == null || raw.isEmpty) &&
                        _lastMsgs.isNotEmpty
                    ? _lastMsgs
                    : (raw ?? []);
                // Bubble optimistik milik sendiri (centang-1) selalu tampil
                // di ujung list — walau offline, walau stream belum emit.
                final all = [...msgs, ..._pending];
                if (all.isEmpty) {
                  // Room baru/kosong — tampilkan layar kosong saja,
                  // tanpa ikon/teks "mulai percakapan".
                  return const SizedBox.shrink();
                }
                if (msgs.length > _lastMsgCount && _isNearBottom) {
                  _lastMsgCount = msgs.length;
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _scrollToBottom(),
                  );
                } else {
                  _lastMsgCount = msgs.length;
                }
                // Selipkan chip tanggal (Hari ini/Kemarin/tanggal) di antara grup hari,
                // pola WhatsApp — item list berisi pesan + separator tanggal.
                // PRIVASI: kumpulan id pesan terhapus — quote reply yang
                // menunjuk pesan ini dirender "Pesan dihapus", bukan isinya.
                final deletedIds = {
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
                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final item = items[items.length - 1 - i];
                    if (item.dateLabel != null)
                      return DateChip(label: item.dateLabel!);
                    final m = item.msg!;
                    final isMe = m.senderId == auth.uid;
                    final mkey = _msgKeys.putIfAbsent(m.id, () => GlobalKey());
                    final selected = selectedIds.contains(m.id);
                    final reacts = reactions[m.id];
                    final starred = starredIds.contains(m.id);
                    return Container(
                      // Tanpa wash biru selebar baris (sama private chat —
                      // hanya border bubble). Wash tersisa hanya untuk flash
                      // sesaat saat lompat ke pesan (_highlightId).
                      color: _highlightId == m.id
                          ? AppTheme.primary.withValues(alpha: 0.22)
                          : Colors.transparent,
                      child: CompositedTransformTarget(
                      link: linkFor(m.id),
                      // AppGestureDetector: tahan 320ms (bukan 500ms).
                      child: AppGestureDetector(
                        onLongPressStart: (d) => onMessageLongPress(d, m, linkFor(m.id)),
                        onTap: inSelection ? () => toggleSelect(m) : null,
                        child: SwipeToReply(
                          // Geser kanan = balas (grup & room). Pesan sendiri
                          // dikecualikan agar tidak bentrok swipe-back sistem.
                          enabled: !inSelection &&
                              m.senderId != auth.uid &&
                              !m.isDeleted,
                          onReply: () => replyMessage(m),
                          child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (m.isForwarded)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 4, right: 4, bottom: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.forward,
                                        size: 14,
                                        color: AppTheme.textSecondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        s.msgForwardedLabel,
                                        style: AppText.caption.copyWith(
                                          color: AppTheme.textSecondary,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    // Border seleksi digambar DI DALAM bubble
                                    // (sama seperti private chat) — dulu di
                                    // Container pembungkus sehingga border
                                    // memanjang sampai ujung layar.
                                    child: RoomMessageBubble(
                                      key: mkey,
                                      msg: m,
                                      isMe: isMe,
                                      isPending:
                                          m.id.startsWith('pending-'),
                                      isQueued:
                                          _queuedIds.contains(m.id),
                                      isSelected: selected,
                                      color: Color(
                                        userColorPalette[colorHashForUid(
                                                    m.senderId) %
                                            userColorPalette.length],
                                      ),
                                      roomId: widget.room.id,
                                      onTapUser: () => _onTapUser(m, auth),
                                      deletedIds: deletedIds,
                                      highlightMentionAll:
                                          isPrivateRoom && canModerate,
                                    ),
                                  ),
                                  if (starred)
                                    Positioned(
                                      top: -6,
                                      right: isMe ? 0 : null,
                                      left: isMe ? null : 0,
                                      child: const Icon(
                                        Icons.star,
                                        size: 14,
                                        color: Color(0xFFFFB300),
                                      ),
                                    ),
                                  if (reacts != null && reacts.isNotEmpty)
                                    Positioned(
                                      bottom: -10,
                                      left: isMe ? null : 8,
                                      right: isMe ? 8 : null,
                                      child: ReactionBadge(
                                        counts: reacts,
                                        isMe: isMe,
                                        onTap: inSelection
                                            ? null
                                            : () => openReactionDetail(m),
                                      ),
                                    ),
                                ],
                              ),
                              if (reacts != null && reacts.isNotEmpty)
                                const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                      ),
                    );
                  },
                );
              },
                ),
                // Banner approval mengambang — hanya setelah role dicek,
                // tidak menggeser list pesan saat muncul.
                if (isPrivateRoom && _roleChecked && _myRole == null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          Colors.orange.withValues(alpha: 0.12),
                          AppTheme.bgCard,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.hourglass_top_rounded, color: Colors.orange, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(s.privateRoomNeedApproval, style: AppText.bodySmall.copyWith(color: Colors.orange.shade800))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (_queuedIds.isNotEmpty)
            Container(
              color: AppTheme.bgCard,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Row(
                children: [
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
            Container(
              color: AppTheme.bgCard,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Row(
                children: [
                  Container(width: 3, height: 36, decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(replyingTo!.senderName, style: AppText.chatCaption.copyWith(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                        Text(replyingTo!.text.isNotEmpty ? replyingTo!.text : s.msgPhoto, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.chatBodySmall),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: cancelReply, color: AppTheme.textSecondary),
                ],
              ),
            ),
          if (editingMessage != null)
            Container(
              color: AppTheme.bgCard,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.edit,
                    size: 16,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.editingMessage,
                      style: AppText.chatBodySmall.copyWith(color: AppTheme.primary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: cancelEdit,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          // Bottom bar 3-state didefinisikan di atas (bottomBar) —
          // SafeArea bawah agar tidak kepotong nav bar Android.
          SafeArea(
            top: false,
            child: bottomBar,
          ),
        ],
      );
        // Overlay gift fly + kombo — di atas semua konten (IgnorePointer,
        // tidak mengganggu gesture chat/stage).
        final giftOverlay = GiftFlyOverlay(controller: _giftFly);
        if (!showPip) {
          return Stack(children: [column, Positioned.fill(child: giftOverlay)]);
        }
        return Stack(children: [
          column,
          Positioned.fill(child: giftOverlay),
          Builder(builder: (context) {
            final mq = MediaQuery.of(context);
            final minW = 100.0, maxW = mq.size.width * 0.8;
            final minH = 130.0, maxH = mq.size.height * 0.6;
            _pipSize = Size(
              _pipSize.width.clamp(minW, maxW),
              _pipSize.height.clamp(minH, maxH),
            );
            final w = _pipSize.width;
            final h = _pipSize.height;
            _pipPos ??= Offset(mq.size.width - w - 12, 24);
            final pos = Offset(
              _pipPos!.dx.clamp(8.0, mq.size.width - w - 8),
              _pipPos!.dy.clamp(8.0, mq.size.height - h - 8),
            );
            final handle = 28.0;
            return Positioned(
              left: pos.dx,
              top: pos.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => setState(() => _stageMinimized = false),
                onPanStart: (d) {
                  _pipResizing =
                      d.localPosition.dx > w - handle && d.localPosition.dy > h - handle;
                  _pipResizeStartSize = _pipSize;
                  _pipResizeStartLocal = d.localPosition;
                },
                onPanUpdate: (d) {
                  setState(() {
                    if (_pipResizing) {
                      _pipSize = Size(
                        (_pipResizeStartSize.width + d.localPosition.dx - _pipResizeStartLocal.dx)
                            .clamp(minW, maxW),
                        (_pipResizeStartSize.height + d.localPosition.dy - _pipResizeStartLocal.dy)
                            .clamp(minH, maxH),
                      );
                    } else {
                      _pipPos = Offset(
                        (_pipPos!.dx + d.delta.dx).clamp(8.0, mq.size.width - w - 8),
                        (_pipPos!.dy + d.delta.dy).clamp(8.0, mq.size.height - h - 8),
                      );
                    }
                  });
                },
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _BroadcastStage(
                          session: _broadcastSession!,
                          isBroadcaster: iAmBroadcasting,
                          compact: true,
                        ),
                        // Handle resize pojok kanan bawah
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Icon(Icons.zoom_out_map_rounded, size: 14, color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ]);
      }),
      ),
    );
  }

  void _onTapUser(MessageModel msg, AuthProvider auth) {
    if (msg.senderId == auth.uid) return;
    if (_sheetOpen) return;
    if (context.read<ChatProvider>().isBlocked(msg.senderId)) {
      final s = context.read<LocaleProvider>().s;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.msgBlocked)));
      return;
    }
    _sheetOpen = true;
    final s = context.read<LocaleProvider>().s;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  // Tutup sheet lalu buka halaman profil user.
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UserInfoScreen(
                        userId: msg.senderId,
                        fallbackName: msg.senderName,
                      ),
                    ),
                  );
                },
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Color(
                        userColorPalette[colorHashForUid(msg.senderId) %
                            userColorPalette.length],
                      ),
                      child: Text(
                        msg.senderName.isNotEmpty
                            ? msg.senderName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(msg.senderName, style: AppText.bodyStrong),
                          Text(
                            msg.senderGender == 'male'
                                ? s.genderMale
                                : msg.senderGender == 'female'
                                ? s.genderFemale
                                : s.genderOther,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: RoomSheetIcon(
                icon: Icons.chat_rounded,
                color: AppTheme.primary,
              ),
              title: Text(
                s.titlePrivateChat,
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              onTap: () async {
                final chat = context.read<ChatProvider>();
                final locale = context.read<LocaleProvider>();
                // User sudah dihapus (akun tidak ada) → jangan buka chat,
                // policy RLS menolak insert chat dengan participant yang hilang.
                final active = await chat.isUserActive(msg.senderId);
                if (!context.mounted) return;
                if (!active) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(locale.s.errUserNotFound)),
                  );
                  return;
                }
                // Pakai context screen (bukan context sheet) — context sheet
                // sudah deactivated setelah pop, sehingga Navigator.push
                // gagal diam-diam kalau startPrivateChat > animasi pop.
                final navigator = Navigator.of(context);
                final screenContext = context;
                navigator.pop();
                try {
                  final chatId = await chat.startPrivateChat(
                    myUid: auth.uid!,
                    otherUid: msg.senderId,
                    myName: auth.profile!.nickname,
                    otherName: msg.senderName,
                    myGender: auth.profile!.gender,
                    otherGender: msg.senderGender,
                    myAge: auth.profile!.age,
                  );
                  if (mounted && screenContext.mounted) {
                    Navigator.of(screenContext).push(
                      MaterialPageRoute(
                        builder: (_) => PrivateChatScreen(
                          chatId: chatId,
                          otherName: msg.senderName,
                          otherUid: msg.senderId,
                          otherGender: msg.senderGender,
                          otherCountry: '',
                          otherRegistered: msg.isRegistered,
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    final s = context.read<LocaleProvider>().s;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s.errGeneric)),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const RoomSheetIcon(
                icon: Icons.block_rounded,
                color: AppTheme.danger,
              ),
              title: Text(
                s.btnBlock,
                style: const TextStyle(color: AppTheme.danger),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await context.read<ChatProvider>().blockUser(
                  auth.uid!,
                  msg.senderId,
                );
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(s.blockSuccess)));
                }
              },
            ),
            ListTile(
              leading: const RoomSheetIcon(
                icon: Icons.flag_rounded,
                color: Colors.orange,
              ),
              title: Text(
                s.btnReport,
                style: const TextStyle(color: Colors.orange),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _showReportDialog(msg.senderId, msg.senderName);
              },
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      _sheetOpen = false;
    });
  }

  void _showReportDialog(String reportedId, String reportedName) {
    showReportUserDialog(
      context,
      reportedId: reportedId,
      reportedName: reportedName,
    );
  }

}


class _BroadcastStage extends StatelessWidget {
  const _BroadcastStage(
      {required this.session, required this.isBroadcaster, this.onMinimize, this.compact = false});

  final RoomBroadcastSession session;
  final bool isBroadcaster;
  final VoidCallback? onMinimize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final tiles = <Widget>[];
    if (isBroadcaster && session.localRendererReady) {
      tiles.add(RTCVideoView(session.localRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover, mirror: true));
    }
    for (final r in session.remoteRenderers.values) {
      if (r.srcObject != null) {
        tiles.add(RTCVideoView(r, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover));
      }
    }
    // fallback single remoteRenderer lama
    if (tiles.isEmpty && !isBroadcaster && session.remoteRenderer.srcObject != null) {
      tiles.add(RTCVideoView(session.remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover));
    }
    return Container(
      height: compact ? double.infinity : 220,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (tiles.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(strokeWidth: 2),
                  const SizedBox(height: 8),
                  Text(s.privateRoomsLiveConnecting,
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            )
          else if (tiles.length == 1)
            tiles.first
          else
            GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.6,
              children: tiles,
            ),
          Positioned(
            top: 8,
            left: 10,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('LIVE · ${session.viewerCount}',
                  style: AppText.micro.copyWith(color: Colors.white)),
            ),
          ),
          // Drag ke bawah di AREA MANA PUN video utk minimize (hanya stage
          // inline, bukan PiP). Double-tap juga minimize.
          if (onMinimize != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (d) {
                  if (d.primaryDelta != null && d.primaryDelta! > 8) {
                    onMinimize!();
                  }
                },
                onDoubleTap: onMinimize,
                child: const SizedBox.expand(),
              ),
            ),
          if (onMinimize != null)
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white54,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          if (isBroadcaster)
            Positioned(
              bottom: 8,
              right: 10,
              child: Row(children: [
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => session.toggleCamera(),
                  icon: Icon(Icons.videocam_rounded,
                      size: 18,
                      color: session.cameraOn ? null : AppTheme.danger),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => session.switchCamera(),
                  icon: const Icon(Icons.cameraswitch_rounded, size: 18),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await PrivateRoomService.instance
                        .stopBroadcast(session.roomId);
                    await session.stop();
                  },
                  icon: const Icon(Icons.stop_circle_rounded,
                      size: 20, color: AppTheme.danger),
                ),
              ]),
            ),
          if (!isBroadcaster)
            Positioned(
              bottom: 8,
              right: 10,
              child: Text(s.viewerCount(session.viewerCount),
                  style: AppText.micro.copyWith(color: Colors.white54)),
            ),
        ],
      ),
    );
  }
}
