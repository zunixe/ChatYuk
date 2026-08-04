import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../main.dart';

class PrivateChatScreen extends StatefulWidget {
  final String chatId;
  final String otherName;
  final String otherUid;
  const PrivateChatScreen({super.key, required this.chatId, required this.otherName, required this.otherUid});

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    activeChatId.value = widget.chatId;
  }

  @override
  void dispose() {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User ini diblokir, tidak bisa kirim pesan')),
      );
      return;
    }
    try {
      await chat.sendPrivateMessage(
        chatId: widget.chatId,
        senderId: auth.uid!,
        senderName: auth.profile!.nickname,
        senderGender: auth.profile!.gender,
        text: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal kirim: $e')),
        );
      }
    }
    _scrollToBottom();
  }

  Future<void> _sendPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 70,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membaca gambar')),
        );
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
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal kirim foto: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.accent,
              child: Text(
                widget.otherName[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Text(widget.otherName),
          ],
        ),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            color: AppTheme.bgCard,
            onSelected: (val) {
              if (val == 'block') {
                chat.blockUser(auth.uid!, widget.otherUid);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('User diblokir')),
                );
              } else if (val == 'report') {
                _showReportDialog();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'block', child: Text('Block', style: TextStyle(color: AppTheme.danger))),
              const PopupMenuItem(value: 'report', child: Text('Report', style: TextStyle(color: Colors.orange))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: chat.getPrivateChatMessages(widget.chatId),
              builder: (_, snap) {
                final msgs = snap.data ?? [];
                if (msgs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('👋', style: TextStyle(fontSize: 40)),
                        SizedBox(height: 8),
                        Text('Mulai percakapan pribadi!', style: TextStyle(color: AppTheme.textSecondary)),
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
                                    Text(
                                      msg.text,
                                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTime(msg.timestamp),
                                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
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
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Ketik pesan...',
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _send,
                    icon: const Icon(Icons.send, color: AppTheme.primary),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }  void _showReportDialog() {
    String reason = '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text('Report ${widget.otherName}', style: const TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Alasan report...'),
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
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Terima kasih, report diterima')));
            },
            child: const Text('Report', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}

class _MessageImage extends StatelessWidget {
  final String imageData;
  const _MessageImage({required this.imageData});

  @override
  Widget build(BuildContext context) {
    try {
      final bytes = base64Decode(imageData);
      return Image.memory(
        bytes,
        width: 200,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const _BrokenImage(),
      );
    } catch (_) {
      return const _BrokenImage();
    }
  }
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 120,
      color: AppTheme.bgInput,
      alignment: Alignment.center,
      child: const Text('🖼️ Gambar rusak', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
    );
  }
}
