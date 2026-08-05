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
import '../utils.dart';

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
  final _imagePicker = ImagePicker();

  late Stream<List<MessageModel>> _msgsStream;
  late Stream<List<PrivateChatInfo>> _chatInfoStream;

  DateTime? _otherLastRead;
  StreamSubscription<List<PrivateChatInfo>>? _chatInfoSub;
  final List<MessageModel> _pending = [];

  @override
  void initState() {
    super.initState();
    activeChatId.value = widget.chatId;

    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();

    _msgsStream = chat.getPrivateChatMessages(widget.chatId);
    _chatInfoStream = chat.getMyPrivateChats(auth.uid ?? '');

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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.msgBlocked)));
      return;
    }
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    final pending = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
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
      // Pending tetap tampil sampai stream server mengkonfirmasi (dedupe di builder).
    } catch (e) {
      if (mounted) {
        setState(() => _pending.remove(pending));
        final s = context.read<LocaleProvider>().s;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errSendFailed}$e')));
      }
    }
    _scrollToBottom();
  }

  Future<void> _sendPhoto() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 70);
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
                // Pending yang sudah dikonfirmasi server (muncul di stream) tidak perlu ditampilkan lagi.
                final confirmedText = msgs.where((m) => m.type == 'text').map((m) => m.text).toSet();
                if (_pending.isNotEmpty) {
                  final toRemove = _pending.where((p) => p.type == 'text' && confirmedText.contains(p.text)).toList();
                  if (toRemove.isNotEmpty) {
                    for (final p in toRemove) { _pending.remove(p); }
                    // Hapus pending via setState tidak aman di build; gunakan callback.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() {});
                    });
                  }
                }
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

class _MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  final bool isRead;
  final bool isPending;
  const _MessageBubble({required this.msg, required this.isMe, required this.isRead, this.isPending = false});

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
                            isRead ? Icons.done_all : Icons.done_all,
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
