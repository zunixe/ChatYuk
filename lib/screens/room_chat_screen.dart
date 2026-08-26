import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/room_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../services/storage_photo_service.dart';
import '../services/forensic_watermark.dart';
import '../utils.dart';
import '../main.dart';
import '../widgets/date_chip.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/private_chat_message.dart';
import 'private_chat_screen.dart';
import 'user_info_screen.dart';
import '../providers/theme_provider.dart';

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

  late Stream<List<MessageModel>> _msgsStream;
  late Stream<List<UserModel>> _usersStream;

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
    _joinRoom();
    _startPresenceHeartbeat();
    _scrollCtrl.addListener(_onRoomScroll);
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
    if (uid == null || profile == null) {
      _isSending = false;
      return;
    }
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
      final stored = path ?? base64;
      await chat.sendRoomMessage(
        roomId: widget.room.id,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: '',
        type: 'image',
        imageData: stored,
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
      final stored = path ?? base64;
      await chat.sendRoomMessage(
        roomId: widget.room.id,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: '',
        type: 'view_once',
        imageData: stored,
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
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _HeaderToggle(
              showUsers: _showUsers,
              onTap: () => setState(() => _showUsers = !_showUsers),
            ),
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
                    padding: const EdgeInsets.all(12),
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
                    return _MessageBubble(
                      key: ValueKey(m.id),
                      msg: m,
                      isMe: m.senderId == auth.uid,
                      color: Color(
                        userColorPalette[colorHashForUid(m.senderId) %
                            userColorPalette.length],
                      ),
                      roomId: widget.room.id,
                      onTapUser: () => _onTapUser(m, auth),
                    );
                  },
                );
              },
            ),
          ),

          _ChatInput(
            controller: _msgCtrl,
            onSend: _send,
            showAttachRow: _showAttachRow,
            onToggleAttach: _toggleAttachRow,
            onSendPhoto: () {
              setState(() => _showAttachRow = false);
              _sendPhoto();
            },
            onSendViewOnce: () {
              setState(() => _showAttachRow = false);
              _sendViewOncePhoto();
            },
          ),
        ],
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
  Widget _content(
    BuildContext context,
    String timeStr, {
    required bool alignRight,
  }) {
    final chatKey = 'room_$roomId';
    if (msg.type == 'image' && msg.imageData.isNotEmpty) {
      return ClipRRect(
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
    return MessageTextWithTime(
      text: msg.text,
      timeStr: timeStr,
      textStyle: AppText.body.copyWith(color: _textColor),
      timeStyle: AppText.micro.copyWith(
        color: _textColor.withValues(alpha: 0.45),
        fontWeight: FontWeight.w400,
      ),
      alignRight: alignRight,
    );
  }

  @override
  Widget build(BuildContext context) {
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
  final VoidCallback onSendPhoto;
  final VoidCallback onSendViewOnce;
  const _ChatInput({
    required this.controller,
    required this.onSend,
    required this.showAttachRow,
    required this.onToggleAttach,
    required this.onSendPhoto,
    required this.onSendViewOnce,
  });

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
      padding: EdgeInsets.fromLTRB(8, 6, 8, 6),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    onPressed: () =>
                        EmojiPickerSheet.show(context, widget.controller),
                    icon: Icon(Icons.emoji_emotions_rounded, size: 24),
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
                    child: Row(
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
                                vertical: 12,
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
                        const SizedBox(width: 10),
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
                          width: 44,
                          height: 44,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppTheme.primaryDark,
                                  AppTheme.primary,
                                  AppTheme.accent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: IconButton(
                              onPressed: widget.onSend,
                              icon: const Icon(Icons.send_rounded, size: 20),
                              color: Colors.white,
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shape: const CircleBorder(),
                              ),
                            ),
                          ),
                        ),
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
  const _RoomInputIconBtn({
    required this.open,
    required this.onTap,
    required this.tooltip,
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
                open ? Icons.close_rounded : Icons.add_rounded,
                key: ValueKey(open),
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
