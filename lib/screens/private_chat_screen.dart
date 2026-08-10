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
import '../providers/points_provider.dart';
import '../services/chat_service.dart';
import '../services/forensic_watermark.dart';
import '../services/screen_secure_service.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../main.dart';
import '../utils.dart';
import 'user_info_screen.dart';

// Top-level function untuk compute() isolate — decode + resize + encode di background
String? _processImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
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
    // Anti-screenshot dikontrol setting admin global (ScreenSecureService).
    // Privasi view_once tetap terjaga via enterViewOnce/exitViewOnce.

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errSendPhoto}$e')));
      }
    }
  }

  Future<void> _sendViewOncePhoto() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    // Resize + embed forensic watermark (seed = UID penerima) di isolate
    final base64 =
        await compute(_processViewOnceImage, (bytes, widget.otherUid));
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
    final ppView = context.read<PointsProvider>();
    final rView = await ppView.deductBeforeSend('view_once');
    if (rView < 0) { if (mounted) { ppView.showOutOfPointsDialog(context, context.read<LocaleProvider>().s.isId); } return; }
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
      if (ppView.enabled) {
        ppView.showPointsToast(context, context.read<LocaleProvider>().s.isId ? '-3 Poin' : '-3 Points');
      }
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
                  else if (msg.type == 'view_once' || msg.type == 'view_once_expired')
                    _ViewOnceImage(
                      imageData: msg.imageData,
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

class _MessageImage extends StatefulWidget {
  final String imageData;
  const _MessageImage({required this.imageData});

  @override
  State<_MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends State<_MessageImage> {
  _DecodedImage? _decoded;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  // Decode di isolate agar UI tidak freeze untuk foto besar.
  Future<void> _decode() async {
    final decoded = await compute(_decodeImage, widget.imageData);
    if (!mounted) return;
    setState(() => _decoded = decoded);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    final decoded = _decoded;
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return Container(
        width: 200, height: 120,
        color: AppTheme.bgInput,
        alignment: Alignment.center,
        child: Text(s.msgPhotoExpired, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      );
    }
    // Ukuran proporsional: lebar maks 200, tinggi mengikuti rasio asli.
    final aspect = decoded.width / decoded.height;
    var width = 200.0;
    var height = width / aspect;
    if (height > 280) {
      height = 280;
      width = height * aspect;
    }
    return GestureDetector(
      onTap: () => _openFullscreen(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          decoded.bytes,
          width: width,
          height: height,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Container(
            width: 200, height: 120,
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
      MaterialPageRoute(builder: (_) => _PhotoViewerScreen(bytes: decoded.bytes)),
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

class _ViewOnceImage extends StatefulWidget {
  final String imageData;
  final bool isMe;
  final String? messageId;
  final bool isExpired;
  const _ViewOnceImage({
    required this.imageData,
    required this.isMe,
    this.messageId,
    this.isExpired = false,
  });

  @override
  State<_ViewOnceImage> createState() => _ViewOnceImageState();
}

class _ViewOnceImageState extends State<_ViewOnceImage> {
  _ViewOnceState _state = _ViewOnceState.idle;
  int _secondsLeft = 10;
  Timer? _timer;
  _DecodedImage? _decoded;
  final ValueNotifier<int> _countdown = ValueNotifier<int>(10);
  bool _viewerOpen = false;

  @override
  void initState() {
    super.initState();
    // Sudah expired di server (type view_once_expired) — jangan tampilkan tombol lihat.
    if (widget.isExpired) {
      _state = _ViewOnceState.expired;
    }
    _decode();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdown.dispose();
    if (_state == _ViewOnceState.viewing) {
      ScreenSecureService.exitViewOnce();
    }
    super.dispose();
  }

  // Decode di isolate agar UI tidak freeze untuk foto besar.
  Future<void> _decode() async {
    if (widget.imageData.isEmpty) return;
    final decoded = await compute(_decodeImage, widget.imageData);
    if (!mounted) return;
    setState(() => _decoded = decoded);
  }

  void _startViewing() {
    if (_state != _ViewOnceState.idle) return;
    setState(() {
      _state = _ViewOnceState.viewing;
      _secondsLeft = 10;
    });
    ScreenSecureService.enterViewOnce();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { _secondsLeft--; });
      _countdown.value = _secondsLeft;
      if (_secondsLeft <= 0) {
        t.cancel();
        ScreenSecureService.exitViewOnce();
        setState(() => _state = _ViewOnceState.expired);
        if (_viewerOpen) Navigator.of(context).maybePop();
        _clearFromServer();
      }
    });
  }

  // Buka foto fullscreen; timer tetap berjalan (State ini tetap mounted di bawah route).
  void _openViewer() {
    final decoded = _decoded;
    if (decoded == null || _state != _ViewOnceState.viewing || !mounted) return;
    _viewerOpen = true;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => _PhotoViewerScreen(
            bytes: decoded.bytes,
            countdown: _countdown,
          ),
        ))
        .whenComplete(() => _viewerOpen = false);
  }

  // Hapus foto dari DB agar tidak bisa dilihat lagi setelah keluar-masuk chat.
  Future<void> _clearFromServer() async {
    final id = widget.messageId;
    if (id == null || id.startsWith('pending-')) return;
    try {
      await context.read<ChatProvider>().clearViewOnceImage(id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;

    // Pengirim lihat foto asli + badge
    if (widget.isMe) {
      final decoded = _decoded;
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: decoded != null
                ? Image.memory(
                    decoded.bytes,
                    width: _viewWidth(decoded),
                    height: _viewHeight(decoded),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.high,
                  )
                : Container(width: 200, height: 120, color: AppTheme.bgInput),
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
      );
    }

    // Penerima — idle: kartu modern "tekan untuk melihat"
    if (_state == _ViewOnceState.idle) {
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

    // Expired — blur penuh + kartu terkunci modern
    if (_state == _ViewOnceState.expired) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            _decoded != null
                ? ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Image.memory(
                      _decoded!.bytes,
                      width: _viewWidth(_decoded!),
                      height: _viewHeight(_decoded!),
                      fit: BoxFit.cover,
                    ),
                  )
                : Container(
                    width: 200,
                    height: 120,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF37474F), Color(0xFF263238)],
                      ),
                    ),
                  ),
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
      );
    }

    // Viewing — tampilkan foto proporsional + countdown; tap untuk memperbesar
    final decoded = _decoded;
    return GestureDetector(
      onTap: _openViewer,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: decoded != null
                ? Image.memory(
                    decoded.bytes,
                    width: _viewWidth(decoded),
                    height: _viewHeight(decoded),
                    fit: BoxFit.cover,
                    gaplessPlayback: true)
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
      ),
    );
  }

  // Lebar/t tinggi tampilan proporsional (maks 200×280) sesuai rasio asli.
  static double _viewWidth(_DecodedImage d) {
    final aspect = d.width / d.height;
    if (aspect >= 1) return 200;
    return 200 * aspect;
  }

  static double _viewHeight(_DecodedImage d) {
    final aspect = d.width / d.height;
    if (aspect <= 1) return 200;
    return 200 / aspect;
  }
}

// ── Photo Viewer Fullscreen ─────────────────────────────────────────────────
// Menampilkan foto fullscreen (hitam) dengan zoom + close. Untuk view-once,
// countdown diteruskan dari state pemilik sehingga timer terus berjalan.
class _PhotoViewerScreen extends StatefulWidget {
  final Uint8List bytes;
  final ValueNotifier<int>? countdown;
  const _PhotoViewerScreen({required this.bytes, this.countdown});

  @override
  State<_PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<_PhotoViewerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.memory(widget.bytes, fit: BoxFit.contain),
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
