import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/room_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../utils.dart';
import '../main.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/private_chat_message.dart';
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
  bool _sheetOpen = false;
  late AuthProvider _auth;
  late ChatProvider _chat;
  int _lastMsgCount = 0;
  bool _readBonusClaimed = false;
  int _roomSendCount = 0;
  PointsProvider? _pointsProv;

  late Stream<List<MessageModel>> _msgsStream;
  late Stream<List<UserModel>> _usersStream;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _chat = context.read<ChatProvider>();
    activeChatId.value = widget.room.id;
    final msgsHandle = _chat.getRoomMessages(widget.room.id);
    _msgsStream = msgsHandle.stream;
    _usersStream = _chat.getOnlineUsersInRoom(widget.room.id);
    _pointsProv = context.read<PointsProvider>();
    _joinRoom();
    _scrollCtrl.addListener(_onRoomScroll);
  }

  void _onRoomScroll() {
    if (_readBonusClaimed) return;
    if (_scrollCtrl.hasClients && _scrollCtrl.position.pixels < 300) {
      _readBonusClaimed = true;
      _pointsProv?.roomReadBonus().then((_) {
        if (mounted && _pointsProv?.enabled == true) {
          final s = context.read<LocaleProvider>().s;
          _pointsProv?.showPointsToast(context, s.isId ? '+2 Poin — Baca room' : '+2 Points — Room read');
        }
      });
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

  @override
  void dispose() {
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

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    _msgCtrl.clear();
    _isSending = true;

    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) { _isSending = false; return; }
    final pp = context.read<PointsProvider>();
    final remaining = await pp.deductBeforeSend('text');
    if (remaining < 0) { _isSending = false; if (mounted) { final ss = context.read<LocaleProvider>().s; pp.showOutOfPointsDialog(context, ss.isId); } return; }
    try {
      await chat.sendRoomMessage(
        roomId: widget.room.id,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: text,
      );
      if (pp.enabled) {
        pp.showPointsToast(context, context.read<LocaleProvider>().s.isId ? '-1 Poin' : '-1 Point');
      }
      _roomSendCount++;
      if (_roomSendCount == 5) {
        _pointsProv?.oneTimeBonus('first_room_chat', 5).then((earned) {
          if (earned && mounted) {
            final s = context.read<LocaleProvider>().s;
            _pointsProv?.showPointsToast(context, s.isId ? '+5 Poin — Room chat!' : '+5 Points — Room chat!');
          }
        });
      }
      _scrollToBottom();
    } finally {
      _isSending = false;
    }
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
                    itemBuilder: (_, i) => _UserChip(
                      user: users[i],
                      myUid: auth.uid,
                      color: Color(userColorPalette[colorHashForUid(users[i].uid) % userColorPalette.length]),
                    ),
                  );
                },
              ),
            ),

          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _msgsStream,
              builder: (_, snap) {
                final msgs = snap.data ?? [];
                if (msgs.isEmpty) {
                  return Center(
                    child: Builder(builder: (ctx) {
                      final s = ctx.read<LocaleProvider>().s;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('👋', style: TextStyle(fontSize: 40)),
                          const SizedBox(height: 8),
                          Text(s.msgStartConversation, style: const TextStyle(color: AppTheme.textSecondary)),
                        ],
                      );
                    }),
                  );
                }
                if (msgs.length > _lastMsgCount && _isNearBottom) {
                  _lastMsgCount = msgs.length;
                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                } else {
                  _lastMsgCount = msgs.length;
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[msgs.length - 1 - i];
                    return _MessageBubble(
                      key: ValueKey(m.id),
                      msg: m,
                      isMe: m.senderId == auth.uid,
                      color: Color(userColorPalette[colorHashForUid(m.senderId) % userColorPalette.length]),
                      onTapUser: () => _onTapUser(m, auth),
                    );
                  },
                );
              },
            ),
          ),

          _ChatInput(controller: _msgCtrl, onSend: _send),
        ],
      ),
    );
  }

  void _onTapUser(MessageModel msg, AuthProvider auth) {
    if (msg.senderId == auth.uid) return;
    if (_sheetOpen) return;
    if (context.read<ChatProvider>().isBlocked(msg.senderId)) {
      final s = context.read<LocaleProvider>().s;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.msgBlocked)),
      );
      return;
    }
    _sheetOpen = true;
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
                    backgroundColor: Color(userColorPalette[colorHashForUid(msg.senderId) % userColorPalette.length]),
                    child: Text(msg.senderName.isNotEmpty ? msg.senderName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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
                      MaterialPageRoute(builder: (_) => PrivateChatScreen(chatId: chatId, otherName: msg.senderName, otherUid: msg.senderId, otherGender: msg.senderGender, otherCountry: '', otherRegistered: msg.isRegistered)),
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
              leading: const Icon(Icons.block, color: AppTheme.danger),
              title: Text(s.btnBlock, style: const TextStyle(color: AppTheme.danger)),
              onTap: () async {
                Navigator.of(context).pop();
                await context.read<ChatProvider>().blockUser(auth.uid!, msg.senderId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(s.blockSuccess)),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag, color: Colors.orange),
              title: Text(s.btnReport, style: const TextStyle(color: Colors.orange)),
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
        title: Text('${s.btnReport} $reportedName', style: const TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(hintText: s.reportHint),
          onChanged: (v) => reason = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(context.read<LocaleProvider>().s.btnCancel)),
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
      padding: const EdgeInsets.only(right: 8),
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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              if (user.isRegistered)
                const Positioned(
                  right: -2, bottom: -2,
                  child: Icon(Icons.verified, size: 14, color: Color(0xFF4A90E2)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isMe ? s.labelYou : user.nickname,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
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
  final VoidCallback onTapUser;
  const _MessageBubble({super.key, required this.msg, required this.isMe, required this.color, required this.onTapUser});

  static const _myColor = Color(0xFFD5F5E3);
  static const _theirColor = Color(0xFFFFFFFF);
  static const _textColor = Color(0xFF303030);

  @override
  Widget build(BuildContext context) {
    final timeStr = formatTime(msg.timestamp);

    // Pesan sendiri: hijau, rata kanan, tanpa avatar
    if (isMe) {
      return Padding(
        padding: const EdgeInsets.only(left: 60, bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: _myColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: MessageTextWithTime(
                text: msg.text,
                timeStr: timeStr,
                textStyle: const TextStyle(color: _textColor, fontSize: 14.5, height: 1.2, letterSpacing: -0.4),
                timeStyle: TextStyle(color: _textColor.withValues(alpha: 0.45), fontSize: 10.5),
                alignRight: true,
              ),
            ),
          ],
        ),
      );
    }

    // Pesan user lain: avatar + nama warna + bubble putih, rata kiri
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTapUser,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: color,
              child: Text(
                msg.senderName.isNotEmpty ? msg.senderName[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 8),
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
                        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      if (msg.isRegistered) ...[
                        const SizedBox(width: 3),
                        const Icon(Icons.verified, size: 13, color: Color(0xFF4A90E2)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: _theirColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                      bottomLeft: Radius.circular(2),
                      bottomRight: Radius.circular(8),
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
                            border: const Border(left: BorderSide(color: AppTheme.primary, width: 3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                msg.repliedToSenderName ?? '',
                                style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                msg.repliedToText ?? '',
                                style: TextStyle(color: _textColor.withValues(alpha: 0.6), fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      MessageTextWithTime(
                        text: msg.text,
                        timeStr: timeStr,
                        textStyle: const TextStyle(color: _textColor, fontSize: 14.5, height: 1.2, letterSpacing: -0.4),
                        timeStyle: TextStyle(color: _textColor.withValues(alpha: 0.45), fontSize: 10.5),
                        alignRight: false,
                      ),
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
  const _ChatInput({required this.controller, required this.onSend});

  @override
  State<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<_ChatInput> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppTheme.bgScreen,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, -1)),
        ],
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                onPressed: () => EmojiPickerSheet.show(context, widget.controller),
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
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
                        onSubmitted: (_) => widget.onSend(),
                        minLines: 1,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 2),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => SizeTransition(
                sizeFactor: anim,
                axis: Axis.horizontal,
                axisAlignment: -1,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: widget.controller.text.trim().isEmpty
                  ? const SizedBox(width: 0, key: ValueKey('empty'))
                  : SizedBox(
                      key: const ValueKey('send'),
                      width: 48,
                      height: 48,
                      child: IconButton(
                        onPressed: widget.onSend,
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
          ],
        ),
      ),
    );
  }
}
