import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../config/strings.dart';
import '../models/message_model.dart';
import '../models/room_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../services/message_reaction_service.dart';
import '../widgets/forward_picker_sheet.dart';
import '../widgets/message_reaction_bar.dart';
import '../widgets/reaction_detail_sheet.dart';

/// Modul BERSAMA seleksi pesan + reaksi/bintang/forward/hapus/edit (private ↔ room).
///
/// Dulu ~15 method ini disalin di `private_chat_screen` dan `room_chat_screen`
/// dan mulai divergen (room kehilangan dialog konfirmasi hapus). Sekarang satu
/// implementasi; perilaku mengikuti `private_chat_screen` (paling baru) dan
/// room menyesuaikan.
///
/// Kontrak implementor:
/// - [chatKind]        'private' / 'room' (dipakai API reaksi)
/// - [chatId]          id chat/room
/// - [chatAuth]        AuthProvider aktif
/// - [chatProvider]    ChatProvider untuk hapus/forward
/// - [chatMsgCtrl]     controller composer (edit pesan)
/// - [chatFocusComposer] fokuskan composer setelah edit/balas
/// - [chatScrollToBottom] scroll ke bawah setelah set reply
/// - [chatDeleteMessage] hapus 1 pesan (private/room)
/// - [chatDeletedLabel]  teks snackbar setelah hapus
/// - [chatReactionKnownNames] nama lawan untuk sheet detail reaksi
mixin ChatSelectionMixin<T extends StatefulWidget> on State<T> {
  String get chatKind;
  String get chatId;
  AuthProvider get chatAuth;
  ChatProvider get chatProvider;
  TextEditingController get chatMsgCtrl;
  void chatFocusComposer();
  void chatScrollToBottom();
  Future<bool> chatDeleteMessage(String id);
  String chatDeletedLabel(S s);
  Map<String, String> get chatReactionKnownNames;

  final Set<String> selectedIds = {};
  final Map<String, MessageModel> selectedMsgs = {};
  Map<String, Map<String, int>> reactions = {};
  Set<String> starredIds = {};

  // LayerLink per pesan — anchor action bar tepat di atas bubble.
  final Map<String, LayerLink> msgLinks = {};
  OverlayEntry? actionBar;

  MessageModel? editingMessage;
  MessageModel? replyingTo;

  bool get inSelection => selectedIds.isNotEmpty;
  MessageModel? get singleSelected =>
      selectedIds.length == 1 ? selectedMsgs[selectedIds.first] : null;

  LayerLink linkFor(String id) {
    if (msgLinks.length > 500 && !msgLinks.containsKey(id)) {
      msgLinks.remove(msgLinks.keys.first);
    }
    return msgLinks.putIfAbsent(id, () => LayerLink());
  }

  void hideActionBar() {
    actionBar?.remove();
    actionBar = null;
  }

  void clearSelection() {
    hideActionBar();
    if (selectedIds.isEmpty) return;
    setState(() {
      selectedIds.clear();
      selectedMsgs.clear();
    });
  }

  void toggleSelect(MessageModel msg) {
    if (msg.isDeleted || msg.id.startsWith('pending-')) return;
    setState(() {
      if (selectedIds.contains(msg.id)) {
        selectedIds.remove(msg.id);
        selectedMsgs.remove(msg.id);
      } else {
        selectedIds.add(msg.id);
        selectedMsgs[msg.id] = msg;
      }
    });
    refreshReactionBar(msg);
  }

  /// Tahan pesan ala WA: header jadi toolbar seleksi + bar emoji mengambang
  /// di atas bubble. Tap bubble lain = tambah seleksi (multi).
  void onMessageLongPress(
    LongPressStartDetails details,
    MessageModel msg,
    LayerLink link,
  ) {
    if (msg.isDeleted || msg.id.startsWith('pending-')) return;
    if (selectedIds.contains(msg.id)) return;
    setState(() {
      selectedIds.add(msg.id);
      selectedMsgs[msg.id] = msg;
    });
    refreshReactionBar(msg);
  }

  void refreshReactionBar(MessageModel anchor) {
    hideActionBar();
    // Multi-seleksi: hanya toolbar atas, tanpa bar emoji (sama seperti WA).
    if (selectedIds.length != 1) return;
    final link = linkFor(anchor.id);
    actionBar = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: hideActionBar,
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            offset: const Offset(0, -10),
            child: ReactionBar(
              onReact: (emoji) => reactToSelected(emoji),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(actionBar!);
  }

  Future<void> reactToSelected(String emoji) async {
    final msg = singleSelected;
    hideActionBar();
    if (msg == null) return;
    final res = await MessageReactionService.instance.toggleReaction(
      chatType: chatKind,
      chatId: chatId,
      messageId: msg.id,
      emoji: emoji,
    );
    if (!mounted) return;
    // Update optimistis: UI langsung benar tanpa menunggu realtime.
    setState(() {
      final per = reactions.putIfAbsent(msg.id, () => {});
      if (res == ToggleResult.added) {
        per[emoji] = (per[emoji] ?? 0) + 1;
      } else {
        final n = (per[emoji] ?? 1) - 1;
        if (n <= 0) {
          per.remove(emoji);
        } else {
          per[emoji] = n;
        }
        if (per.isEmpty) reactions.remove(msg.id);
      }
    });
    if (res == ToggleResult.failed && mounted) {
      final s = context.read<LocaleProvider>().s;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.msgReactionFailed)),
      );
    }
    clearSelection();
  }

  Future<void> starSelected() async {
    if (selectedIds.isEmpty) return;
    var res = ToggleResult.removed;
    for (final id in selectedIds) {
      res = await MessageReactionService.instance.toggleStar(
        chatType: chatKind,
        chatId: chatId,
        messageId: id,
      );
      if (!mounted) return;
      // Update optimistis: ikon bintang langsung benar tanpa realtime.
      setState(() {
        if (res == ToggleResult.added) {
          starredIds.add(id);
        } else {
          starredIds.remove(id);
        }
      });
      if (res == ToggleResult.failed) break;
    }
    if (!mounted) return;
    final s = context.read<LocaleProvider>().s;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res == ToggleResult.added
              ? s.msgStarred
              : res == ToggleResult.removed
              ? s.msgUnstarred
              : s.msgStarFailed,
        ),
      ),
    );
    clearSelection();
  }

  Future<void> copySelected() async {
    final msg = singleSelected;
    if (msg == null || msg.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: msg.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<LocaleProvider>().s.msgMessageCopied)),
    );
    clearSelection();
  }

  Future<void> deleteSelected() async {
    if (selectedIds.isEmpty) return;
    final s = context.read<LocaleProvider>().s;
    final auth = chatAuth;
    final mine = selectedMsgs.values
        .where((m) => m.senderId == auth.uid)
        .toList();
    if (mine.isEmpty) {
      clearSelection();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.btnDelete),
        content: Text(s.confirmDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.btnDelete, style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    for (final m in mine) {
      await chatDeleteMessage(m.id);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(chatDeletedLabel(s))),
      );
    }
    clearSelection();
  }

  Future<void> forwardSelected() async {
    if (selectedIds.isEmpty) return;
    final target = await showForwardSheet(context);
    if (target == null || !mounted) return;
    final auth = chatAuth;
    final chat = chatProvider;
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    final msgs = selectedMsgs.values.toList();
    for (final m in msgs) {
      if (m.type == 'call' || m.type == 'coin' || m.type == 'gift') continue;
      try {
        if (target.chatType == 'private') {
          await chat.sendPrivateMessage(
            chatId: target.chatId,
            senderId: uid,
            senderName: profile.nickname,
            senderGender: profile.gender,
            text: m.text,
            type: m.type == 'text' ? 'text' : m.type,
            imageData: m.imageData,
            durationMs: m.durationMs,
            isForwarded: true,
          );
        } else {
          await chat.sendRoomMessage(
            roomId: target.chatId,
            senderId: uid,
            senderName: profile.nickname,
            senderGender: profile.gender,
            text: m.text,
            type: m.type == 'text' ? 'text' : m.type,
            imageData: m.imageData,
            durationMs: m.durationMs,
            isForwarded: true,
          );
        }
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<LocaleProvider>().s.msgForwarded)),
    );
    clearSelection();
  }

  void openReactionDetail(MessageModel msg) {
    if (inSelection) return;
    final auth = chatAuth;
    showReactionDetailSheet(
      context,
      chatType: chatKind,
      messageId: msg.id,
      myUid: auth.uid ?? '',
      myName: auth.profile?.nickname ?? '',
      knownNames: chatReactionKnownNames,
    );
  }

  void editMessage(MessageModel msg) {
    setState(() {
      editingMessage = msg;
      replyingTo = null;
      chatMsgCtrl.text = msg.text;
      chatMsgCtrl.selection =
          TextSelection.collapsed(offset: chatMsgCtrl.text.length);
    });
    chatFocusComposer();
  }

  void cancelEdit() {
    setState(() {
      editingMessage = null;
      chatMsgCtrl.clear();
    });
  }

  void replyMessage(MessageModel msg) {
    setState(() {
      replyingTo = msg;
      editingMessage = null;
    });
    chatFocusComposer();
    chatScrollToBottom();
  }

  void cancelReply() => setState(() => replyingTo = null);

  PreferredSizeWidget buildSelectionAppBar() {
    final s = context.read<LocaleProvider>().s;
    final auth = chatAuth;
    final single = singleSelected;
    final allMine = selectedMsgs.values.isNotEmpty &&
        selectedMsgs.values.every((m) => m.senderId == auth.uid);
    final singleStarred = single != null && starredIds.contains(single.id);
    final canEdit = single != null &&
        single.senderId == auth.uid &&
        single.type == 'text' &&
        !single.id.startsWith('pending-');
    Widget act(IconData icon, String tip, VoidCallback fn) {
      return IconButton(
        icon: Icon(icon, size: 24, color: Colors.white),
        tooltip: tip,
        onPressed: fn,
      );
    }

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: clearSelection,
      ),
      title: Text(
        '${selectedIds.length}',
        style: AppText.titleEmphasis.copyWith(color: Colors.white),
      ),
      actions: [
        if (single != null)
          act(Icons.reply, s.menuReply, () {
            final m = single;
            clearSelection();
            replyMessage(m);
          }),
        if (single != null)
          act(
            singleStarred ? Icons.star : Icons.star_outline,
            singleStarred ? s.menuUnstar : s.menuStar,
            starSelected,
          ),
        if (allMine) act(Icons.delete_outline, s.btnDelete, deleteSelected),
        act(Icons.forward, s.menuForward, forwardSelected),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          color: AppTheme.bgCard,
          onSelected: (v) {
            if (v == 'copy') {
              copySelected();
            } else if (v == 'star') {
              starSelected();
            } else if (v == 'edit' && single != null) {
              final m = single;
              clearSelection();
              editMessage(m);
            }
          },
          itemBuilder: (_) => [
            if (single != null && single.text.isNotEmpty)
              PopupMenuItem(
                value: 'copy',
                child: Text(
                  s.menuCopy,
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
              ),
            PopupMenuItem(
              value: 'star',
              child: Text(
                singleStarred ? s.menuUnstar : s.menuStar,
                style: TextStyle(color: AppTheme.textPrimary),
              ),
            ),
            if (canEdit)
              PopupMenuItem(
                value: 'edit',
                child: Text(
                  s.editMessageTitle,
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Dipakai implementor untuk tipe RoomModel pada kontrak forward/room.
typedef RoomRef = RoomModel;
