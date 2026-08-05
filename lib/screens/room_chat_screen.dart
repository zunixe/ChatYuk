import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/room_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../main.dart';
import 'private_chat_screen.dart';

class RoomChatScreen extends StatefulWidget {
  final RoomModel room;
  const RoomChatScreen({super.key, required this.room});

  @override
  State<RoomChatScreen> createState() => _RoomChatScreenState();
}

class _RoomChatScreenState extends State<RoomChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _showUsers = false;
  AuthProvider? _auth;
  ChatProvider? _chat;
  int _lastMsgCount = 0;

  // Hoisted streams — bukan dibuat di build method
  late Stream<List<MessageModel>> _msgsStream;
  late Stream<List<UserModel>> _usersStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _auth = context.read<AuthProvider>();
    _chat = context.read<ChatProvider>();
  }

  @override
  void initState() {
    super.initState();
    activeChatId.value = widget.room.id;
    final chat = context.read<ChatProvider>();
    _msgsStream = chat.getRoomMessages(widget.room.id);
    _usersStream = chat.getOnlineUsersInRoom(widget.room.id);
    _joinRoom();
  }

  Future<void> _joinRoom() async {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    if (auth.profile != null) {
      await chat.joinRoom(widget.room.id, auth.profile!);
      await chat.loadBlockedUids(auth.uid!);
    }
  }

  @override
  void dispose() {
    if (activeChatId.value == widget.room.id) {
      activeChatId.value = null;
    }
    if (_auth?.uid != null) {
      _chat?.leaveRoom(widget.room.id, _auth!.uid!);
    }
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    await chat.sendRoomMessage(
      roomId: widget.room.id,
      senderId: auth.uid!,
      senderName: auth.profile!.nickname,
      senderGender: auth.profile!.gender,
      text: text,
    );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final s = context.watch<LocaleProvider>().s;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.room.icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(widget.room.name),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showUsers ? Icons.chat : Icons.people),
            onPressed: () => setState(() => _showUsers = !_showUsers),
          ),
        ],
      ),
      body: Column(
        children: [
          // Online users panel
          if (_showUsers)
            Container(
              height: 120,
              color: AppTheme.bgCard,
              child: StreamBuilder<List<UserModel>>(
              stream: _usersStream,
                builder: (_, snap) {
                  final users = snap.data ?? [];
                  if (users.isEmpty) {
                    return Center(
                      child: Text(s.noOnlineUsers, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    );
                  }
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(12),
                    itemCount: users.length,
                    itemBuilder: (_, i) => _UserChip(user: users[i], myUid: auth.uid),
                  );
                },
              ),
            ),

          // Messages
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _msgsStream,
              builder: (_, snap) {
                final msgs = snap.data ?? [];
                if (msgs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('👋', style: TextStyle(fontSize: 40)),
                        SizedBox(height: 8),
                        Text('Mulai percakapan!', style: TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  );
                }
                // Scroll ke bawah hanya saat ada pesan baru
                if (msgs.length > _lastMsgCount) {
                  _lastMsgCount = msgs.length;
                  _scrollToBottom();
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) => _MessageBubble(
                    msg: msgs[i],
                    isMe: msgs[i].senderId == auth.uid,
                    onTapUser: () => _onTapUser(msgs[i], auth),
                  ),
                );
              },
            ),
          ),

          // Input
          _ChatInput(controller: _msgCtrl, onSend: _send),
        ],
      ),
    );
  }

  void _onTapUser(MessageModel msg, AuthProvider auth) {
    if (msg.senderId == auth.uid) return;
    if (context.read<ChatProvider>().isBlocked(msg.senderId)) {
      final s = context.read<LocaleProvider>().s;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.msgBlocked)),
      );
      return;
    }
    final s = context.read<LocaleProvider>().s;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _genderColor(msg.senderGender),
                    child: Text(msg.senderName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(msg.senderName, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                        Text(msg.senderGender == 'male' ? s.genderMale : msg.senderGender == 'female' ? s.genderFemale : s.genderOther,
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble, color: AppTheme.primary),
              title: Text(s.titlePrivateChat, style: const TextStyle(color: AppTheme.textPrimary)),
              onTap: () async {
                Navigator.of(context).pop();
                final chatId = await context.read<ChatProvider>().startPrivateChat(
                  myUid: auth.uid!,
                  otherUid: msg.senderId,
                  myName: auth.profile!.nickname,
                  otherName: msg.senderName,
                  myGender: auth.profile!.gender,
                  otherGender: msg.senderGender,
                  myAge: auth.profile!.age,
                );
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PrivateChatScreen(chatId: chatId, otherName: msg.senderName, otherUid: msg.senderId, otherGender: msg.senderGender, otherCountry: '')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: AppTheme.danger),
              title: const Text('Block', style: TextStyle(color: AppTheme.danger)),
              onTap: () async {
                Navigator.of(context).pop();
                await context.read<ChatProvider>().blockUser(auth.uid!, msg.senderId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User diblokir')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag, color: Colors.orange),
              title: const Text('Report', style: TextStyle(color: Colors.orange)),
              onTap: () {
                Navigator.of(context).pop();
                _showReportDialog(msg.senderId, msg.senderName);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDialog(String reportedId, String reportedName) {
    String reason = '';
    final s = context.read<LocaleProvider>().s;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text('${s.btnReport} $reportedName', style: const TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(hintText: s.reportHint),
          onChanged: (v) => reason = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Batal')),
          TextButton(
            onPressed: () {
              context.read<ChatProvider>().reportUser(reporterId: context.read<AuthProvider>().uid!, reportedId: reportedId, reason: reason);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.reportSuccess)));
            },
            child: Text(s.btnReport, style: const TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }

  Color _genderColor(String gender) {
    switch (gender) {
      case 'male':
        return AppTheme.male;
      case 'female':
        return AppTheme.female;
      default:
        return AppTheme.accent;
    }
  }
}

class _UserChip extends StatelessWidget {
  final UserModel user;
  final String? myUid;
  const _UserChip({required this.user, this.myUid});

  @override
  Widget build(BuildContext context) {
    final isMe = user.uid == myUid;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: isMe ? AppTheme.primary : _genderColor(user.gender),
            child: Text(
              user.initial,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isMe ? 'Kamu' : user.nickname,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Color _genderColor(String gender) {
    switch (gender) {
      case 'male':
        return AppTheme.male;
      case 'female':
        return AppTheme.female;
      default:
        return AppTheme.accent;
    }
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  final VoidCallback onTapUser;
  const _MessageBubble({required this.msg, required this.isMe, required this.onTapUser});

  @override
  Widget build(BuildContext context) {
    final color = msg.senderGender == 'male'
        ? AppTheme.male
        : msg.senderGender == 'female'
            ? AppTheme.female
            : AppTheme.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTapUser,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: isMe ? AppTheme.primary : color,
              child: Text(
                msg.senderName[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onTapUser,
                  child: Text(
                    msg.senderName,
                    style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe ? AppTheme.primary.withValues(alpha: 0.2) : AppTheme.bgInput,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    msg.text,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
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

class _ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _ChatInput({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: s.hintTypeMessage,
                  isDense: true,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onSend,
              icon: const Icon(Icons.send, color: AppTheme.primary),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
