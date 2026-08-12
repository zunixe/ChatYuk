import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../services/chat_service.dart';
import '../services/forensic_watermark.dart';
import '../services/photo_cache.dart';
import '../services/screen_secure_service.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../main.dart';
import '../utils.dart';
import 'user_info_screen.dart';

// cacheKey untuk PhotoCache = cacheKey yang dipakai chat_service
// ('private_$chatId' untuk private chat).
String cacheKeyFor(String chatId) => 'private_$chatId';

// Top-level function untuk compute() isolate — decode + resize + encode di background
String? _processImage(Uint8List bytes) {  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = _resizeMaxSide(decoded, 1024);
  final jpg = img.encodeJpg(resized, quality: 85);
  return base64Encode(jpg);
}

// Top-level function untuk compute() isolate — decode base64 + dimensi di background
_DecodedImage? _decodeImage(String base64) {
  try {
    final bytes = base64Decode(base64);
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return _DecodedImage(bytes, 0, 0);
    return _DecodedImage(bytes, decoded.width, decoded.height);
  } catch (_) {
    return null;
  }
}

// Hasil decode: bytes + dimensi asli agar tampilan proporsional.
class _DecodedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  const _DecodedImage(this.bytes, this.width, this.height);
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

// Top-level function untuk compute() isolate — tanpa watermark: resize 1600px + JPEG
// Kamera kirim foto besar (10-20MB) → decode gagal di penerima kalau tidak di-resize.
String? _passthroughImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = _resizeMaxSide(decoded, 1600);
  final jpg = img.encodeJpg(resized, quality: 90);
  return base64Encode(jpg);
}

class PrivateChatScreen extends StatefulWidget {
  final String chatId;
  final String otherName;
  final String otherUid;
  final String otherGender;
  final String otherCountry;
  final int otherAge;
  final bool otherRegistered;
  const PrivateChatScreen({
    super.key,
    required this.chatId,
    required this.otherName,
    required this.otherUid,
    this.otherGender = '',
    this.otherCountry = '',
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

  late Stream<List<MessageModel>> _msgsStream;
  late Stream<List<PrivateChatInfo>> _chatInfoStream;
  Future<void> Function() _loadOlder = () async {};
  Future<void> Function(String messageId) _msgsHandleFetchImage = (_) async {};
  bool _loadingOlder = false;

  DateTime? _otherLastRead;
  StreamSubscription<List<PrivateChatInfo>>? _chatInfoSub;
  StreamSubscription<List<MessageModel>>? _msgsSub;
  StreamSubscription<String>? _statusSub;
  String _otherStatus = 'offline';
  bool _wasBlocked = false;
  final List<MessageModel> _pending = [];
  // Foto yang sudah dikonfirmasi server (id pesan server) — dipakai dedupe
  // FIFO karena imageData di stream berupa thumbnail, bukan base64 penuh.
  // Hanya foto dengan timestamp setelah screen dibuka yang diproses, supaya
  // history lama tidak ikut menghapus pending.
  final Set<String> _confirmedPhotoIds = {};
  late final DateTime _openedAt;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    activeChatId.value = widget.chatId;
    // Anti-screenshot dikontrol setting admin global (ScreenSecureService).
    // Privasi view_once tetap terjaga via enterViewOnce/exitViewOnce.

    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();

    final msgsHandle = chat.getPrivateChatMessages(widget.chatId);
    _msgsStream = msgsHandle.stream;
    _loadOlder = msgsHandle.loadOlder;
    _msgsHandleFetchImage = msgsHandle.fetchImage;
    // Scroll ke atas → load pesan lama (pagination)
    _scrollCtrl.addListener(_onScrollToLoadOlder);
    _chatInfoStream = chat.getMyPrivateChats(auth.uid ?? '');

    // Dedupe _pending: hapus satu per satu saat server konfirmasi — aman utk double-send text sama
    _msgsSub = _msgsStream.listen((msgs) {
      if (_pending.isEmpty || !mounted) return;
      final mySenderIds = _pending.map((p) => p.senderId).toSet();
      final confirmedTexts = msgs.where((m) => mySenderIds.contains(m.senderId) && m.type == 'text').map((m) => m.text).toList();
      for (final text in confirmedTexts) {
        final idx = _pending.indexWhere((p) => p.type == 'text' && p.text == text);
        if (idx != -1) {
          setState(() { _pending.removeAt(idx); });
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
          final idx = _pending.indexWhere((p) => (p.type == 'image' || p.type == 'view_once'));
          if (idx != -1) {
            setState(() { _pending.removeAt(idx); });
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
  }

  @override
  void dispose() {
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
    super.dispose();
  }

  void _subscribeStatus() {
    _statusSub?.cancel();
    _statusSub = context.read<ChatProvider>().getUserStatus(widget.otherUid).listen((status) {
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
  StreamSubscription<void>? _typingSub;
  Timer? _typingClearTimer;
  DateTime _lastTypingSent = DateTime(2000);
  bool _showTyping = false;

  void _subscribeTyping() {
    _typingSub?.cancel();
    _typingSub = context.read<ChatProvider>().getTypingStream(widget.chatId).listen((_) {
      if (!mounted) return;
      setState(() { _showTyping = true; });
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

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    _msgCtrl.clear();
    _isSending = true;

    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    if (chat.isBlocked(widget.otherUid)) {
      _isSending = false;
      final s = context.read<LocaleProvider>().s;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgBlocked)));
      return;
    }
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) {
      _isSending = false;
      return;
    }

    // Deduct poin sebelum kirim
    final pp = context.read<PointsProvider>();
    final remaining = await pp.deductBeforeSend('text');
    if (remaining < 0) {
      _isSending = false;
      if (mounted) {
        final ss = context.read<LocaleProvider>().s;
        pp.showOutOfPointsDialog(context, ss.isId);
      }
      return;
    }

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
    try {
      await chat.sendPrivateMessage(
        chatId: widget.chatId,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: text,

      );
    } catch (e) {
      if (mounted) {
        setState(() => _pending.remove(pending));
        final s = context.read<LocaleProvider>().s;
        final isBlockedByOther = e.toString().contains('42501') ||
            e.toString().toLowerCase().contains('insufficient_privilege') ||
            e.toString().toLowerCase().contains('policy');
        // Jangan expose detail error teknis ke user
        final msg = isBlockedByOther ? s.msgBlockedByOther : s.errSendFailed;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      _isSending = false;
    }
    if (context.read<PointsProvider>().enabled) {
      context.read<PointsProvider>().showPointsToast(context, context.read<LocaleProvider>().s.isId ? '-1 Poin' : '-1 Point');
    }
    _scrollToBottom();
  }

  Future<void> _sendPhoto() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    // Tolak file > 10MB sebelum proses
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.msgFileTooLarge)));
      }
      return;
    }
    // Decode + resize + encode di background isolate agar UI tidak freeze
    final base64 = await compute(_processImage, bytes);
    if (base64 == null) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errPhotoRead)));
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
    if (rPhoto < 0) { if (mounted) { ppPhoto.showOutOfPointsDialog(context, context.read<LocaleProvider>().s.isId); } return; }
    try {
      await chat.sendPrivateMessage(
        chatId: widget.chatId,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: '',
        type: 'image',
        imageData: base64,
      );
      if (ppPhoto.enabled) {
        ppPhoto.showPointsToast(context, context.read<LocaleProvider>().s.isId ? '-3 Poin' : '-3 Points');
        ppPhoto.oneTimeBonus('first_photo', 10).then((earned) {
          if (earned && mounted) {
            ppPhoto.showPointsToast(context, context.read<LocaleProvider>().s.isId ? '+10 Poin — Foto pertama!' : '+10 Points — First photo!');
          }
        });
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
      }
    }
  }

  Future<void> _sendViewOncePhoto() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final auth = context.read<AuthProvider>();
    // Resize + potong poin paralel — potong ~2 detik
    final results = await Future.wait([
      auth.watermarkEnabled
          ? compute(_processViewOnceImage, (bytes, widget.otherUid))
          : compute(_passthroughImage, bytes),
      context.read<PointsProvider>().deductBeforeSend('view_once'),
    ]);
    final base64 = results[0] as String?;
    if (base64 == null) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errPhotoRead)));
      }
      return;
    }
    if (!mounted) return;
    final rView = results[1] as int;
    if (rView < 0) { if (mounted) { context.read<PointsProvider>().showOutOfPointsDialog(context, context.read<LocaleProvider>().s.isId); } return; }
    final chat = context.read<ChatProvider>();
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    final pp = context.read<PointsProvider>();
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
      await chat.sendPrivateMessage(
        chatId: widget.chatId,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: '',
        type: 'view_once',
        imageData: base64,
      );
      if (pp.enabled) {
        final loc = context.read<LocaleProvider>();
        pp.showPointsToast(context, loc.isId ? '-3 Poin' : '-3 Points');
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() => _pending.remove(pending));
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errSendPhoto)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    // select: rebuild hanya saat isBlocked untuk UID lawan bicara berubah
    final isBlocked = context.select<ChatProvider, bool>((c) => c.isBlocked(widget.otherUid));
    final s = context.watch<LocaleProvider>().s;
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
    final genderLabel = widget.otherGender == 'male' ? s.genderMale : widget.otherGender == 'female' ? s.genderFemale : '';
    final agePart = widget.otherAge > 0 ? '${widget.otherAge}' : '';
    final subtitle = [if (genderLabel.isNotEmpty) '$genderLabel $agePart'.trim(), widget.otherCountry].where((e) => e.isNotEmpty).join(' · ');
    final points = auth.profile?.points ?? 50;

    // Show online bonus toast jika ada yang nunggu
    Future.microtask(() {
      final pp = context.read<PointsProvider>();
      pp.checkAndShowOnlineToast(context, s.isId);
    });

    return Scaffold(
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
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    child: Text(
                      widget.otherName.isNotEmpty ? widget.otherName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: displayStatus == 'online'
                            ? const Color(0xFF69F0AE)
                            : displayStatus == 'idle'
                                ? const Color(0xFFFFD740)
                                : Colors.white38,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primary, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.otherName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.otherRegistered) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 15, color: Color(0xFF8AB4F8)),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      if (_showTyping)
                        Flexible(
                          child: Text(
                            s.typingStatus,
                            style: const TextStyle(
                              color: Color(0xFF69F0AE),
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else if (subtitle.isNotEmpty)
                        Flexible(
                          child: Text(
                            subtitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(width: 8),
                      _StatusIndicator(status: displayStatus),
                      if (context.watch<PointsProvider>().enabled) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '🪙 $points',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: AppTheme.bgCard,
            onSelected: (val) {
              if (val == 'block') {
                chat.blockUser(auth.uid!, widget.otherUid);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.blockSuccess)));
              } else if (val == 'report') {
                _showReportDialog();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'block', child: Text(s.btnBlock, style: const TextStyle(color: AppTheme.danger))),
              PopupMenuItem(value: 'report', child: Text(s.btnReport, style: const TextStyle(color: Colors.orange))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _msgsStream,
              builder: (_, snap) {
                final msgs = snap.data ?? [];
                final all = [...msgs, ..._pending];
                if (all.isEmpty) {
                  // Stream belum emit (data == null) → jangan tampilkan empty state —
                  // mencegah flash "Mulai percakapan!" saat buka chat yang ada isinya.
                  // Hanya tampilkan empty state setelah stream selesai (data != null).
                  if (snap.data == null) return const SizedBox.shrink();
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('👋', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 8),
                        Text(s.startConversation, style: const TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: all.length,
                  itemBuilder: (_, i) {
                    final msg = all[all.length - 1 - i];
                    final isMe = msg.senderId == auth.uid;
                    final isPending = msg.id.startsWith('pending-');
                    final isRead = isMe && !isPending && _otherLastRead != null && msg.timestamp.isBefore(_otherLastRead!);
                    // Image kosong & pesan lama (> 50 dari terbaru) → deferred (icon refresh)
                    final isImageDeferred =
                        msg.type == 'image' && msg.imageData.isEmpty && i >= 50;
                    return _MessageBubble(
                      key: ValueKey(msg.id),
                      msg: msg,
                      chatKey: cacheKeyFor(widget.chatId),
                      isMe: isMe,
                      isRead: isRead,
                      isPending: isPending,
                      isImageDeferred: isImageDeferred,
                      onRetryImage: _msgsHandleFetchImage,
                    );
                  },
                );
              },
            ),
          ),
          if (_showTyping)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 6, 0, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _TypingBubble(),
              ),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(
              color: AppTheme.bgScreen,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, -1)),
              ],
            ),
            child: SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Builder(builder: (ctx) {
                  final pts = ctx.watch<PointsProvider>();
                  final loc = ctx.read<LocaleProvider>();
                  if (!pts.enabled) return const SizedBox.shrink();
                  Color badgeColor;
                  String badgeText;
                  if (pts.points <= 0) {
                    return const SizedBox.shrink();
                  } else if (pts.points <= 5) {
                    badgeColor = Colors.orange;
                    badgeText = loc.s.isId ? '⚠️ ${pts.points} poin — daftar email +100' : '⚠️ ${pts.points} points — register +100';
                  } else if (pts.points <= 10) {
                    badgeColor = Colors.amber;
                    badgeText = loc.s.isId ? '${pts.points} poin — baca room +2' : '${pts.points} points — read room +2';
                  } else if (pts.points <= 20) {
                    badgeColor = Colors.lightGreen;
                    badgeText = loc.s.isId ? '${pts.points} poin' : '${pts.points} points';
                  } else {
                    return const SizedBox.shrink();
                  }
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Text(badgeText, style: TextStyle(color: badgeColor, fontSize: 11), textAlign: TextAlign.center),
                  );
                }),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        onPressed: () => EmojiPickerSheet.show(context, _msgCtrl),
                        icon: const Icon(Icons.emoji_emotions_outlined, size: 22),
                        color: AppTheme.textSecondary,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 132),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppTheme.bgCard, width: 1),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _msgCtrl,
                                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, height: 1.35),
                                decoration: InputDecoration(
                                  hintText: s.hintTypeMessage,
                                  hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                textInputAction: TextInputAction.newline,
                                onSubmitted: (_) => _send(),
                                onChanged: (_) => _sendTypingSignal(),
                                minLines: 1,
                                maxLines: 4,
                                keyboardType: TextInputType.multiline,
                                textCapitalization: TextCapitalization.sentences,
                              ),
                            ),
                            _InputIconBtn(
                              icon: Icons.image_outlined,
                              color: AppTheme.primary,
                              onTap: _sendPhoto,
                              tooltip: context.read<LocaleProvider>().s.tooltipPhoto,
                            ),
                            _InputIconBtn(
                              icon: Icons.timer_outlined,
                              color: Colors.orange,
                              onTap: _sendViewOncePhoto,
                              tooltip: s.viewOnceTap,
                            ),
                            const SizedBox(width: 10),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _msgCtrl,
                      builder: (context, value, _) => AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) => SizeTransition(
                          sizeFactor: anim,
                          axis: Axis.horizontal,
                          axisAlignment: -1,
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: value.text.trim().isEmpty
                            ? const SizedBox(width: 0, key: ValueKey('empty'))
                            : SizedBox(
                                key: const ValueKey('send'),
                                width: 48,
                                height: 48,
                                child: IconButton(
                                  onPressed: _send,
                                  icon: const Icon(Icons.send_rounded, size: 22),
                                  color: Colors.white,
                                  padding: EdgeInsets.zero,
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    shape: const CircleBorder(),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }

  void _showReportDialog() {
    String reason = '';
    final s = context.read<LocaleProvider>().s;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text('${s.btnReport} ${widget.otherName}', style: const TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(hintText: s.reportHint),
          onChanged: (v) => reason = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(context.read<LocaleProvider>().s.btnCancel)),
          TextButton(
            onPressed: () {
              context.read<ChatProvider>().reportUser(
                    reporterId: context.read<AuthProvider>().uid!,
                    reportedId: widget.otherUid,
                    reason: reason,
                  );
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.reportSuccess)));
            },
            child: Text(s.btnReport, style: const TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final String chatKey;
  final bool isMe;
  final bool isRead;
  final bool isPending;
  // Image kosong karena di luar window auto-load (pesan lama) → tampilkan
  // icon refresh; klik memanggil onRetryImage(messageId).
  final bool isImageDeferred;
  final Future<void> Function(String messageId)? onRetryImage;
  const _MessageBubble({
    super.key,
    required this.msg,
    required this.chatKey,
    required this.isMe,
    required this.isRead,
    this.isPending = false,
    this.isImageDeferred = false,
    this.onRetryImage,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = formatTime(msg.timestamp);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? AppTheme.primary.withValues(alpha: 0.25) : AppTheme.bgInput,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isMe ? 14 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 14),
                ),
              ),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (msg.type == 'image' && msg.imageData.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _MessageImage(
                        imageData: msg.imageData,
                        chatKey: chatKey,
                        messageId: msg.id,
                      ),
                    )
                  else if (msg.type == 'image' && msg.imageData.isEmpty && isImageDeferred)
                    _DeferredImage(onTap: () => onRetryImage?.call(msg.id))
                  else if (msg.type == 'view_once' || msg.type == 'view_once_expired')
                    _ViewOnceImage(
                      imageData: msg.imageData,
                      chatKey: chatKey,
                      isMe: isMe,
                      messageId: msg.id,
                      isExpired: msg.type == 'view_once_expired',
                    )
                  else
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.2),
                        children: [
                          TextSpan(text: msg.text),
                          const TextSpan(text: '  '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.belowBaseline,
                            baseline: TextBaseline.alphabetic,
                            child: Text(timeStr, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                          ),
                          if (isMe)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.belowBaseline,
                              baseline: TextBaseline.alphabetic,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 3),
                                child: Icon(
                                  isPending ? Icons.done : (isRead ? Icons.done_all : Icons.done),
                                  size: 12,
                                  color: isPending ? AppTheme.textSecondary : (isRead ? AppTheme.primary : AppTheme.textSecondary),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (msg.type == 'image' || msg.type == 'view_once' || msg.type == 'view_once_expired') ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(timeStr, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                        if (isMe) ...[
                          const SizedBox(width: 3),
                          if (isPending)
                            Icon(Icons.done, size: 12, color: AppTheme.textSecondary)
                          else
                            Icon(
                              isRead ? Icons.done_all : Icons.done,
                              size: 12,
                              color: isRead ? AppTheme.primary : AppTheme.textSecondary,
                            ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Cache decode agar scroll-back tidak resize (glitch). Key = hash imageData.
final _decodedCache = <int, _DecodedImage>{};

// Image yang belum di-load (pesan lama di luar window 50) — tampilkan icon refresh.
class _DeferredImage extends StatelessWidget {
  final VoidCallback? onTap;
  const _DeferredImage({this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        height: 120,
        color: AppTheme.bgInput,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, color: AppTheme.textSecondary, size: 22),
            const SizedBox(height: 4),
            Text(s.msgPhotoTapToLoad, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _MessageImage extends StatefulWidget {
  final String imageData;
  final String chatKey;
  final String messageId;
  const _MessageImage({
    required this.imageData,
    required this.chatKey,
    required this.messageId,
  });

  @override
  State<_MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends State<_MessageImage> {
  _DecodedImage? _decoded;

  @override
  void initState() {
    super.initState();
    final key = widget.imageData.hashCode;
    _decoded = _decodedCache[key];
    if (_decoded == null) _decode(key);
  }

  @override
  void didUpdateWidget(_MessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // imageData berubah (fetch awal kosong → photo download selesai) → re-decode
    if (widget.imageData != oldWidget.imageData && widget.imageData.isNotEmpty) {
      final key = widget.imageData.hashCode;
      _decoded = _decodedCache[key];
      if (_decoded == null) _decode(key);
    }
  }

  Future<void> _decode(int key) async {
    final decoded = await compute(_decodeImage, widget.imageData);
    _decodedCache[key] = decoded!;
    if (!mounted) return;
    setState(() => _decoded = decoded);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    final decoded = _decoded;
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return Container(
        width: 200, height: 200,
        color: AppTheme.bgInput,
        alignment: Alignment.center,
        child: Text(s.msgPhotoExpired, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      );
    }
    final aspect = decoded.width / decoded.height;
    var width = 200.0;
    var height = width / aspect;
    if (height > 280) { height = 280; width = height * aspect; }
    return GestureDetector(
      onTap: () => _openFullscreen(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          decoded.bytes,
          width: width, height: height,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Container(
            width: 200, height: 200,
            color: AppTheme.bgInput,
            alignment: Alignment.center,
            child: Text(s.msgPhotoExpired, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ),
        ),
      ),
    );
  }

  void _openFullscreen() {
    final decoded = _decoded;
    if (decoded == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoViewerScreen(
          bytes: decoded.bytes,
          fullLoader: () => PhotoCache.instance.load(widget.chatKey, widget.messageId),
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final String status;
  const _StatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final Color dotColor;
    final String statusLabel;
    switch (status) {
      case 'online':
        dotColor = const Color(0xFF69F0AE);
        statusLabel = s.statusOnline;
        break;
      case 'idle':
        dotColor = const Color(0xFFFFD740);
        statusLabel = s.statusIdle;
        break;
      default:
        dotColor = Colors.white38;
        statusLabel = s.statusOffline;
        break;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          statusLabel,
          style: TextStyle(
            color: dotColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// Tombol ikon kecil untuk input bar
class _InputIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;
  const _InputIconBtn({required this.icon, required this.color, required this.onTap, required this.tooltip});

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

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = TweenSequence<double>([
            TweenSequenceItem(tween: Tween(begin: 0.3, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
            TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.3).chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
          ]).animate(CurvedAnimation(parent: _ctrl, curve: Interval(i * 0.15, 1, curve: Curves.linear)));
          return FadeTransition(
            opacity: t,
            child: Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: const BoxDecoration(color: AppTheme.textSecondary, shape: BoxShape.circle),
            ),
          );
        }),
      ),
    );
  }
}

// ── View Once Image ──────────────────────────────────────────────────────────
enum _ViewOnceState { idle, viewing, expired }

// Timer & state persist di luar widget lifecycle — ListView.builder recycle
// widget saat scroll, tapi timer harus terus jalan & state tidak boleh reset.
class _ViewOnceTick {
  int left = 10;
  Timer? timer;
  final ValueNotifier<int> countdown = ValueNotifier<int>(10);
  _ViewOnceState _state = _ViewOnceState.idle;
  final ValueNotifier<_ViewOnceState> stateNotifier = ValueNotifier<_ViewOnceState>(_ViewOnceState.idle);
  bool viewerOpen = false;
  _DecodedImage? decoded;

  _ViewOnceState get state => _state;
  set state(_ViewOnceState s) { _state = s; stateNotifier.value = s; }

  void dispose() { timer?.cancel(); countdown.dispose(); stateNotifier.dispose(); }
}
final _viewOnceStates = <String, _ViewOnceTick>{};

class _ViewOnceImage extends StatefulWidget {
  final String imageData;
  final String chatKey;
  final bool isMe;
  final String? messageId;
  final bool isExpired;
  const _ViewOnceImage({
    required this.imageData,
    required this.chatKey,
    required this.isMe,
    this.messageId,
    this.isExpired = false,
  });

  @override
  State<_ViewOnceImage> createState() => _ViewOnceImageState();
}

class _ViewOnceImageState extends State<_ViewOnceImage> {
  late _ViewOnceTick _tick;
  _DecodedImage? _decoded;

  @override
  void initState() {
    super.initState();
    final id = widget.messageId ?? 'pending-${widget.imageData.hashCode}';
    _tick = _viewOnceStates[id] ?? (_viewOnceStates[id] = _ViewOnceTick());
    if (widget.isExpired && _tick.state != _ViewOnceState.viewing) {
      _tick.state = _ViewOnceState.expired;
    }
    // View-once terkunci: JANGAN decode/load image — cukup kartu terkunci.
    if (_tick.state == _ViewOnceState.expired) return;
    _decoded = _tick.decoded;
    if (_decoded == null) _decode();
  }

  @override
  void didUpdateWidget(_ViewOnceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // View-once terkunci: skip — jangan load image.
    if (_tick.state == _ViewOnceState.expired) return;
    // imageData berubah (fetch awal kosong → photo download selesai) → re-decode
    if (widget.imageData != oldWidget.imageData && widget.imageData.isNotEmpty) {
      _decoded = _tick.decoded;
      if (_decoded == null) _decode();
    }
  }

  @override
  void dispose() {
    // Jangan dispose _tick — timer harus terus jalan via _viewOnceStates
    super.dispose();
  }

  Future<void> _decode() async {
    if (widget.imageData.isEmpty) return;
    final decoded = await compute(_decodeImage, widget.imageData);
    _tick.decoded = decoded;
    if (!mounted) return;
    setState(() => _decoded = decoded);
    // Kalau user sudah tap "Lihat" sebelum gambar siap → mulai timer sekarang
    if (_tick.state == _ViewOnceState.viewing && _tick.timer == null && decoded != null) {
      _beginCountdown();
    }
  }

  void _startViewing() {
    if (_tick.state != _ViewOnceState.idle) return;
    _tick.state = _ViewOnceState.viewing;
    setState(() {});
    ScreenSecureService.enterViewOnce();
    // Mulai timer hanya kalau gambar sudah siap — kalau belum, nunggu _decode selesai
    if (_decoded != null) {
      _beginCountdown();
    }
  }

  void _beginCountdown() {
    if (_tick.timer != null) return;
    _tick.left = 10;
    _tick.countdown.value = 10;
    _tick.timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _tick.left--;
      _tick.countdown.value = _tick.left;
      if (_tick.left <= 0) {
        t.cancel();
        _tick.timer = null;
        _tick.state = _ViewOnceState.expired;
        ScreenSecureService.exitViewOnce();
        if (_tick.viewerOpen && mounted) Navigator.of(context).maybePop();
        if (mounted) { setState(() {}); _clearFromServer(); }
        return;
      }
      if (mounted) setState(() {});
    });
  }

  void _openViewer() {
    if (_decoded == null || _tick.state != _ViewOnceState.viewing || !mounted) return;
    _tick.viewerOpen = true;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => _PhotoViewerScreen(
            bytes: _decoded!.bytes,
            fullLoader: () {
              final id = widget.messageId;
              if (id == null || id.startsWith('pending-')) return Future.value(null);
              return PhotoCache.instance.load(widget.chatKey, id);
            },
            countdown: _tick.countdown,
          ),
        ))
        .whenComplete(() => _tick.viewerOpen = false);
  }

  Future<void> _clearFromServer() async {
    final id = widget.messageId;
    if (id == null || id.startsWith('pending-')) return;
    try {
      await context.read<ChatProvider>().clearViewOnceImage(id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_ViewOnceState>(
      valueListenable: _tick.stateNotifier,
      builder: (_, st, __) {
    final s = context.read<LocaleProvider>().s;

    // Pengirim lihat foto asli + badge
    if (widget.isMe) {
      final decoded = _decoded;
      final w = decoded != null ? _viewWidth(decoded) : 200.0;
      final h = decoded != null ? _viewHeight(decoded) : 200.0;
      return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
            fit: StackFit.expand,
            children: [
              decoded != null
                  ? Image.memory(
                      decoded.bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                    )
                  : Container(
                      color: AppTheme.bgInput,
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 28, height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
                      ),
                    ),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, color: Colors.white, size: 12),
                      const SizedBox(width: 3),
                      Text(s.msgViewOnce,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
            ),
          ),
      );
    }

    // Penerima — idle: kartu modern "tekan untuk melihat"
    if (_tick.state == _ViewOnceState.idle) {
      return GestureDetector(
        onTap: _startViewing,
        child: Container(
          width: 220,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E88E5), Color(0xFF00BCD4)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00BCD4).withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.22),
                ),
                child: const Icon(
                  Icons.remove_red_eye_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                s.viewOnceTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                s.viewOnceTap,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  s.btnView,
                  style: const TextStyle(
                    color: Color(0xFF1E88E5),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Expired — kartu terkunci (tanpa image — hemat memori & tidak load foto)
    if (_tick.state == _ViewOnceState.expired) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 200,
          height: 140,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF37474F), Color(0xFF263238)],
            ),
          ),
          child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_clock_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.viewOnceExpired,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.viewOnceExpiredHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      );
    }

    // Viewing — tampilkan foto proporsional + countdown; tap untuk memperbesar
    final decoded = _decoded;
    final vw = decoded != null ? _viewWidth(decoded) : 200.0;
    final vh = decoded != null ? _viewHeight(decoded) : 200.0;
    return GestureDetector(
      onTap: _openViewer,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: vw,
            height: vh,
            child: Stack(
              fit: StackFit.expand,
              children: [
                decoded != null
                    ? Image.memory(
                        decoded.bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true)
                    : Container(
                        color: AppTheme.bgInput,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 28, height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
                        ),
                      ),
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, color: Colors.white, size: 12),
                        const SizedBox(width: 3),
                        ValueListenableBuilder<int>(
                          valueListenable: _tick.countdown,
                          builder: (_, v, __) => Text('${v}s',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
    );
  }

  // Lebar/t tinggi tampilan proporsional (maks 200×280) sesuai rasio asli.
  static double _viewWidth(_DecodedImage d) {
    final aspect = d.width / d.height;
    var width = 200.0;
    var height = width / aspect;
    if (height > 280) {
      height = 280;
      width = height * aspect;
    }
    return width;
  }

  static double _viewHeight(_DecodedImage d) {
    final aspect = d.width / d.height;
    var width = 200.0;
    var height = width / aspect;
    if (height > 280) {
      height = 280;
      width = height * aspect;
    }
    return height;
  }
}

// ── Photo Viewer Fullscreen ─────────────────────────────────────────────────
// Menampilkan foto fullscreen (hitam) dengan zoom + close. Bubble mengirim
// THUMBNAIL (bytes) supaya viewer langsung tampil, lalu fullLoader mengambil
// versi full-res dari PhotoCache dan menggantinya begitu siap.
// Untuk view-once, countdown diteruskan dari state pemilik sehingga timer
// terus berjalan.
class _PhotoViewerScreen extends StatefulWidget {
  final Uint8List bytes;
  final Future<String?> Function()? fullLoader;
  final ValueNotifier<int>? countdown;
  const _PhotoViewerScreen({required this.bytes, this.fullLoader, this.countdown});

  @override
  State<_PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<_PhotoViewerScreen> {
  Uint8List? _fullBytes;

  @override
  void initState() {
    super.initState();
    _loadFull();
  }

  Future<void> _loadFull() async {
    final loader = widget.fullLoader;
    if (loader == null) return;
    try {
      final b64 = await loader();
      if (b64 == null || b64.isEmpty || !mounted) return;
      final bytes = await compute(_b64ToBytes, b64);
      if (bytes == null || !mounted) return;
      setState(() => _fullBytes = bytes);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _fullBytes ?? widget.bytes;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            if (_fullBytes == null && widget.fullLoader != null)
              const Positioned(
                top: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Tutup',
              ),
            ),
            if (widget.countdown != null)
              Positioned(
                top: 12,
                right: 16,
                child: ValueListenableBuilder<int>(
                  valueListenable: widget.countdown!,
                  builder: (_, secs, __) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text('${secs}s',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Top-level untuk compute() — base64 → bytes (fullscreen viewer).
Uint8List? _b64ToBytes(String b64) {
  try { return base64Decode(b64); } catch (_) { return null; }
}
