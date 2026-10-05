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
import '../widgets/chat_info_snack.dart';
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
  Future<bool> chatUndeleteMessage(String id);
  String chatDeletedLabel(S s);
  Map<String, String> get chatReactionKnownNames;

  /// YukCoin v2 (opsional). Implementor boleh override:
  /// - [chatYukcoinV2Active] true bila fitur berbayar v2 aktif.
  /// - [chatChargeYukcoin] potong YukCoin; return true bila berhasil.
  /// - [chatUndoMessage] jalankan undo berbayar; return {ok?}.
  /// Default: fitur v2 nonaktif, edit/undo bebas (perilaku lama).
  bool get chatYukcoinV2Active => false;
  Future<bool> chatChargeYukcoin(String feature, int cost, String ref) async =>
      true;
  Future<Map<String, dynamic>> chatUndoMessage(String id) async => {};

  /// Biaya default (dari server; angka ini hanya untuk dialog konfirmasi).
  int get chatCostUndoMessage => 10;
  int get chatCostEditMessage => 15;


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
    // Anti-lempar: remove() pada overlay yang overlay-nya sudah unmount
    // (mis. rute di-pop paksa) melempar dan merusak dispose/navigator.
    try {
      actionBar?.remove();
    } catch (_) {}
    actionBar = null;
  }

  /// Dipanggil dari `dispose()` screen pemakai mixin — pastikan overlay
  /// seleksi TIDAK tersisa (penghalang transparan full-screen yang bikin
  /// tap/back tertelan). Defensif: aman dipanggil berulang.
  void disposeSelectionLayer() => hideActionBar();

  void clearSelection() {
    hideActionBar();
    if (selectedIds.isEmpty) return;
    // Bisa dipanggil setelah unmount (callback async) — jangan setState.
    if (!mounted) {
      selectedIds.clear();
      selectedMsgs.clear();
      return;
    }
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
    final entry = OverlayEntry(
      builder: (overlayCtx) => Stack(
        children: [
          // Layer penutup tap-di-luar JANGAN menutupi AppBar: tap ikon
          // AppBar seleksi (reply/edit/...) yang mendarat di layer ini MATI
          // (terbukti di test: onPressed tak pernah jalan) → user harus tap
          // dua kali (tap pertama cuma menutup layer). Mulai di bawah zona
          // AppBar (status bar + toolbar standar 56).
          Positioned(
            top: MediaQuery.of(overlayCtx).padding.top + kToolbarHeight,
            left: 0,
            right: 0,
            bottom: 0,
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
    actionBar = entry;
    // Overlay bisa sudah di-unmount (rute di-pop paksa) → insert melempar.
    // Bungkus supaya exception TIDAK merusak dispose/dispatcher navigator
    // (gejala "back mati"). Bila gagal, bersihkan state agar tidak yatim.
    try {
      Overlay.of(context).insert(entry);
    } catch (_) {
      try {
        entry.remove();
      } catch (_) {}
      actionBar = null;
    }
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
    if (!mounted) {
      clearSelection();
      return;
    }
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
      showChatSnack(context, s.msgReactionFailed);
    }
    clearSelection();
  }

  Future<void> starSelected() async {
    if (selectedIds.isEmpty) return;
    var res = ToggleResult.removed;
    var anyChanged = false;
    for (final id in selectedIds) {
      res = await MessageReactionService.instance.toggleStar(
        chatType: chatKind,
        chatId: chatId,
        messageId: id,
      );
      if (!mounted) return;
      // Update optimistis data saja — JANGAN setState per id (dulu N setState
      // beruntun = N rebuild layar penuh untuk satu aksi bintang). Rebuild
      // sekali di akhir loop (di bawah).
      if (res == ToggleResult.added) {
        starredIds.add(id);
      } else {
        starredIds.remove(id);
      }
      anyChanged = true;
      if (res == ToggleResult.failed) break;
    }
    if (!mounted) return;
    if (anyChanged) setState(() {});
    final s = context.read<LocaleProvider>().s;
    showChatSnack(
      context,
      res == ToggleResult.added
          ? s.msgStarred
          : res == ToggleResult.removed
          ? s.msgUnstarred
          : s.msgStarFailed,
    );
    clearSelection();
  }

  Future<void> copySelected() async {
    final msg = singleSelected;
    if (msg == null || msg.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: msg.text));
    if (!mounted) return;
    showChatSnack(context, context.read<LocaleProvider>().s.msgMessageCopied);
    clearSelection();
  }

  /// Hapus 1-tap (tanpa dialog konfirmasi, ala reply): seleksi langsung
  /// ditutup + hapus jalan, snackbar menawarkan UNDO. Aman karena hapus =
  /// soft-delete (is_deleted) yang bisa dikembalikan.
  Future<void> deleteSelected() async {
    if (selectedIds.isEmpty) return;
    final auth = chatAuth;
    final mine = selectedMsgs.values
        .where((m) => m.senderId == auth.uid)
        .toList();
    if (mine.isEmpty) {
      clearSelection();
      return;
    }
    // Salin id LEBIH DULU (defensif): stream refetch dari hapus pertama bisa
    // membangun ulang daftar & state seleksi. Iterasi daftar id lokal ini
    // menjamin SEMUA pesan terpilih benar-benar diproses (dulu ada kasus
    // hanya 1 terhapus).
    final ids = mine.map((m) => m.id).toList();
    // Tutup seleksi DULU supaya UI langsung responsif (ikon hilang seketika).
    clearSelection();
    // Hapus PARALEL (dulu berurutan): server menerima semuanya sekaligus,
    // tidak saling menunggu round-trip.
    final results = await Future.wait(ids.map(chatDeleteMessage));
    final failCount = results.where((ok) => !ok).length;
    if (!mounted) return;
    final s = context.read<LocaleProvider>().s;
    if (failCount == 0) {
      showChatSnack(
        context,
        chatDeletedLabel(s),
        action: SnackBarAction(
          label: s.btnUndo,
          onPressed: () => unawaited(_undeleteMany(ids)),
        ),
      );
    } else {
      showChatSnack(context, s.msgDeleteFailed);
    }
  }

  /// Kembalikan pesan yang baru dihapus (aksi UNDO di snackbar).
  Future<void> _undeleteMany(List<String> ids) async {
    for (final id in ids) {
      try {
        await chatUndeleteMessage(id);
      } catch (_) {}
      if (!mounted) return;
    }
  }

  /// Undo pesan berbayar YukCoin (kirim → batalkan). Hanya saat v2 aktif.
  /// Bila v2 nonaktif, tidak ada menu undo (pakai hapus biasa).
  Future<void> undoSelected() async {
    final msg = singleSelected;
    if (msg == null) return;
    hideActionBar();
    final s = context.read<LocaleProvider>().s;
    // Konfirmasi biaya.
    final ok = await _confirmYukcoin(s, chatCostUndoMessage);
    if (ok != true || !mounted) {
      clearSelection();
      return;
    }
    final charged = await chatChargeYukcoin(
      'undo_message',
      chatCostUndoMessage,
      msg.id,
    );
    if (!mounted) return;
    if (!charged) {
      showChatSnack(context, s.yukcoinNotEnough);
      clearSelection();
      return;
    }
    await chatUndoMessage(msg.id);
    if (!mounted) return;
    showChatSnack(context, s.undoMessageDone);
    clearSelection();
  }

  /// Dialog konfirmasi pemakaian YukCoin.
  Future<bool?> _confirmYukcoin(S s, int cost) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.yukcoinUseConfirm),
        content: Text(s.yukcoinUseConfirmBody(cost)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.yukcoinCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.yukcoinConfirm),
          ),
        ],
      ),
    );
  }

  /// Edit pesan berbayar. Return false bila user batal / YukCoin kurang.
  Future<bool> _chargeEditIfNeeded(String messageId) async {
    if (!chatYukcoinV2Active) return true;
    final s = context.read<LocaleProvider>().s;
    final ok = await _confirmYukcoin(s, chatCostEditMessage);
    if (ok != true || !mounted) return false;
    final charged = await chatChargeYukcoin(
      'edit_message',
      chatCostEditMessage,
      messageId,
    );
    if (!mounted) return false;
    if (!charged) {
      showChatSnack(context, s.yukcoinNotEnough);
      return false;
    }
    return true;
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
    showChatSnack(context, context.read<LocaleProvider>().s.msgForwarded);
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

  /// Dipanggil dari menu "Edit": charge YukCoin dulu (bila v2 aktif),
  /// baru masuk mode edit. Nonaktif → langsung edit (perilaku lama).
  Future<void> editSelected() async {
    final msg = singleSelected;
    if (msg == null) return;
    clearSelection();
    if (!await _chargeEditIfNeeded(msg.id)) return;
    if (!mounted) return;
    editMessage(msg);
    // Menu popup masih beranimasi tutup (~150-250ms) saat requestFocus di
    // editMessage jalan — fokus sering tertelan sehingga keyboard tidak
    // terbuka dan user mengira tap gagal ("harus dua kali"). Tegaskan fokus
    // sekali lagi setelah animasi selesai.
    await _refocusComposer(() => editingMessage?.id == msg.id);
  }

  /// Tegaskan fokus composer setelah jeda singkat.
  ///
  /// `requestFocus` yang diminta tepat saat tap ikon seleksi sering tertelan
  /// rebuild realtime/animasi yang mendarat di jendela yang sama → keyboard
  /// tidak terbuka dan user mengira tap gagal. Penegasan ini idempoten
  /// (fokus yang sudah benar tidak berubah) dan dijaga [stillValid] supaya
  /// tidak merebut fokus bila user sudah pindah/cancel.
  Future<void> _refocusComposer(bool Function() stillValid) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    if (stillValid()) chatFocusComposer();
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
    // Sama seperti edit: fokus langsung sering tertelan rebuild di jendela
    // tap → tegaskan sekali lagi (lihat _refocusComposer).
    unawaited(_refocusComposer(() => replyingTo?.id == msg.id));
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
            } else if (v == 'edit') {
              editSelected();
            } else if (v == 'undo') {
              undoSelected();
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
            // Undo berbayar (YukCoin v2) — hanya pesan teks milik sendiri.
            if (canEdit && chatYukcoinV2Active)
              PopupMenuItem(
                value: 'undo',
                child: Text(
                  '${s.yukcoinFeatureUndo} · $chatCostUndoMessage',
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
