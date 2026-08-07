import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
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
import '../services/chat_service.dart';
import '../main.dart';
import '../utils.dart';
import 'user_info_screen.dart';

// Top-level function untuk compute() isolate — decode + resize + encode di background
String? _processImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = img.copyResize(decoded, width: 512, height: 512);
  final jpg = img.encodeJpg(resized, quality: 70);
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

  DateTime? _otherLastRead;
  StreamSubscription<List<PrivateChatInfo>>? _chatInfoSub;
  StreamSubscription<List<MessageModel>>? _msgsSub;
  StreamSubscription<String>? _statusSub;
  String _otherStatus = 'offline';
  bool _wasBlocked = false;
  final List<MessageModel> _pending = [];

  @override
  void initState() {
    super.initState();
    activeChatId.value = widget.chatId;

    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();

    _msgsStream = chat.getPrivateChatMessages(widget.chatId);
    _chatInfoStream = chat.getMyPrivateChats(auth.uid ?? '');

    // Dedupe _pending di listener, bukan di build() — lebih aman dan efisien
    _msgsSub = _msgsStream.listen((msgs) {
      if (_pending.isEmpty || !mounted) return;
      final confirmedText = msgs.where((m) => m.type == 'text').map((m) => m.text).toSet();
      final toRemove = _pending.where((p) => p.type == 'text' && confirmedText.contains(p.text)).toList();
      if (toRemove.isNotEmpty) setState(() { for (final p in toRemove) _pending.remove(p); });
    });

    // Subscribe status realtime lawan bicara
    // Kalau diblokir, tampilkan offline langsung tanpa fetch DB
    _wasBlocked = context.read<ChatProvider>().isBlocked(widget.otherUid);
    if (!_wasBlocked) {
      _subscribeStatus();
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
      if (mounted) setState(() => _otherStatus = status);
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  bool _isSending = false;

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
        receiverId: widget.otherUid,
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
    _scrollToBottom();
  }

  Future<void> _sendPhoto() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    // Tolak file > 10MB sebelum proses
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File terlalu besar. Maksimal 10MB.')));
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
    try {
      await chat.sendPrivateMessage(
        chatId: widget.chatId,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: '',
        type: 'image',
        imageData: base64,
        receiverId: widget.otherUid,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errSendPhoto}$e')));
      }
    }
  }

  Future<void> _sendViewOncePhoto() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
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
    try {
      await chat.sendPrivateMessage(
        chatId: widget.chatId,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: '',
        type: 'view_once',
        imageData: base64,
        receiverId: widget.otherUid,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errSendPhoto}$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final chat = context.watch<ChatProvider>(); // watch untuk detect block/unblock
    final s = context.watch<LocaleProvider>().s;
    // Kalau diblokir, tampilkan offline — sembunyikan status asli
    final isBlocked = chat.isBlocked(widget.otherUid);
    // Saat unblock: re-subscribe status realtime
    if (_wasBlocked && !isBlocked) {
      _wasBlocked = false;
      _subscribeStatus();
    } else if (!_wasBlocked && isBlocked) {
      _wasBlocked = true;
      _statusSub?.cancel();
      _statusSub = null;
    }
    final displayStatus = isBlocked ? 'offline' : _otherStatus;
    final genderLabel = widget.otherGender == 'male' ? s.genderMale : widget.otherGender == 'female' ? s.genderFemale : '';
    final agePart = widget.otherAge > 0 ? '${widget.otherAge}' : '';
    final subtitle = [if (genderLabel.isNotEmpty) '$genderLabel $agePart'.trim(), widget.otherCountry].where((e) => e.isNotEmpty).join(' · ');

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
                      widget.otherName[0].toUpperCase(),
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
                      if (subtitle.isNotEmpty)
                        Expanded(
                          child: Text(
                            subtitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      _StatusIndicator(status: displayStatus),
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
                    return _MessageBubble(
                      key: ValueKey(msg.id),
                      msg: msg,
                      isMe: isMe,
                      isRead: isRead,
                      isPending: isPending,
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: AppTheme.bgCard,
              border: Border(top: BorderSide(color: AppTheme.divider)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Tombol foto kecil
                  _InputIconBtn(
                    icon: Icons.image_outlined,
                    color: AppTheme.primary,
                    onTap: _sendPhoto,
                    tooltip: 'Foto',
                  ),
                  const SizedBox(width: 4),
                  // Tombol sekali lihat kecil
                  _InputIconBtn(
                    icon: Icons.timer_outlined,
                    color: Colors.orange,
                    onTap: _sendViewOncePhoto,
                    tooltip: s.viewOnceTap,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                      decoration: InputDecoration(hintText: s.hintTypeMessage, isDense: true),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _send,
                    icon: const Icon(Icons.send, color: AppTheme.primary),
                    style: IconButton.styleFrom(backgroundColor: AppTheme.primary.withValues(alpha: 0.15)),
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
  final bool isMe;
  final bool isRead;
  final bool isPending;
  const _MessageBubble({super.key, required this.msg, required this.isMe, required this.isRead, this.isPending = false});

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
                      child: _MessageImage(imageData: msg.imageData),
                    )
                  else if (msg.type == 'view_once')
                    _ViewOnceImage(imageData: msg.imageData, isMe: isMe)
                  else
                    Text(msg.text, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageImage extends StatefulWidget {
  final String imageData;
  const _MessageImage({required this.imageData});

  @override
  State<_MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends State<_MessageImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    try { _bytes = base64Decode(widget.imageData); } catch (_) { _bytes = null; }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    if (_bytes == null) {
      return Container(
        width: 200, height: 120,
        color: AppTheme.bgInput,
        alignment: Alignment.center,
        child: Text(s.msgPhotoExpired, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      );
    }
    return Image.memory(
      _bytes!,
      width: 200,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Container(
        width: 200, height: 120,
        color: AppTheme.bgInput,
        alignment: Alignment.center,
        child: Text(s.msgPhotoExpired, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final String status;
  const _StatusIndicator({super.key, required this.status});

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
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

// ── View Once Image ──────────────────────────────────────────────────────────
enum _ViewOnceState { idle, viewing, expired }

class _ViewOnceImage extends StatefulWidget {
  final String imageData;
  final bool isMe;
  const _ViewOnceImage({super.key, required this.imageData, required this.isMe});

  @override
  State<_ViewOnceImage> createState() => _ViewOnceImageState();
}

class _ViewOnceImageState extends State<_ViewOnceImage> {
  _ViewOnceState _state = _ViewOnceState.idle;
  int _secondsLeft = 10;
  Timer? _timer;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    try { _bytes = base64Decode(widget.imageData); } catch (_) {}
  }

  static const _windowChannel = MethodChannel('com.chatyuk.chatyuk/window');

  static Future<void> _setSecure(bool secure) async {
    try {
      await _windowChannel.invokeMethod(secure ? 'setSecure' : 'clearSecure');
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_state == _ViewOnceState.viewing) {
      _setSecure(false);
    }
    super.dispose();
  }

  void _startViewing() {
    if (_state != _ViewOnceState.idle) return;
    setState(() {
      _state = _ViewOnceState.viewing;
      _secondsLeft = 10;
    });
    _setSecure(true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { _secondsLeft--; });
      if (_secondsLeft <= 0) {
        t.cancel();
        _setSecure(false);
        setState(() => _state = _ViewOnceState.expired);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;

    // Pengirim hanya lihat ikon kamera — tidak bisa buka
    if (widget.isMe) {
      return Container(
        width: 200, height: 80,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer_outlined, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(s.msgViewOnce,
              style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    // Penerima — idle: tombol lihat
    if (_state == _ViewOnceState.idle) {
      return GestureDetector(
        onTap: _startViewing,
        child: Container(
          width: 200, height: 80,
          decoration: BoxDecoration(
            color: AppTheme.bgInput,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.remove_red_eye_outlined, color: AppTheme.primary, size: 24),
              const SizedBox(height: 6),
              Text(s.viewOnceTap,
                style: const TextStyle(color: AppTheme.primary, fontSize: 12),
                textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    // Expired — blur penuh
    if (_state == _ViewOnceState.expired) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _bytes != null
                ? ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Image.memory(_bytes!, width: 200, fit: BoxFit.cover),
                  )
                : Container(width: 200, height: 120, color: AppTheme.bgInput),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, color: Colors.white70, size: 24),
                  const SizedBox(height: 4),
                  Text(s.viewOnceExpired,
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Viewing — tampilkan foto + countdown timer + overlay
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _bytes != null
              ? Image.memory(_bytes!, width: 200, fit: BoxFit.cover, gaplessPlayback: true)
              : Container(width: 200, height: 120, color: AppTheme.bgInput),
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
                Text('${_secondsLeft}s',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
