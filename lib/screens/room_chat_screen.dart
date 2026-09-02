import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../models/room_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/chat_service.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../services/storage_photo_service.dart';
import '../services/room_service.dart';
import '../services/forensic_watermark.dart';
import '../utils.dart';
import '../main.dart';
import '../services/private_room_service.dart';
import '../services/room_broadcast_service.dart';
import 'room_members_sheet.dart';
import '../widgets/date_chip.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/private_chat_message.dart';
import '../widgets/voice_bubble.dart';
import '../widgets/mic_record_button.dart';
import '../widgets/composer_link_preview.dart';
import '../widgets/linkify_text.dart';
import '../widgets/link_preview.dart';
import '../services/link_preview_service.dart';
import 'private_chat_screen.dart';
import 'user_info_screen.dart';
import '../providers/theme_provider.dart';
import '../services/call_notification.dart';

// Isolate helpers untuk proses foto (sama seperti private chat).
String? _roomProcessImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final w = decoded.width, h = decoded.height;
  final img.Image resized = (w <= 800 && h <= 800)
      ? decoded
      : img.copyResize(
          decoded,
          width: w > h ? 800 : null,
          height: h >= w ? 800 : null,
        );
  return base64Encode(img.encodeJpg(resized, quality: 75));
}

String? _roomPassthroughImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final w = decoded.width, h = decoded.height;
  final img.Image resized = (w <= 1200 && h <= 1200)
      ? decoded
      : img.copyResize(
          decoded,
          width: w > h ? 1200 : null,
          height: h >= w ? 1200 : null,
        );
  return base64Encode(img.encodeJpg(resized, quality: 82));
}

String? _roomViewOnceImage((Uint8List, String) args) {
  final (bytes, seed) = args;
  return ForensicWatermark.embedToBase64(bytes, seed);
}

class RoomChatScreen extends StatefulWidget {
  final RoomModel room;
  const RoomChatScreen({super.key, required this.room});

  @override
  State<RoomChatScreen> createState() => _RoomChatScreenState();
}

class _RoomChatScreenState extends State<RoomChatScreen>
    with WidgetsBindingObserver {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _imagePicker = ImagePicker();
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

  // ── Private room v2 ──
  String? _myRole;
  String? _liveUid;
  int _pendingCount = 0;
  RoomBroadcastSession? _broadcastSession;
  Timer? _livePoll;
  bool _isGrantedBroadcast = false;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = context.read<AuthProvider>();
    _chat = context.read<ChatProvider>();
    activeChatId.value = widget.room.id;
    final msgsHandle = _chat.getRoomMessages(widget.room.id);
    _msgsStream = msgsHandle.stream;
    _usersStream = _chat.getOnlineUsersInRoom(widget.room.id);
    _pointsProv = context.read<PointsProvider>();
    if (isPrivateRoom) {
      unawaited(_initPrivate());
    }
    _joinRoom();
    _startPresenceHeartbeat();
    _scrollCtrl.addListener(_onRoomScroll);
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
    debugPrint('[BDBG] initPrivate start room=${widget.room.id} uid=${_auth.uid}');
    try {
      _myRole = await PrivateRoomService.instance.myRole(widget.room.id);
      debugPrint('[BDBG] myRole=$_myRole isPrivate=${widget.room.isPrivate}');
      if (canModerate) {
        try {
          final req = await PrivateRoomService.instance
              .listJoinRequests(widget.room.id);
          _pendingCount = req.length;
        } catch (_) {}
      }
      await _refreshLiveUid();
      try {
        final granted = await PrivateRoomService.instance.myBroadcastGranted(widget.room.id);
        _isGrantedBroadcast = granted || _liveUid == _auth.uid;
        debugPrint('[BDBG] init granted=$_isGrantedBroadcast live=$_liveUid');
      } catch (e) {
        debugPrint('[BDBG] init myBroadcastGranted error: $e');
      }
      _listenRoomLive();
      _livePoll?.cancel();
      _livePoll = Timer.periodic(const Duration(seconds: 5), (_) {
        _refreshLiveUid();
        _refreshGrant();
        _ensureViewerSession();
      });
    } catch (e) {
      debugPrint('[BDBG] initPrivate ERROR: $e');
    }
    _roleChecked = true;
    if (!mounted) return;
    setState(() {});
  }

  RealtimeChannel? _roomLiveChannel;

  void _listenRoomLive() {
    try {
      _roomLiveChannel?.unsubscribe();
    } catch (_) {}
    try {
      final ch = Supabase.instance.client.channel('room-live-${widget.room.id}');
      ch.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'rooms',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.room.id),
        callback: (payload) {
          final live = payload.newRecord['live_uid']?.toString();
          debugPrint('[BDBG] realtime rooms update live=$live current=$_liveUid');
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
      debugPrint('[BDBG] refreshGrant granted=$granted live=$_liveUid uid=${_auth.uid} g=$g');
      if (mounted && g != _isGrantedBroadcast) setState(() => _isGrantedBroadcast = g);
    } catch (e) {
      debugPrint('[BDBG] refreshGrant error: $e');
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
    debugPrint('[BDBG] refreshLiveUid fetched=$live current=$_liveUid');
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

  Future<void> _openMembersSheet() async {
    await showModalBottomSheet(
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
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _livePoll?.cancel();
    try { _roomLiveChannel?.unsubscribe(); } catch (_) {}
    unawaited(_broadcastSession?.stop());
    if (activeChatId.value == widget.room.id) {
      activeChatId.value = null;
    }
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

  Future<void> _sendVoiceMessage(String filePath, int durationMs) async {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    try {
      final f = File(filePath);
      if (!await f.exists()) return;
      final bytes = await f.readAsBytes();
      final storagePath = await StoragePhotoService.instance.uploadVoice(
        chatId: 'room_${widget.room.id}',
        bytes: bytes,
      );
      if (storagePath == null || storagePath.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.read<LocaleProvider>().s.errSendFailed}upload')),
          );
        }
        return;
      }
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
      debugPrint('[RoomVoice] send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.read<LocaleProvider>().s.errSendFailed}$e')),
        );
      }
    }
  }

  MessageModel? _replyingTo;
  MessageModel? _editingMessage;

  void _editMessage(MessageModel msg) {
    setState(() {
      _editingMessage = msg;
      _replyingTo = null;
      _msgCtrl.text = msg.text;
      _msgCtrl.selection =
          TextSelection.collapsed(offset: _msgCtrl.text.length);
    });
  }

  void _cancelEdit() => setState(() => _editingMessage = null);

  void _replyMessage(MessageModel msg) {
    setState(() {
      _replyingTo = msg;
      _editingMessage = null;
    });
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  // LayerLink per pesan — anchor action bar (Balas / Hapus) tepat di atas bubble.
  final Map<String, LayerLink> _msgLinks = {};
  OverlayEntry? _actionBar;

  LayerLink _linkFor(String id) => _msgLinks.putIfAbsent(id, () => LayerLink());

  void _hideActionBar() {
    _actionBar?.remove();
    _actionBar = null;
  }

  Future<void> _deleteMessage(MessageModel msg) async {
    final s = context.read<LocaleProvider>().s;
    final ok = await context.read<ChatProvider>().deleteRoomMessage(msg.id);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgDeletedRoom)));
    }
  }

  void _onMessageLongPress(
    LongPressStartDetails details,
    MessageModel msg,
    LayerLink link,
  ) {
    if (msg.isDeleted) return;
    _hideActionBar();
    final s = context.read<LocaleProvider>().s;
    final isMe = msg.senderId == context.read<AuthProvider>().uid;

    Widget iconBtn(IconData icon, String tooltip, VoidCallback onTap, {bool danger = false}) {
      return IconButton(
        icon: Icon(icon, size: 20, color: danger ? AppTheme.danger : AppTheme.textPrimary),
        tooltip: tooltip,
        splashRadius: 20,
        onPressed: () {
          _hideActionBar();
          onTap();
        },
      );
    }

    _actionBar = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _hideActionBar,
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            offset: const Offset(0, -8),
            child: Material(
              color: AppTheme.bgCard,
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              shadowColor: Colors.black.withValues(alpha: 0.25),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconBtn(Icons.reply, s.menuReply, () => _replyMessage(msg)),
                    // Edit hanya pesan teks milik sendiri (foto/voice/pending
                    // tidak bisa diedit — sama seperti private chat).
                    if (isMe && msg.type == 'text' && !msg.id.startsWith('pending-'))
                      iconBtn(Icons.edit, s.editMessageTitle, () => _editMessage(msg)),
                    if (isMe)
                      iconBtn(Icons.delete_outline, s.btnDelete, () => _deleteMessage(msg), danger: true),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_actionBar!);
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    final hasPhoto = _pendingPhotoBase64 != null;
    if (text.isEmpty && !hasPhoto) return;
    if (_isSending) return;

    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;

    // Mode edit pesan sendiri (text): simpan perubahan, tanpa koin/kirim baru.
    final editing = _editingMessage;
    if (editing != null && !hasPhoto) {
      if (text.isEmpty || text == editing.text) {
        _cancelEdit();
        return;
      }
      _msgCtrl.clear();
      setState(() => _editingMessage = null);
      _isSending = true;
      try {
        final ok = await ChatService().editRoomMessage(editing.id, text);
        if (mounted) {
          final s = context.read<LocaleProvider>().s;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ok ? s.msgEdited : s.errSendFailed),
            ),
          );
        }
      } finally {
        _isSending = false;
      }
      return;
    }

    final replying = _replyingTo;
    if (hasPhoto) {
      final photoB64 = _pendingPhotoBase64!;
      _msgCtrl.clear();
      setState(() {
        _pendingPhotoBase64 = null;
        _replyingTo = null;
      });
      _isSending = true;

      final pp = context.read<PointsProvider>();
      final rPhoto = await pp.deductBeforeSend('image');
      if (rPhoto < 0) {
        _isSending = false;
        if (!mounted) return;
        if (rPhoto == -1) {
          pp.showOutOfPointsDialog(context, context.read<LocaleProvider>().s.isId);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.read<LocaleProvider>().s.errSendPhoto)),
          );
        }
        return;
      }
      try {
        final path = await StoragePhotoService.instance.upload(
          chatId: 'room_${widget.room.id}',
          base64: photoB64,
        );
        if (path == null || path.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<LocaleProvider>().s.errSendPhoto)));
          }
          _isSending = false;
          return;
        }
        await chat.sendRoomMessage(
          roomId: widget.room.id,
          senderId: uid,
          senderName: profile.nickname,
          senderGender: profile.gender,
          text: text,
          type: 'image',
          imageData: path,
          repliedToId: replying?.id,
          repliedToText: replying?.text,
          repliedToSenderName: replying?.senderName,
        );
        _scrollToBottom();
      } catch (e) {
        safeUnawaited(pp.refundChatPoint('image'));
        if (mounted) {
          final s = context.read<LocaleProvider>().s;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.errSendPhoto)),
          );
        }
      } finally {
        _isSending = false;
      }
      return;
    }

    final reply = _replyingTo;
    _msgCtrl.clear();
    setState(() => _replyingTo = null);
    _isSending = true;

    final pp = context.read<PointsProvider>();
    final remaining = await pp.deductBeforeSend('text');
    if (remaining < 0) {
      _isSending = false;
      if (!mounted) return;
      final ss = context.read<LocaleProvider>().s;
      if (remaining == -1) {
        pp.showOutOfPointsDialog(context, ss.isId);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ss.errSendFailed)));
      }
      return;
    }
    try {
      await chat.sendRoomMessage(
        roomId: widget.room.id,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: text,
        repliedToId: reply?.id,
        repliedToText: reply?.text,
        repliedToSenderName: reply?.senderName,
      );
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
    } catch (e) {
      // Kirim gagal → kembalikan koin yang sudah terpotong.
      safeUnawaited(pp.refundChatPoint('text'));
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errSendFailed)));
      }
    } finally {
      _isSending = false;
    }
  }

  bool _showAttachRow = false;

  void _toggleAttachRow() {
    if (!_showAttachRow) FocusScope.of(context).unfocus();
    setState(() => _showAttachRow = !_showAttachRow);
  }

  Future<void> _takePhoto() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.msgFileTooLarge)),
        );
      }
      return;
    }
    final processed = await compute(_roomProcessImage, bytes);
    if (processed == null) return;
    if (mounted) {
      setState(() => _pendingPhotoBase64 = processed);
    }
  }

  Future<void> _sendPhoto() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgFileTooLarge)));
      }
      return;
    }
    final base64 = await compute(_roomProcessImage, bytes);
    if (base64 == null) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoRead)));
      }
      return;
    }
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    final pp = context.read<PointsProvider>();
    final r = await pp.deductBeforeSend('image');
    if (r < 0) {
      if (!mounted) return;
      if (r == -1) {
        pp.showOutOfPointsDialog(
          context,
          context.read<LocaleProvider>().s.isId,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.read<LocaleProvider>().s.errSendPhoto),
          ),
        );
      }
      return;
    }
    try {
      final path = await StoragePhotoService.instance.upload(
        chatId: 'room_${widget.room.id}',
        base64: base64,
      );
      if (path == null || path.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<LocaleProvider>().s.errSendPhoto)));
        }
        _isSending = false;
        return;
      }
      await chat.sendRoomMessage(
        roomId: widget.room.id,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: '',
        type: 'image',
        imageData: path,
      );
      _scrollToBottom();
    } catch (e) {
      safeUnawaited(pp.refundChatPoint('image'));
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
      }
    }
  }

  Future<void> _sendViewOncePhoto() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final auth = context.read<AuthProvider>();
    // Proses gambar DULU, baru potong poin (jangan paralel) — mencegah
    // koin terpotong saat decode/resize gagal.
    final base64 = await (auth.watermarkEnabled
        ? compute(_roomViewOnceImage, (bytes, widget.room.id))
        : compute(_roomPassthroughImage, bytes));
    if (base64 == null) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errPhotoRead)));
      }
      return;
    }
    if (!mounted) return;
    final pp = context.read<PointsProvider>();
    final rView = await pp.deductBeforeSend('view_once');
    if (rView < 0) {
      if (rView == -1) {
        pp.showOutOfPointsDialog(
          context,
          context.read<LocaleProvider>().s.isId,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.read<LocaleProvider>().s.errSendPhoto),
          ),
        );
      }
      return;
    }
    final chat = context.read<ChatProvider>();
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    try {
      final path = await StoragePhotoService.instance.upload(
        chatId: 'room_${widget.room.id}',
        base64: base64,
      );
      if (path == null || path.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<LocaleProvider>().s.errSendPhoto)));
        }
        _isSending = false;
        return;
      }
      await chat.sendRoomMessage(
        roomId: widget.room.id,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: '',
        type: 'view_once',
        imageData: path,
      );
      _scrollToBottom();
    } catch (e) {
      safeUnawaited(pp.refundChatPoint('view_once'));
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final auth = context.read<AuthProvider>();
    final s = context.watch<LocaleProvider>().s;

    return Scaffold(
      backgroundColor: AppTheme.bgCard,
      appBar: AppBar(
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
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _HeaderToggle(
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
        final column = Column(
        children: [
          // Banner hanya setelah role selesai dicek — mencegah blink
          // "menunggu persetujuan" di awal load untuk member biasa.
          if (isPrivateRoom && _roleChecked && _myRole == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: Colors.orange.withValues(alpha: 0.12),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.privateRoomNeedApproval, style: AppText.bodySmall.copyWith(color: Colors.orange.shade800))),
                ],
              ),
            ),
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
                  final users = snap.data ?? [];
                  if (users.isEmpty) {
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
                    itemBuilder: (_, i) => _UserChip(
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
            child: StreamBuilder<List<MessageModel>>(
              stream: _msgsStream,
              builder: (_, snap) {
                final s = context.read<LocaleProvider>().s;
                final msgs = snap.data ?? [];
                if (msgs.isEmpty) {
                  return Center(
                    child: Builder(
                      builder: (ctx) {
                        final s = ctx.read<LocaleProvider>().s;
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('👋', style: TextStyle(fontSize: AppGlyph.xl)),
                            SizedBox(height: 8),
                            Text(
                              s.msgStartConversation,
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ],
                        );
                      },
                    ),
                  );
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
                final items = <ChatItem>[];
                String? prevDateKey;
                for (final m in msgs) {
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
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final item = items[items.length - 1 - i];
                    if (item.dateLabel != null)
                      return DateChip(label: item.dateLabel!);
                    final m = item.msg!;
                    final isMe = m.senderId == auth.uid;
                    return CompositedTransformTarget(
                      link: _linkFor(m.id),
                      child: GestureDetector(
                        onLongPressStart: (d) => _onMessageLongPress(d, m, _linkFor(m.id)),
                        child: _MessageBubble(
                          key: ValueKey(m.id),
                          msg: m,
                          isMe: isMe,
                          color: Color(
                            userColorPalette[colorHashForUid(m.senderId) %
                                userColorPalette.length],
                          ),
                          roomId: widget.room.id,
                          onTapUser: () => _onTapUser(m, auth),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          if (_replyingTo != null)
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
                        Text(_replyingTo!.senderName, style: AppText.caption.copyWith(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                        Text(_replyingTo!.text.isNotEmpty ? _replyingTo!.text : '[Foto]', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _cancelReply, color: AppTheme.textSecondary),
                ],
              ),
            ),
          if (_editingMessage != null)
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
                      style: AppText.bodySmall.copyWith(color: AppTheme.primary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _cancelEdit,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          // Pending approval: composer diganti bar info — jangan biarkan user
          // mencoba kirim lalu gagal diam-diam.
          if (isPrivateRoom && _roleChecked && _myRole == null)
            Container(
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
            )
          else
          _ChatInput(
            controller: _msgCtrl,
            onSend: _send,
            showAttachRow: _showAttachRow,
            onToggleAttach: _toggleAttachRow,
            onTakePhoto: () {
              setState(() => _showAttachRow = false);
              _takePhoto();
            },
            onSendPhoto: () {
              setState(() => _showAttachRow = false);
              _sendPhoto();
            },
            onSendViewOnce: () {
              setState(() => _showAttachRow = false);
              _sendViewOncePhoto();
            },
            onSendVoice: _sendVoiceMessage,
            pendingPhotoBase64: _pendingPhotoBase64,
            onCancelPhoto: _pendingPhotoBase64 != null
                ? () => setState(() => _pendingPhotoBase64 = null)
                : null,
          ),
        ],
      );
        if (!showPip) return column;
        return Stack(children: [
          column,
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
              leading: _SheetIcon(
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
                      SnackBar(content: Text('${s.errGeneric}$e')),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const _SheetIcon(
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
              leading: const _SheetIcon(
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
    String reason = '';
    final s = context.read<LocaleProvider>().s;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          '${s.btnReport} $reportedName',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: TextField(
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(hintText: s.reportHint),
          onChanged: (v) => reason = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.read<LocaleProvider>().s.btnCancel),
          ),
          TextButton(
            onPressed: () {
              context.read<ChatProvider>().reportUser(
                reporterId: context.read<AuthProvider>().uid!,
                reportedId: reportedId,
                reason: reason,
              );
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(s.reportSuccess)));
            },
            child: Text(
              s.btnReport,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  final UserModel user;
  final String? myUid;
  final Color color;
  const _UserChip({required this.user, this.myUid, required this.color});

  @override
  Widget build(BuildContext context) {
    final isMe = user.uid == myUid;
    final s = context.read<LocaleProvider>().s;
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isMe ? AppTheme.primary : color,
                child: Text(
                  user.initial,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: AppGlyph.avatarInitial(44),
                  ),
                ),
              ),
              if (user.isRegistered)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Icon(
                    Icons.verified,
                    size: 14,
                    color: Color(0xFF4A90E2),
                  ),
                ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            isMe ? s.labelYou : user.nickname,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  final Color color;
  final String roomId;
  final VoidCallback onTapUser;
  const _MessageBubble({
    super.key,
    required this.msg,
    required this.isMe,
    required this.color,
    required this.roomId,
    required this.onTapUser,
  });

  // Warna teks bubble mengikuti tema (gelap di light mode, terang di dark mode)
  // supaya sinkron dengan warna bubble (bgInput / primary alpha).
  static Color get _textColor => AppTheme.textPrimary;

  bool get _isMedia =>
      msg.type == 'image' ||
      msg.type == 'view_once' ||
      msg.type == 'view_once_expired';

  // Konten bubble: foto / view-once / teks — dipakai untuk pesan sendiri & orang lain.
  Widget _replyQuote(BuildContext context) {
    if (msg.repliedToText == null || msg.repliedToText!.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isMe ? Colors.white.withValues(alpha: 0.15) : AppTheme.bgScreen.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(msg.repliedToSenderName ?? '', style: AppText.label.copyWith(color: AppTheme.primary)),
          Text(msg.repliedToText!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.bodySmall),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    String timeStr, {
    required bool alignRight,
  }) {
    final chatKey = 'room_$roomId';
    if (msg.type == 'voice' && msg.imageData.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _replyQuote(context),
          VoiceBubble(
            path: msg.imageData,
            durationMs: msg.durationMs ?? 0,
            isMe: isMe,
            timeStr: timeStr,
          ),
        ],
      );
    }
    if (msg.type == 'image' && msg.imageData.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _replyQuote(context),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                MessageImage(
                  imageData: msg.imageData,
                  chatKey: chatKey,
                  messageId: msg.id,
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      timeStr,
                      style: AppText.micro.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (msg.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinkifyText(
                msg.text,
                style: AppText.body.copyWith(color: _textColor),
              ),
            ),
        ],
      );
    }
    if (msg.type == 'view_once' || msg.type == 'view_once_expired') {
      return Stack(
        children: [
          ViewOnceImage(
            imageData: msg.imageData,
            chatKey: chatKey,
            isMe: isMe,
            messageId: msg.id,
            isExpired: msg.type == 'view_once_expired',
            isRoom: true,
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                timeStr,
                style: AppText.micro.copyWith(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _replyQuote(context),
        if (LinkPreviewService.instance.extractUrl(msg.text) != null) LinkPreview(text: msg.text),
        MessageTextWithTime(
          text: msg.text,
          timeStr: timeStr,
          textStyle: AppText.body.copyWith(color: _textColor),
          timeStyle: AppText.micro.copyWith(
            color: _textColor.withValues(alpha: 0.45),
            fontWeight: FontWeight.w400,
          ),
          alignRight: alignRight,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    if (msg.isDeleted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Text(s.messageDeleted, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary, fontStyle: FontStyle.italic)),
          ],
        ),
      );
    }
    final timeStr = DateFormat.Hm().format(msg.timestamp.toLocal());

    // Pesan sendiri: biru muda (sama private), rata kanan, tanpa avatar
    if (isMe) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.8,
                ),
                padding: _isMedia
                    ? const EdgeInsets.all(4)
                    : const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.25),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: _content(context, timeStr, alignRight: true),
              ),
            ),
          ],
        ),
      );
    }

    // Pesan user lain: avatar + nama warna + bubble abu-abu (sama private), rata kiri
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTapUser,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: color,
              child: Text(
                msg.senderName.isNotEmpty
                    ? msg.senderName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppGlyph.avatarInitial(32),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onTapUser,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        msg.senderName,
                        style: AppText.label.copyWith(
                          color: color,
                          letterSpacing: 0,
                        ),
                      ),
                      if (msg.isRegistered) ...[
                        SizedBox(width: 3),
                        Icon(
                          Icons.verified,
                          size: 14,
                          color: Color(0xFF4A90E2),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 2),
                Container(
                  // Kurangi offset avatar (32) + gap (8) supaya tepi kanan bubble
                  // sama dengan bubble private chat (80% lebar layar).
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.8 - 40,
                  ),
                  padding: _isMedia
                      ? EdgeInsets.all(4)
                      : const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.bgInput,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      topRight: Radius.circular(14),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.repliedToId != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 5),
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: const Border(
                              left: BorderSide(
                                color: AppTheme.primary,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                msg.repliedToSenderName ?? '',
                                style: AppText.caption.copyWith(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                msg.repliedToText ?? '',
                                style: AppText.caption.copyWith(
                                  color: _textColor.withValues(alpha: 0.6),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      _content(context, timeStr, alignRight: false),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool showAttachRow;
  final VoidCallback onToggleAttach;
  final VoidCallback onTakePhoto;
  final VoidCallback onSendPhoto;
  final VoidCallback onSendViewOnce;
  final String? pendingPhotoBase64;
  final VoidCallback? onCancelPhoto;
  final void Function(String filePath, int durationMs)? onSendVoice;
  const _ChatInput({
    required this.controller,
    required this.onSend,
    required this.showAttachRow,
    required this.onToggleAttach,
    required this.onTakePhoto,
    required this.onSendPhoto,
    required this.onSendViewOnce,
    this.pendingPhotoBase64,
    this.onCancelPhoto,
    this.onSendVoice,
  });

  @override
  State<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<_ChatInput> {
  Uint8List? _decodedPhoto;
  final _record = AudioRecorder();
  bool _isRecordingVoice = false;
  Timer? _voiceTimer;
  int _voiceSeconds = 0;
  bool _isVoiceLocked = false;
  bool _isVoicePaused = false;
  // Bulatan lock sedang di-pick-up (ditekan + digeser) — menyembunyikan
  // tombol pause di composer dan menampilkan kembali "geser untuk batal".
  bool _voicePickUp = false;

  void _lockVoiceRecord() {
    if (mounted) setState(() => _isVoiceLocked = true);
  }

  void _startVoiceTimer() {
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_voiceSeconds >= 59) { _stopVoiceRecord(); return; }
      setState(() => _voiceSeconds++);
    });
  }

  Future<void> _pauseVoiceRecord() async {
    try { await _record.pause(); } catch (_) {}
    _voiceTimer?.cancel();
    if (mounted) setState(() => _isVoicePaused = true);
  }

  Future<void> _resumeVoiceRecord() async {
    try { await _record.resume(); } catch (_) {}
    if (mounted) setState(() => _isVoicePaused = false);
    _startVoiceTimer();
  }

  Future<void> _startVoiceRecord() async {
    final hasPerm = await Permission.microphone.request();
    if (!hasPerm.isGranted) return;
    try {
      if (!await _record.hasPermission()) return;
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _record.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 16000), path: path);
      setState(() {
        _isRecordingVoice = true;
        _voiceSeconds = 0;
        _isVoiceLocked = false;
        _isVoicePaused = false;
        _voicePickUp = false;
      });
      _startVoiceTimer();
    } catch (_) {}
  }

  Future<void> _stopVoiceRecord() async {
    _voiceTimer?.cancel();
    if (!_isRecordingVoice) return;
    _isVoiceLocked = false;
    _isVoicePaused = false;
    _voicePickUp = false;
    final path = await _record.stop();
    setState(() => _isRecordingVoice = false);
    if (path == null) return;
    final f = File(path);
    if (!await f.exists()) return;
    final bytes = await f.readAsBytes();
    if (bytes.length < 2000) return;
    final ms = _voiceSeconds * 1000;
    widget.onSendVoice?.call(path, ms);
  }

  void _cancelVoiceRecord() {
    _voiceTimer?.cancel();
    _record.cancel();
    setState(() {
      _isRecordingVoice = false;
      _isVoiceLocked = false;
      _isVoicePaused = false;
      _voicePickUp = false;
    });
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _decodePhoto();
  }

  @override
  void didUpdateWidget(covariant _ChatInput old) {
    super.didUpdateWidget(old);
    if (old.pendingPhotoBase64 != widget.pendingPhotoBase64) _decodePhoto();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _voiceTimer?.cancel();
    _record.dispose();
    super.dispose();
  }

  void _decodePhoto() {
    final b64 = widget.pendingPhotoBase64;
    if (b64 == null) {
      _decodedPhoto = null;
    } else {
      try {
        _decodedPhoto = base64Decode(b64);
      } catch (_) {
        _decodedPhoto = null;
      }
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: AppTheme.bgScreen,
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
          children: [
            if (_decodedPhoto != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Image.memory(
                        _decodedPhoto!,
                        width: double.infinity,
                        height: 150,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: widget.onCancelPhoto,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ComposerLinkPreview(controller: widget.controller),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    onPressed: () =>
                      EmojiPickerSheet.show(context, widget.controller),
                    icon: Icon(Icons.emoji_emotions_rounded, size: 22),
                    color: AppTheme.textSecondary,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                SizedBox(width: 2),
                Expanded(
                  child: Container(
                    constraints: BoxConstraints(maxHeight: 132),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.bgCard, width: 1),
                    ),
                    // Isi card di-swap: ketik pesan ↔ rekam voice.
                    // Ukuran & posisi card 100% identik karena
                    // container-nya yang sama. Tinggi 48 = tinggi
                    // konten ketik (icon +/📷 48px).
                    child: _isRecordingVoice
                        ? SizedBox(
                            height: 48,
                            child: Row(
                              children: [
                                const SizedBox(width: 16),
                                Icon(Icons.mic_rounded, color: Colors.red, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  _voiceSeconds < 60
                                      ? '${_voiceSeconds.toString().padLeft(2, '0')}s'
                                      : '${(_voiceSeconds ~/ 60).toString().padLeft(2, '0')}:${(_voiceSeconds % 60).toString().padLeft(2, '0')}',
                                  style: AppText.bodyStrong.copyWith(color: Colors.red),
                                ),
                                const Spacer(),
                                if (!_isVoiceLocked || _voicePickUp) ...[
                                  Icon(
                                    Icons.keyboard_arrow_left_rounded,
                                    color: AppTheme.textSecondary,
                                    size: 20,
                                  ),
                                  Text(
                                    s.hintSlideToCancel,
                                    style: AppText.caption.copyWith(color: AppTheme.textSecondary),
                                  ),
                                ] else ...[
                                  GestureDetector(
                                    onTap: () => _isVoicePaused
                                        ? _resumeVoiceRecord()
                                        : _pauseVoiceRecord(),
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _isVoicePaused
                                            ? Icons.play_arrow_rounded
                                            : Icons.pause_rounded,
                                        color: Colors.red,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 16),
                              ],
                            ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              SizedBox(width: 16),
                              Expanded(
                                child: TextField(
                                  controller: widget.controller,
                                  style: AppText.body,
                                  decoration: InputDecoration(
                                    hintText: s.hintTypeMessage,
                                    hintStyle: AppText.body.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                  textInputAction: TextInputAction.newline,
                                  onSubmitted: (_) => widget.onSend(),
                                  minLines: 1,
                                  maxLines: null,
                                  keyboardType: TextInputType.multiline,
                                  textCapitalization: TextCapitalization.sentences,
                                ),
                              ),
                              _RoomInputIconBtn(
                                open: widget.showAttachRow,
                                onTap: widget.onToggleAttach,
                                tooltip: s.menuSendPhoto,
                              ),
                              const SizedBox(width: 2),
                              _RoomInputIconBtn(
                                open: false,
                                onTap: widget.onTakePhoto,
                                tooltip: s.menuTakePhoto,
                                icon: Icons.photo_camera_outlined,
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  // HANYA currentChild — previousChildren dibuang supaya
                  // tidak ada DUA bulatan bertumpuk saat cross-fade
                  // (sumber blink biru/gembok saat rekaman dibatalkan).
                  layoutBuilder: (currentChild, previousChildren) =>
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: <Widget>[
                          if (currentChild != null) currentChild,
                        ],
                      ),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: child,
                  ),
                  // SATU instance MicRecordButton sepanjang gesture: swap
                  // cabang saat recording meng-unmount tombol yang di-hold
                  // → gesture putus → rekaman menggantung (hang).
                  child: _isRecordingVoice
                      ? MicRecordButton(
                          isRecording: true,
                          isLocked: _isVoiceLocked,
                          onTap: _stopVoiceRecord,
                          onLongPressStart: _startVoiceRecord,
                          onLongPressCancel: _cancelVoiceRecord,
                          onLock: _lockVoiceRecord,
                          onPickUpChanged: (v) =>
                              setState(() => _voicePickUp = v),
                          size: 40,
                        )
                      : (widget.controller.text.trim().isEmpty && _decodedPhoto == null
                      ? MicRecordButton(
                          isRecording: false,
                          isLocked: _isVoiceLocked,
                          onTap: _stopVoiceRecord,
                          onLongPressStart: _startVoiceRecord,
                          onLongPressCancel: _cancelVoiceRecord,
                          onLock: _lockVoiceRecord,
                          onPickUpChanged: (v) =>
                              setState(() => _voicePickUp = v),
                          size: 40,
                        )
                          : GestureDetector(
                              key: const ValueKey('send'),
                              onTap: widget.onSend,
                              child: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary.withValues(alpha: 0.4),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.send_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            )),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: widget.showAttachRow
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: Row(
                        children: [
                          _RoomAttachChip(
                            icon: Icons.image_rounded,
                            color: AppTheme.primary,
                            label: s.menuSendPhoto,
                            onTap: widget.onSendPhoto,
                          ),
                          const SizedBox(width: 12),
                          _RoomAttachChip(
                            icon: Icons.timer_rounded,
                            color: Colors.orange,
                            label: s.menuViewOnce,
                            onTap: widget.onSendViewOnce,
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomInputIconBtn extends StatelessWidget {
  final bool open;
  final VoidCallback onTap;
  final String tooltip;
  final IconData? icon;
  const _RoomInputIconBtn({
    required this.open,
    required this.onTap,
    required this.tooltip,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primary.withValues(alpha: open ? 0.16 : 0.12),
          ),
          child: AnimatedRotation(
            turns: open ? 0.125 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(scale: anim, child: child),
              ),
              child: Icon(
                icon ?? (open ? Icons.close_rounded : Icons.add_rounded),
                key: ValueKey(icon ?? open),
                color: AppTheme.primary,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Toggle header room: pill squircle dengan icon beranimasi
/// anggota ⇄ chat — lebih jelas afordansinya daripada icon polos.
class _HeaderToggle extends StatelessWidget {
  final bool showUsers;
  final VoidCallback onTap;
  const _HeaderToggle({required this.showUsers, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    return Tooltip(
      message: showUsers ? s.roomShowChat : s.roomShowMembers,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: showUsers
                ? AppTheme.primary
                : AppTheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(scale: anim, child: child),
            ),
            child: Icon(
              showUsers ? Icons.forum_rounded : Icons.groups_rounded,
              key: ValueKey(showUsers),
              size: 20,
              color: showUsers ? Colors.white : AppTheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon dalam lingkaran tinted untuk item bottom sheet — konsisten
/// gaya modern, warna membedakan aksi.
class _SheetIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _SheetIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _RoomAttachChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _RoomAttachChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(child: Icon(icon, color: color, size: 24)),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}


/// Stage broadcast setengah layar: video broadcaster + kontrol ringkas.
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
              child: Text('${session.viewerCount} peers',
                  style: AppText.micro.copyWith(color: Colors.white54)),
            ),
        ],
      ),
    );
  }
}
