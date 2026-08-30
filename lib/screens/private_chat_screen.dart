import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import '../config/theme.dart';
import '../config/gifts.dart';
import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../providers/social_provider.dart';
import '../services/chat_service.dart';
import '../services/chat_background.dart';
import '../services/call_service.dart';
import '../services/forensic_watermark.dart';
import '../services/storage_photo_service.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/private_chat_message.dart';
import '../widgets/date_chip.dart';
import '../widgets/voice_bubble.dart';
import '../widgets/voice_record_overlay.dart';
import '../widgets/mic_record_button.dart';
import '../widgets/composer_link_preview.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/chat_call_overlay.dart';
import '../main.dart';
import 'call_screen.dart';
import 'user_info_screen.dart';
import '../providers/theme_provider.dart';

// Top-level function untuk compute() isolate — decode + resize + encode di background
String? _processImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = _resizeMaxSide(decoded, 800);
  final jpg = img.encodeJpg(resized, quality: 75);
  return base64Encode(jpg);
}

// Resize proporsional dengan sisi terpanjang = maxSide.
img.Image _resizeMaxSide(img.Image src, int maxSide) {
  final w = src.width;
  final h = src.height;
  if (w <= maxSide && h <= maxSide) return src;
  final scale = maxSide / (w > h ? w : h);
  final nw = (w * scale).round();
  final nh = (h * scale).round();
  return img.copyResize(src, width: nw, height: nh);
}

// Top-level function untuk compute() isolate — resize 1024 + embed forensic watermark
String? _processViewOnceImage((Uint8List, String) args) {
  final (bytes, seed) = args;
  return ForensicWatermark.embedToBase64(bytes, seed);
}

// Top-level function untuk compute() isolate — tanpa watermark: resize 1200px + JPEG
// Kamera kirim foto besar (10-20MB) → decode gagal di penerima kalau tidak di-resize.
String? _passthroughImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = _resizeMaxSide(decoded, 1200);
  final jpg = img.encodeJpg(resized, quality: 82);
  return base64Encode(jpg);
}

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

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _imagePicker = ImagePicker();
  final _inputFocus = FocusNode();
  bool _showAttachRow = false;

  late Stream<List<MessageModel>> _msgsStream;
  late Stream<List<PrivateChatInfo>> _chatInfoStream;
  Future<void> Function() _loadOlder = () async {};
  Future<void> Function(String messageId) _msgsHandleFetchImage = (_) async {};
  Future<void> Function() _msgsHandleReload = () async {};
  bool _loadingOlder = false;

  DateTime? _otherLastRead;
  DateTime? _lastIncomingSeen;
  StreamSubscription<List<PrivateChatInfo>>? _chatInfoSub;
  StreamSubscription<List<MessageModel>>? _msgsSub;
  StreamSubscription<String>? _statusSub;
  String _otherStatus = 'offline';
  String _otherCountry = '';
  String _otherCity = '';
  List<String> _otherHashtags = const [];
  bool _otherRegistered = false;
  bool _wasBlocked = false;

  static const List<Color> _hashColors = [
    Color(0xFFFFD740),
    Color(0xFFFF80AB),
    Color(0xFF69F0AE),
    Color(0xFFFFAB40),
    Color(0xFFB388FF),
    Color(0xFF80D8FF),
  ];

  Color _hashColor(int i) => _hashColors[i % _hashColors.length];
  final List<MessageModel> _pending = [];
  // LayerLink per pesan — dipakai anchor action bar (icon Balas/Edit/Hapus)
  // tepat di atas bubble. CompositedTransformFollower ikut mengikuti bubble
  // saat list di-scroll, jadi action bar tidak "menempel" di layar.
  final Map<String, LayerLink> _msgLinks = {};
  OverlayEntry? _actionBar;

  // Call video dalam chat: overlay panel draggable di atas layar chat.
  bool _callExpanded = false;

  LayerLink _linkFor(String id) => _msgLinks.putIfAbsent(id, () => LayerLink());
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
    activeChatId.value = widget.chatId;
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
      for (final text in confirmedTexts) {
        final idx = _pending.indexWhere(
          (p) => p.type == 'text' && p.text == text,
        );
        if (idx != -1) {
          setState(() {
            _pending.removeAt(idx);
          });
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
            setState(() => _pending.removeAt(idx));
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
            setState(() {
              _pending.removeAt(idx);
            });
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
            setState(() => _pending.removeAt(idx));
          }
        }
      }
    });

    // Subscribe status realtime lawan bicara
    // Kalau diblokir, tampilkan offline langsung tanpa fetch DB
    _wasBlocked = context.read<ChatProvider>().isBlocked(widget.otherUid);
    if (!_wasBlocked) {
      _subscribeStatus();
      _subscribeTyping();
    }

    _chatInfoSub = _chatInfoStream.listen((chats) {
      final info = chats.cast<PrivateChatInfo?>().firstWhere(
        (c) => c?.chatId == widget.chatId,
        orElse: () => null,
      );
      final read = info?.lastReadAt[widget.otherUid];
      if (read != _otherLastRead) {
        setState(() => _otherLastRead = read);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (auth.uid != null) chat.markAsRead(widget.chatId, auth.uid!);
    });

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
        _otherHashtags = p.hashtags;
        // Fix: profil lawan di-fetch live — bukan cuma dari param,
        // supaya chat yang dibuka lewat notifikasi ikut tahu status
        // terdaftar lawan (tombol call & icon verified).
        _otherRegistered = p.isRegistered;
      });
    });
  }

  void _hideActionBar() {
    _actionBar?.remove();
    _actionBar = null;
  }

  @override
  void dispose() {
    _hideActionBar();
    _pendingConfirmTimer?.cancel();
    CallProvider.instance.removeListener(_onCallChanged);
    // Keluar chat TIDAK memutus panggilan — call lanjut berjalan dan notifikasi
    // ongoing "sedang call" tetap tampil. Tap notifikasi → kembali ke chat ini.
    _chatInfoSub?.cancel();
    _msgsSub?.cancel();
    _statusSub?.cancel();
    _typingSub?.cancel();
    _typingClearTimer?.cancel();
    if (activeChatId.value == widget.chatId) {
      activeChatId.value = null;
    }
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  CallPhase? _prevCallPhase;
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

  void _subscribeStatus() {
    _statusSub?.cancel();
    _statusSub = context
        .read<ChatProvider>()
        .getUserStatus(widget.otherUid)
        .listen((status) {
          if (!mounted) return;
          setState(() => _otherStatus = status);
          // Fetch last_seen saat status idle agar bisa tampilkan "terakhir dilihat"
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
  MessageModel? _editingMessage;
  MessageModel? _replyingTo;
  StreamSubscription<void>? _typingSub;
  Timer? _typingClearTimer;
  DateTime _lastTypingSent = DateTime(2000);
  bool _showTyping = false;
  String? _pendingPhotoBase64;

  void _subscribeTyping() {
    _typingSub?.cancel();
    _typingSub = context
        .read<ChatProvider>()
        .getTypingStream(widget.chatId)
        .listen((_) {
          if (!mounted) return;
          setState(() {
            _showTyping = true;
          });
          _typingClearTimer?.cancel();
          _typingClearTimer = Timer(const Duration(seconds: 3), () {
            if (!mounted) return;
            setState(() => _showTyping = false);
          });
        });
  }

  void _sendTypingSignal() {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inMilliseconds < 2500) return;
    _lastTypingSent = now;
    context.read<ChatProvider>().sendTyping(widget.chatId);
  }

  bool _newChatBonusClaimed = false;

  /// Misi "chat orang baru": bonus hanya diberikan saat user BENAR-BENAR
  /// mengirim pesan pertama ke lawan bicara (bukan pas membuka chat kosong).
  /// RPC new_chat_bonus tetap punya guard sendiri (sekali per user + limit
  /// harian), jadi aman dipanggil dari semua jalur kirim.
  void _maybeNewChatBonus() {
    if (_newChatBonusClaimed) return;
    _newChatBonusClaimed = true;
    context.read<PointsProvider>().newChatBonus(widget.otherUid);
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    final hasPhoto = _pendingPhotoBase64 != null;
    if (text.isEmpty && !hasPhoto) return;
    if (_isSending) return;

    // Mode edit: kirim langsung mengubah pesan lama (bukan pesan baru).
    if (_editingMessage != null) {
      final id = _editingMessage!.id;
      final original = _editingMessage!.text;
      _msgCtrl.clear();
      setState(() => _editingMessage = null);
      if (text != original) {
        await ChatService().editPrivateMessage(id, text);
      }
      return;
    }

    // Jika ada foto preview → kirim foto (+ opsional teks caption)
    if (hasPhoto) {
      final photoB64 = _pendingPhotoBase64!;
      _msgCtrl.clear();
      setState(() => _pendingPhotoBase64 = null);
      _isSending = true;

      final auth = context.read<AuthProvider>();
      final chat = context.read<ChatProvider>();
      final uid = auth.uid;
      final profile = auth.profile;
      if (uid == null || profile == null) {
        _isSending = false;
        return;
      }
      final ppPhoto = context.read<PointsProvider>();
      final rPhoto = await ppPhoto.deductBeforeSend('image');
      if (rPhoto < 0) {
        _isSending = false;
        if (!mounted) return;
        if (rPhoto == -1) {
          ppPhoto.showOutOfPointsDialog(context, context.read<LocaleProvider>().s.isId);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.read<LocaleProvider>().s.errSendPhoto)),
          );
        }
        return;
      }

      final pendingPhoto = MessageModel(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        isRegistered: profile.isRegistered,
        text: text,
        type: 'image',
        imageData: photoB64,
        timestamp: DateTime.now(),
      );
      setState(() => _pending.add(pendingPhoto));
      _scrollToBottom();
      try {
        final path = await StoragePhotoService.instance.upload(
          chatId: widget.chatId,
          base64: photoB64,
        );
        if (path == null || path.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.read<LocaleProvider>().s.errSendPhoto)),
            );
            setState(() => _pending.removeWhere((m) => m.id == pendingPhoto.id));
          }
          return;
        }
        await chat.sendPrivateMessage(
          chatId: widget.chatId,
          senderId: uid,
          senderName: profile.nickname,
          senderGender: profile.gender,
          text: text,
          type: 'image',
          imageData: path,
        );
        _maybeNewChatBonus();
        _schedulePendingConfirmFallback();
        if (ppPhoto.enabled) {
          ppPhoto.oneTimeBonus('first_photo', 10).then((earned) {
            if (earned && mounted) {
              ppPhoto.showPointsToast(
                context,
                context.read<LocaleProvider>().s.pointsGain(
                  10,
                  context.read<LocaleProvider>().s.reasonFirstPhoto,
                ),
              );
            }
          });
        }
        _scrollToBottom();
      } catch (e) {
        safeUnawaited(ppPhoto.refundChatPoint('image'));
        if (mounted) {
          setState(() => _pending.remove(pendingPhoto));
          final s = context.read<LocaleProvider>().s;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
        }
      } finally {
        await Future.delayed(const Duration(milliseconds: 300));
        _isSending = false;
      }
      return;
    }

    _msgCtrl.clear();
    _isSending = true;

    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    if (chat.isBlocked(widget.otherUid)) {
      _isSending = false;
      final s = context.read<LocaleProvider>().s;
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgBlocked)));
      return;
    }
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) {
      _isSending = false;
      return;
    }

    // Optimistic SEBELUM deduct: bubble langsung muncul instan tanpa
    // menunggu round-trip RPC potong poin (yang bisa 1-2 detik di
    // jaringan lambat). Gagal deduct → bubble dihapus lagi.
    final pending = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
      isRegistered: profile.isRegistered,
      text: text,
      type: 'text',
      imageData: '',
      timestamp: DateTime.now(),
    );
    setState(() => _pending.add(pending));
    _scrollToBottom();

    // Deduct poin sebelum kirim
    final pp = context.read<PointsProvider>();
    final remaining = await pp.deductBeforeSend('text');
    if (remaining < 0) {
      setState(() => _pending.remove(pending));
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
      await chat.sendPrivateMessage(
        chatId: widget.chatId,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: text,
        repliedToId: _replyingTo?.id,
        repliedToText: _replyingTo?.text,
        repliedToSenderName: _replyingTo?.senderName,
      );
      if (_replyingTo != null) setState(() => _replyingTo = null);
      _maybeNewChatBonus();
      _schedulePendingConfirmFallback();
    } catch (e) {
      // Kirim gagal → kembalikan koin yang sudah terpotong.
      debugPrint('[send] gagal chat=${widget.chatId}: $e');
      safeUnawaited(pp.refundChatPoint('text'));
      if (mounted) {
        setState(() => _pending.remove(pending));
        final s = context.read<LocaleProvider>().s;
        final isBlockedByOther =
            e.toString().contains('42501') ||
            e.toString().toLowerCase().contains('insufficient_privilege') ||
            e.toString().toLowerCase().contains('policy');
        // Jangan expose detail error teknis ke user
        final msg = isBlockedByOther ? s.msgBlockedByOther : s.errSendFailed;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      _isSending = false;
    }
    _scrollToBottom();
  }

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

  // ── Voice message 60s (WA style) ──
  final _record = AudioRecorder();
  bool _isRecordingVoice = false;
  Timer? _voiceTimer;
  int _voiceSeconds = 0;
  OverlayEntry? _voiceOverlay;

  Future<void> _startVoiceRecord() async {
    final hasPerm = await Permission.microphone.request();
    if (!hasPerm.isGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<LocaleProvider>().s.errVoicePermission)));
      return;
    }
    try {
      if (await _record.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
        await _record.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 16000), path: path);
        setState(() { _isRecordingVoice = true; _voiceSeconds = 0; });
        _voiceTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (_voiceSeconds >= 59) { _stopVoiceRecord(send: true); return; }
          setState(() => _voiceSeconds++);
        });
        _showVoiceOverlay();
      }
    } catch (_) {}
  }

  void _showVoiceOverlay() {
    _voiceOverlay?.remove();
    _voiceOverlay = OverlayEntry(builder: (_) => Positioned(bottom: 90, left: 16, right: 16, child: Material(color: Colors.transparent, child: VoiceRecordOverlay(onCancel: _cancelVoiceRecord, onSend: () => _stopVoiceRecord(send: true)))));
    Overlay.of(context).insert(_voiceOverlay!);
  }

  Future<void> _stopVoiceRecord({required bool send}) async {
    _voiceTimer?.cancel();
    _voiceOverlay?.remove(); _voiceOverlay = null;
    if (!_isRecordingVoice) return;
    final path = await _record.stop();
    setState(() => _isRecordingVoice = false);
    if (!send || path == null) return;
    final f = File(path);
    if (!await f.exists()) return;
    final bytes = await f.readAsBytes();
    final recordedMs = _voiceSeconds * 1000;
    if (bytes.length < 2000) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.read<LocaleProvider>().s.errVoiceTooShort)));
      return;
    }
    final chatId = widget.chatId;
    final storagePath = await StoragePhotoService.instance.uploadVoice(chatId: chatId, bytes: bytes);
    if (storagePath == null || storagePath.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${context.read<LocaleProvider>().s.errSendFailed}upload')));
      return;
    }
    final auth = context.read<AuthProvider>();
    final uid = auth.uid; final profile = auth.profile;
    if (uid == null || profile == null) return;
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
      debugPrint('[Voice] send error: $e');
      if (mounted) {
        setState(() => _pending.remove(optimistic));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${context.read<LocaleProvider>().s.errSendFailed}$e')));
      }
    }
  }

  void _cancelVoiceRecord() {
    _voiceTimer?.cancel();
    _voiceOverlay?.remove(); _voiceOverlay = null;
    _record.cancel();
    setState(() => _isRecordingVoice = false);
  }

  /// Mulai edit pesan teks sendiri — teks dimasukkan ke composer bawah,
  /// lalu kirim (tombol send) akan langsung mengubah pesan ini, bukan
  /// membuat pesan baru.
  void _editMessage(MessageModel msg) {
    setState(() {
      _editingMessage = msg;
      _msgCtrl.text = msg.text;
      _msgCtrl.selection = TextSelection.collapsed(offset: msg.text.length);
    });
    _inputFocus.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _msgCtrl.clear();
    });
  }

  /// Hold pesan → action bar icon (Balas / Edit / Hapus) tepat di atas
  /// bubble. Diposisikan pakai CompositedTransformFollower + LayerLink milik
  /// bubble, jadi saat list di-scroll bar tetap nempel di atas bubble yang
  /// sama (Overlay, bukan bagian dari scroll).
  void _onMessageLongPress(
    LongPressStartDetails details,
    MessageModel msg,
    LayerLink link,
  ) {
    if (msg.isDeleted) return;
    _hideActionBar();
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final isMe = msg.senderId == (auth.uid ?? '');
    final isPending = msg.id.startsWith('pending-');
    final canEdit = isMe && msg.type == 'text' && !isPending;

    Widget iconBtn(
      IconData icon,
      String tooltip,
      VoidCallback onTap, {
      bool danger = false,
    }) {
      return IconButton(
        icon: Icon(
          icon,
          size: 20,
          color: danger ? AppTheme.danger : AppTheme.textPrimary,
        ),
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
                    if (canEdit)
                      iconBtn(
                        Icons.edit,
                        s.editMessageTitle,
                        () => _editMessage(msg),
                      ),
                    if (isMe)
                      iconBtn(
                        Icons.delete_outline,
                        s.btnDelete,
                        () => _deleteMessage(msg),
                        danger: true,
                      ),
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

  void _replyMessage(MessageModel msg) {
    setState(() => _replyingTo = msg);
    _inputFocus.requestFocus();
    _scrollToBottom();
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  Future<void> _deleteMessage(MessageModel msg) async {
    await ChatService().deletePrivateMessage(msg.id);
  }

  Future<void> _sendPhoto() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await _sendImageBytes(bytes);
  }

  /// Buka kamera → tampilkan preview di composer (bukan langsung kirim).
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
    final processed = await compute(_processImage, bytes);
    if (processed == null) return;
    if (mounted) {
      setState(() {
        _pendingPhotoBase64 = processed;
        _inputFocus.requestFocus();
      });
      _scrollToBottom();
    }
  }

  /// Proses + kirim foto (dipakai gallery & kamera) — resize di isolate,
  /// upload storage, insert pesan image.
  Future<void> _sendImageBytes(Uint8List bytes) async {
    // Tolak file > 10MB sebelum proses
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgFileTooLarge)));
      }
      return;
    }
    // Decode + resize + encode di background isolate agar UI tidak freeze
    final base64 = await compute(_processImage, bytes);
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
    final ppPhoto = context.read<PointsProvider>();
    final rPhoto = await ppPhoto.deductBeforeSend('image');
    if (rPhoto < 0) {
      if (!mounted) return;
      if (rPhoto == -1) {
        ppPhoto.showOutOfPointsDialog(
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
    // Optimistic: tampilkan foto langsung tanpa nunggu upload server.
    final pendingPhoto = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
      isRegistered: profile.isRegistered,
      text: '',
      type: 'image',
      imageData: base64,
      timestamp: DateTime.now(),
    );
    setState(() => _pending.add(pendingPhoto));
    _scrollToBottom();
    try {
      // Upload foto ke Storage — DB hanya simpan path (hemat ruang).
      final path = await StoragePhotoService.instance.upload(
        chatId: widget.chatId,
        base64: base64,
      );
      if (path == null || path.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.read<LocaleProvider>().s.errSendPhoto)),
          );
          setState(() => _pending.removeWhere((m) => m.id == pendingPhoto.id));
        }
        return;
      }
      await chat.sendPrivateMessage(
        chatId: widget.chatId,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: '',
        type: 'image',
        imageData: path,
      );
      _maybeNewChatBonus();
      _schedulePendingConfirmFallback();
      if (ppPhoto.enabled) {
        ppPhoto.oneTimeBonus('first_photo', 10).then((earned) {
          if (earned && mounted) {
            ppPhoto.showPointsToast(
              context,
              context.read<LocaleProvider>().s.pointsGain(
                10,
                context.read<LocaleProvider>().s.reasonFirstPhoto,
              ),
            );
          }
        });
      }
      _scrollToBottom();
    } catch (e) {
      // Upload/kirim gagal → kembalikan koin yang sudah terpotong.
      safeUnawaited(ppPhoto.refundChatPoint('image'));
      if (mounted) {
        setState(() => _pending.remove(pendingPhoto));
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
    // Proses gambar DULU, baru potong poin — jangan paralel, supaya poin
    // tidak terpotong saat decode/resize gagal (koin hilang percuma).
    final base64 = await (auth.watermarkEnabled
        ? compute(_processViewOnceImage, (bytes, widget.otherUid))
        : compute(_passthroughImage, bytes));
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
    // Optimistic: tampilkan foto view-once langsung tanpa nunggu server —
    // supaya pengirim tidak lihat spinner muter terus.
    final pending = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
      isRegistered: profile.isRegistered,
      text: '',
      type: 'view_once',
      imageData: base64,
      timestamp: DateTime.now(),
    );
    setState(() => _pending.add(pending));
    _scrollToBottom();
    try {
      // Upload ke Storage — DB hanya simpan path (hemat ruang).
      final path = await StoragePhotoService.instance.upload(
        chatId: widget.chatId,
        base64: base64,
      );
      if (path == null || path.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.read<LocaleProvider>().s.errSendPhoto)),
          );
          setState(() => _pending.removeWhere((m) => m.id == pending.id));
        }
        return;
      }
      await chat.sendPrivateMessage(
        chatId: widget.chatId,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: '',
        type: 'view_once',
        imageData: path,
      );
      _maybeNewChatBonus();
      _schedulePendingConfirmFallback();
      _scrollToBottom();
    } catch (e) {
      // Upload/kirim gagal → kembalikan koin yang sudah terpotong.
      safeUnawaited(pp.refundChatPoint('view_once'));
      if (mounted) {
        setState(() => _pending.remove(pending));
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
      }
    }
  }

  void _toggleAttachRow() {
    if (!_showAttachRow) {
      FocusScope.of(context).unfocus(); // tutup keyboard saat buka menu
    }
    setState(() => _showAttachRow = !_showAttachRow);
  }

  void _showSendCoinDialog() {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final points = context.read<PointsProvider>();

    // Hanya akun terdaftar & email terverifikasi yang boleh kirim koin.
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

    final amountCtrl = TextEditingController();
    int selected = 0;
    const presets = [5, 10, 25, 50, 100];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Dialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header gradient elegan
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primaryDark,
                      AppTheme.primary,
                      AppTheme.accent,
                    ],
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          '🪙',
                          style: TextStyle(fontSize: AppGlyph.lg),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      s.sendCoinTitle,
                      style: AppText.title.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.sendCoinTo(widget.otherName),
                      style: AppText.caption.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Saldo kamu
                    if (points.enabled)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFFB300,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(
                              0xFFFFB300,
                            ).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '🪙',
                              style: TextStyle(fontSize: AppGlyph.sm),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                s.labelYourCoins,
                                style: AppText.bodySmall.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                            Text(
                              '${points.paidBalance}',
                              style: AppText.bodyStrong.copyWith(
                                color: const Color(0xFFFFB300),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                    const SizedBox(height: 14),
                    Text(
                      s.coinAmountLabel,
                      style: AppText.label.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    // Preset jumlah
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presets.map((p) {
                        final isSel = selected == p;
                        return GestureDetector(
                          onTap: () => setInner(() {
                            selected = p;
                            amountCtrl.text = '$p';
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? AppTheme.primary
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isSel
                                    ? AppTheme.primary
                                    : Colors.white.withValues(alpha: 0.12),
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              '$p 🪙',
                              style: AppText.bodyStrong.copyWith(
                                color: isSel ? Colors.white : Colors.white70,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    // Input custom
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setInner(() => selected = 0),
                      style: AppText.body.copyWith(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: s.coinAmountHint,
                        hintStyle: AppText.body.copyWith(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.coinDialogHelper,
                      style: AppText.caption.copyWith(color: Colors.white38),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          s.btnCancel,
                          style: AppText.bodyStrong.copyWith(
                            color: Colors.white60,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () async {
                          final amount =
                              int.tryParse(amountCtrl.text.trim()) ?? 0;
                          if (amount < 5) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(s.errCoinMin)),
                            );
                            return;
                          }
                          if (points.enabled && amount > points.paidBalance) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(s.errCoinInsufficient)),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          await _sendCoins(amount);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(s.btnSend, style: AppText.button),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

    final gift = await showModalBottomSheet<GiftItem>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.giftTitle, style: AppText.title),
              SizedBox(height: 4),
              Text(
                s.giftPick,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              SizedBox(height: 16),
              if (!points.enabled) ...[
                SizedBox.shrink(),
                SizedBox(height: 12),
              ] else ...[
                Text(
                  '${s.paidBalanceLabel}: ${points.paidBalance}',
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                height: 200,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: kGiftCatalog.length,
                  itemBuilder: (ctx, i) {
                    final g = kGiftCatalog[i];
                    final afford =
                        g.coins <= points.paidBalance ||
                        (g.coins * points.bonusMultiplier) <=
                            points.bonusBalance;
                    return InkWell(
                      onTap: afford ? () => Navigator.pop(ctx, g) : null,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: afford
                              ? AppTheme.bgInput
                              : AppTheme.bgInput.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: afford
                                ? Colors.pinkAccent.withValues(alpha: 0.4)
                                : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              g.emoji,
                              style: TextStyle(fontSize: AppGlyph.lg),
                            ),
                            SizedBox(height: 4),
                            Text(
                              s.isId ? g.nameId : g.nameEn,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.micro.copyWith(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '${g.coins} 🪙',
                              style: AppText.caption.copyWith(
                                color: afford
                                    ? Color(0xFFB8860B)
                                    : AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
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
    debugPrint('[CHAT-BUILD] callAllEnabled=${auth.callAllEnabled} '
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
    final genderEmoji = widget.otherGender == 'male'
        ? '👨'
        : widget.otherGender == 'female'
        ? '👩'
        : '';
    final genderLabel = widget.otherGender == 'male'
        ? s.genderMalePlain
        : widget.otherGender == 'female'
        ? s.genderFemalePlain
        : '';
    final agePart = widget.otherAge > 0 ? '${widget.otherAge}' : '';
    final cityPart = _otherCity.isNotEmpty ? _otherCity : widget.otherCity;
    final countryPart = _otherCountry.isNotEmpty
        ? _otherCountry
        : widget.otherCountry;
    final subtitle = [
      if (genderLabel.isNotEmpty) '$genderLabel $agePart'.trim(),
      if (cityPart.isNotEmpty && cityPart != countryPart) cityPart,
      if (countryPart.isNotEmpty) countryPart,
    ].where((e) => e.isNotEmpty).join(', ');
    final points = context.watch<PointsProvider>().points;

    // Show online bonus toast jika ada yang nunggu
    Future.microtask(() {
      final pp = context.read<PointsProvider>();
      pp.checkAndShowOnlineToast(context, s.isId);
      pp.checkAndShowStreakToast(context, s.isId);
    });

    Future.microtask(() {
      final pp = context.read<PointsProvider>();
      pp.checkAndShowOnlineToast(context, s.isId);
      pp.checkAndShowStreakToast(context, s.isId);
    });

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
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
                borderRadius: 20,
                bgColor: Colors.white.withValues(alpha: 0.25),
                textColor: Colors.white,
                badge: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: displayStatus == 'online'
                        ? Color(0xFF69F0AE)
                        : displayStatus == 'idle'
                        ? Color(0xFFFFD740)
                        : Colors.white38,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primary, width: 2),
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
                            if (widget.otherRegistered) ...[
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
                            if (_otherHashtags.isNotEmpty)
                              Text.rich(
                                TextSpan(
                                  children: [
                                    for (final e
                                        in _otherHashtags.asMap().entries) ...[
                                      if (e.key > 0) TextSpan(text: '  '),
                                      TextSpan(
                                        text: '#${e.value}',
                                        style: AppText.caption.copyWith(
                                          color: _hashColor(e.key),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
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
            icon: Icon(Icons.more_vert, color: Colors.white),
            color: AppTheme.bgCard,
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
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'follow',
                child: Text(
                  s.menuFollow,
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
              ),
              PopupMenuItem(
                value: 'friend',
                child: Text(
                  s.menuAddFriend,
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: Text(
                  s.btnBlock,
                  style: const TextStyle(color: AppTheme.danger),
                ),
              ),
              PopupMenuItem(
                value: 'report',
                child: Text(
                  s.btnReport,
                  style: const TextStyle(color: Colors.orange),
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
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      StreamBuilder<List<MessageModel>>(
                        stream: _msgsStream,
                        builder: (_, snap) {
                          final msgs = snap.data ?? [];
                          final all = [...msgs, ..._pending];
                          if (all.isEmpty) {
                            // Stream belum emit (data == null) → jangan tampilkan empty state —
                            // mencegah flash "Mulai percakapan!" saat buka chat yang ada isinya.
                            // Hanya tampilkan empty state setelah stream selesai (data != null).
                            if (snap.data == null)
                              return const SizedBox.shrink();
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '👋',
                                    style: TextStyle(fontSize: AppGlyph.xl),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    s.startConversation,
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
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
                            padding: const EdgeInsets.all(12),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final item = items[items.length - 1 - i];
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
                                  msg.timestamp.isBefore(_otherLastRead!);
                              // Image kosong & pesan lama (> 50 dari terbaru) → deferred (icon refresh)
                              final isImageDeferred =
                                  msg.type == 'image' &&
                                  msg.imageData.isEmpty &&
                                  i >= 50;
                              return MessageBubble(
                                key: ValueKey(msg.id),
                                link: _linkFor(msg.id),
                                msg: msg,
                                chatKey: cacheKeyFor(widget.chatId),
                                isMe: isMe,
                                isRead: isRead,
                                isPending: isPending,
                                isImageDeferred: isImageDeferred,
                                onRetryImage: _msgsHandleFetchImage,
                                onLongPressMenu: _onMessageLongPress,
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
                if (_showTyping)
                  Padding(
                    padding: EdgeInsets.fromLTRB(14, 6, 0, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _TypingBubble(),
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
                        if (_replyingTo != null)
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
                                        style: AppText.caption.copyWith(
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                      Text(
                                        _replyingTo!.text,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.bodySmall.copyWith(
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
                                  onPressed: _cancelReply,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        if (_editingMessage != null)
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
                                    style: AppText.bodySmall.copyWith(
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
                                  onPressed: _cancelEdit,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        if (_pendingPhotoBase64 != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                children: [
                                  Image.memory(
                                    base64.decode(_pendingPhotoBase64!),
                                    width: double.infinity,
                                    height: 150,
                                    fit: BoxFit.cover,
                                  ),
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: GestureDetector(
                                      onTap: () =>
                                          setState(() => _pendingPhotoBase64 = null),
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
                        ComposerLinkPreview(controller: _msgCtrl),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.isDark ? Colors.transparent : AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: () =>
                                    EmojiPickerSheet.show(context, _msgCtrl),
                                icon: Icon(
                                  Icons.emoji_emotions_outlined,
                                  size: 20,
                                ),
                                color: AppTheme.isDark ? AppTheme.primary : Colors.white,
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
                                  border: Border.all(
                                    color: AppTheme.bgCard,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(width: 16),
                                    Expanded(
                                      child: TextField(
                                        controller: _msgCtrl,
                                        focusNode: _inputFocus,
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
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                vertical: 10,
                                              ),
                                        ),
                                        textInputAction:
                                            TextInputAction.newline,
                                        onSubmitted: (_) => _send(),
                                        onChanged: (_) => _sendTypingSignal(),
                                        minLines: 1,
                                        maxLines: 4,
                                        keyboardType: TextInputType.multiline,
                                        textCapitalization:
                                            TextCapitalization.sentences,
                                      ),
                                    ),
                                    _InputIconBtn(
                                      icon: _showAttachRow
                                          ? Icons.close
                                          : Icons.add_circle_outline,
                                      color: AppTheme.primary,
                                      onTap: _toggleAttachRow,
                                      tooltip: s.menuSendPhoto,
                                    ),
                                    const SizedBox(width: 4),
                                    _InputIconBtn(
                                      icon: Icons.photo_camera_outlined,
                                      color: AppTheme.primary,
                                      onTap: () {
                                        setState(() => _showAttachRow = false);
                                        _takePhoto();
                                      },
                                      tooltip: s.menuTakePhoto,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _msgCtrl,
                              builder: (context, value, _) {
                                final hasText = value.text.trim().isNotEmpty || _pendingPhotoBase64 != null;
                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  switchInCurve: Curves.easeOut,
                                  switchOutCurve: Curves.easeIn,
                                  transitionBuilder: (child, anim) => SizeTransition(
                                    sizeFactor: anim,
                                    axis: Axis.horizontal,
                                    axisAlignment: -1,
                                    child: FadeTransition(opacity: anim, child: child),
                                  ),
                                  child: hasText
                                      ? SizedBox(
                                          key: const ValueKey('send'),
                                          width: 40,
                                          height: 40,
                                          child: IconButton(
                                            onPressed: _send,
                                            icon: const Icon(Icons.send_rounded, size: 20),
                                            color: Colors.white,
                                            padding: EdgeInsets.zero,
                                            style: IconButton.styleFrom(backgroundColor: AppTheme.primary, shape: const CircleBorder()),
                                          ),
                                        )
                                      : MicRecordButton(
                                          isRecording: _isRecordingVoice,
                                          onTap: () => _stopVoiceRecord(send: true),
                                          onLongPressStart: _startVoiceRecord,
                                          onLongPressCancel: _cancelVoiceRecord,
                                          size: 40,
                                        ),
                                );
                              },
                            ),
                          ],
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          child: _showAttachRow
                              ? Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                    left: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      _AttachChip(
                                        icon: Icons.image_outlined,
                                        color: AppTheme.primary,
                                        label: s.menuSendPhoto,
                                        onTap: () {
                                          setState(
                                            () => _showAttachRow = false,
                                          );
                                          _sendPhoto();
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      _AttachChip(
                                        icon: Icons.timer_outlined,
                                        color: Colors.orange,
                                        label: s.menuViewOnce,
                                        onTap: () {
                                          setState(
                                            () => _showAttachRow = false,
                                          );
                                          _sendViewOncePhoto();
                                        },
                                      ),
                                      // Kirim koin — sembunyikan saat sistem poin OFF
                                      if (context
                                          .watch<PointsProvider>()
                                          .enabled) ...[
                                        const SizedBox(width: 8),
                                        _AttachChip(
                                          icon: Icons.paid_outlined,
                                          color: Colors.amber,
                                          label: s.menuSendCoin,
                                          onTap: () {
                                            setState(
                                              () => _showAttachRow = false,
                                            );
                                            _showSendCoinDialog();
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        _AttachChip(
                                          icon: Icons.card_giftcard,
                                          color: Colors.pinkAccent,
                                          label: s.menuSendGift,
                                          onTap: () {
                                            setState(
                                              () => _showAttachRow = false,
                                            );
                                            _showGiftPicker();
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
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
                onEnd: () async {
                  final sess = CallProvider.instance.activeSession;
                  if (sess != null) await sess.end();
                  unawaited(CallProvider.instance.clearSession());
                },
              ),
            ),
        ],
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
    String reason = '';
    final s = context.read<LocaleProvider>().s;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          '${s.btnReport} ${widget.otherName}',
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
                reportedId: widget.otherUid,
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

// Tombol ikon kecil untuk input bar
class _InputIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;
  const _InputIconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 30,
          height: 48,
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

// Chip menu attach (foto / foto sekali lihat / kirim koin) ala WhatsApp
class _AttachChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _AttachChip({
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
      child: SizedBox(
        // Lebar chip FIXED agar pusat ikon selalu di posisi yang sama —
        // label yang panjang (mis. "Foto Sekali Lihat") tidak menggeser
        // posisi ikon, jadi jeda antar ikon rata. Harus muat 4 chip
        // sekaligus di layar terkecil (Redmi 393dp): 4×82 + 3×10 = 358dp.
        width: 84,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(child: Icon(icon, color: Colors.white, size: 24)),
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t =
              TweenSequence<double>([
                TweenSequenceItem(
                  tween: Tween(
                    begin: 0.3,
                    end: 1.0,
                  ).chain(CurveTween(curve: Curves.easeInOut)),
                  weight: 50,
                ),
                TweenSequenceItem(
                  tween: Tween(
                    begin: 1.0,
                    end: 0.3,
                  ).chain(CurveTween(curve: Curves.easeInOut)),
                  weight: 50,
                ),
              ]).animate(
                CurvedAnimation(
                  parent: _ctrl,
                  curve: Interval(i * 0.15, 1, curve: Curves.linear),
                ),
              );
          return FadeTransition(
            opacity: t,
            child: Container(
              width: 7,
              height: 7,
              margin: EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(
                color: AppTheme.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── View Once / Photo Viewer — pindah ke ../widgets/private_chat_message.dart ──
