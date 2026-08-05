import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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

class PrivateChatScreen extends StatefulWidget {
  final String chatId;
  final String otherName;
  final String otherUid;
  final String otherGender;
  final String otherCountry;
  final int otherAge;
  const PrivateChatScreen({
    super.key,
    required this.chatId,
    required this.otherName,
    required this.otherUid,
    this.otherGender = '',
    this.otherCountry = '',
    this.otherAge = 0,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Hoisted streams
  late Stream<List<MessageModel>> _msgsStream;
  late Stream<List<PrivateChatInfo>> _chatInfoStream;

  // Read receipt — updated dari single subscription
  DateTime? _otherLastRead;
  StreamSubscription<List<PrivateChatInfo>>? _chatInfoSub;

  @override
  void initState() {
    super.initState();
    activeChatId.value = widget.chatId;

    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();

    // Hoist stream ke initState — bukan di build
    _msgsStream = chat.getPrivateChatMessages(widget.chatId);
    _chatInfoStream = chat.getMyPrivateChats(auth.uid ?? '');

    // Subscribe sekali untuk lastReadAt — bukan per bubble
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

    // reset unread count saat buka chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (auth.uid != null) chat.markAsRead(widget.chatId, auth.uid!);
    });
  }

  @override
  void dispose() {
    _chatInfoSub?.cancel();
    if (activeChatId.value == widget.chatId) {
      activeChatId.value = null;
    }
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(0);
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    if (chat.isBlocked(widget.otherUid)) {
      final s = context.read<LocaleProvider>().s;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgBlocked)));
      return;
    }
    try {
      await chat.sendPrivateMessage(
        chatId: widget.chatId,
        senderId: auth.uid!,
        senderName: auth.profile!.nickname,
        senderGender: auth.profile!.gender,
        text: text,
        receiverId: widget.otherUid,
      );
    } catch (e) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errSendFailed}$e')));
      }
    }
    _scrollToBottom();
  }

  Future<void> _sendPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 70);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errPhotoRead)));
      }
      return;
    }

    final resized = img.copyResize(decoded, width: 512, height: 512);
    final jpg = img.encodeJpg(resized, quality: 70);
    final base64 = base64Encode(jpg);

    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    try {
      await chat.sendPrivateMessage(
        chatId: widget.chatId,
        senderId: auth.uid!,
        senderName: auth.profile!.nickname,
        senderGender: auth.profile!.gender,
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

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final s = context.watch<LocaleProvider>().s;
    final genderLabel = widget.otherGender == 'male' ? s.genderMale : widget.otherGender == 'female' ? s.genderFemale : '';
    final agePart = widget.otherAge > 0 ? '${widget.otherAge}' : '';
    final subtitle = [if (genderLabel.isNotEmpty) '$genderLabel $agePart'.trim(), widget.otherCountry].where((e) => e.isNotEmpty).join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.accent,
                  child: Text(widget.otherName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Text(widget.otherName),
              ],
            ),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ],
        ),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
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
                if (msgs.isEmpty) {
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
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final msg = msgs[msgs.length - 1 - i];
                    final isMe = msg.senderId == auth.uid;
                    final isRead = isMe && _otherLastRead != null && msg.timestamp.isBefore(_otherLastRead!);
                    return _MessageBubble(
                      msg: msg,
                      isMe: isMe,
                      isRead: isRead,
                    );
                  },
                );
              },
            ),
          ),
          // Input
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: AppTheme.bgCard,
              border: Border(top: BorderSide(color: AppTheme.divider)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    onPressed: _sendPhoto,
                    icon: const Icon(Icons.image_outlined, color: AppTheme.primary),
                    style: IconButton.styleFrom(backgroundColor: AppTheme.primary.withValues(alpha: 0.15)),
                  ),
                  const SizedBox(width: 8),
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Batal')),
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

// Bubble pesan — StatelessWidget, isRead diterima sebagai param (bukan StreamBuilder per bubble)
class _MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  final bool isRead;
  const _MessageBubble({required this.msg, required this.isMe, required this.isRead});

  @override
  Widget build(BuildContext context) {
    final h = msg.timestamp.hour.toString().padLeft(2, '0');
    final m = msg.timestamp.minute.toString().padLeft(2, '0');
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
                      child: _MessageImage(imageData: msg.imageData, timestamp: msg.timestamp),
                    )
                  else
                    Text(msg.text, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$h:$m', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                      if (isMe) ...[
                        const SizedBox(width: 3),
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

// StatefulWidget — decode base64 sekali di initState, bukan setiap build
class _MessageImage extends StatefulWidget {
  final String imageData;
  final DateTime? timestamp;
  const _MessageImage({required this.imageData, this.timestamp});

  @override
  State<_MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends State<_MessageImage> {
  Uint8List? _bytes;
  bool _expired = false;
  Timer? _expireTimer;

  @override
  void initState() {
    super.initState();
    if (widget.timestamp != null) {
      final expireAt = widget.timestamp!.add(const Duration(seconds: 10));
      final now = DateTime.now();
      if (expireAt.isBefore(now)) {
        _expired = true;
      } else {
        // Decode bytes saat belum expired
        try { _bytes = base64Decode(widget.imageData); } catch (_) { _bytes = null; }
        // Timer untuk auto-expire tepat saat waktunya habis
        final remaining = expireAt.difference(now);
        _expireTimer = Timer(remaining, () {
          if (mounted) setState(() { _expired = true; _bytes = null; });
        });
      }
    } else {
      try { _bytes = base64Decode(widget.imageData); } catch (_) { _bytes = null; }
    }
  }

  @override
  void dispose() {
    _expireTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    if (_expired || _bytes == null) {
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
