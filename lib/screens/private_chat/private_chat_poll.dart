part of '../private_chat_screen.dart';

/// POLLING private chat (ala WhatsApp): buka sheet → bubble pending instan →
/// kirim pesan type 'poll' (definisi di kolom `poll`, teks '📊 <tanya>').
/// Dipisah ke `part` sendiri (ratchet ukuran file layar chat).
mixin _PcPollMx on _PrivateChatBase {
  // Ditangkap saat init: `ref` tak boleh dipakai di dispose.
  PollController? _pollCtl;

  @override
  void initState() {
    super.initState();
    _pollCtl = ref.read(pollProvider);
  }

  @override
  void dispose() {
    // Realtime suara hanya hidup selama chat ini terbuka.
    _pollCtl?.detachChat();
    super.dispose();
  }

  Future<void> _openPollComposer() async {
    final s = ref.read(localeProvider).s;
    final poll = await PollComposerSheet.show(context, s: s);
    if (poll == null || !mounted) return;
    await _sendPoll(poll);
  }

  Future<void> _sendPoll(ChatPoll poll) async {
    final auth = ref.read(authProvider.notifier);
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    final s = ref.read(localeProvider).s;
    if (!outboxIsOnline) {
      showChatSnack(context, s.errSendPoll);
      return;
    }
    final reply = sendReplyingTo;
    final pending = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
      isRegistered: profile.isRegistered,
      text: poll.previewText,
      type: 'poll',
      imageData: '',
      timestamp: DateTime.now(),
      repliedToId: reply?.id,
      repliedToText: reply?.text,
      repliedToSenderName: reply?.senderName,
      poll: poll,
    );
    setState(() {
      _pending.add(pending);
      sendReplyingTo = null;
    });
    outboxScrollToBottom();
    try {
      await ref.read(chatRiverpod.chatProvider.notifier).sendPrivateMessage(
        chatId: widget.chatId,
        senderId: uid,
        senderName: profile.nickname,
        senderGender: profile.gender,
        text: poll.previewText,
        type: 'poll',
        poll: poll.toJson(),
        repliedToId: reply?.id,
        repliedToText: reply?.text,
        repliedToSenderName: reply?.senderName,
      );
      photoOnSent('poll');
    } catch (_) {
      if (!mounted) return;
      setState(() => _pending.removeWhere((m) => m.id == pending.id));
      showChatSnack(context, s.errSendPoll);
    }
  }
}
