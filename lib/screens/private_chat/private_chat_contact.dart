part of '../private_chat_screen.dart';

/// KIRIM KONTAK (ala WhatsApp) di private chat: pemilih kontak (ChatYuk —
/// hanya teman/pernah chat — atau buku kontak HP) → bubble pending instan →
/// pesan type 'contact' (payload di kolom `contact`, text '📇 <nama>').
///
/// Kontak ChatYuk: payload **hanya uid** → penerima resolve nama/foto sendiri.
/// Kontak HP: nama + nomor apa adanya dari buku kontak pengirim.
mixin _PcContactMx on _PrivateChatBase {
  Future<void> _openContactPicker() async {
    if (!mounted) return;
    final picked = await showContactPickerSheet(context: context);
    if (picked == null || !mounted) return;
    await _sendContact(picked);
  }

  Future<void> _sendContact(ChatContact contact) async {
    final auth = ref.read(authProvider.notifier);
    final uid = auth.uid;
    final profile = auth.profile;
    if (uid == null || profile == null) return;
    final s = ref.read(localeProvider).s;
    if (!outboxIsOnline) {
      showChatSnack(context, s.errSendContact);
      return;
    }
    final text = contact.previewText();
    final reply = sendReplyingTo;
    final pending = MessageModel(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      senderId: uid,
      senderName: profile.nickname,
      senderGender: profile.gender,
      isRegistered: profile.isRegistered,
      text: text,
      type: 'contact',
      imageData: '',
      timestamp: DateTime.now(),
      repliedToId: reply?.id,
      repliedToText: reply?.text,
      repliedToSenderName: reply?.senderName,
      repliedToMeta: sendReplyMeta(reply),
      contact: contact,
    );
    setState(() {
      _pending.add(pending);
      sendReplyingTo = null;
    });
    outboxScrollToBottom();
    try {
      await ref
          .read(chatRiverpod.chatProvider.notifier)
          .sendPrivateMessage(
            chatId: widget.chatId,
            senderId: uid,
            senderName: profile.nickname,
            senderGender: profile.gender,
            text: text,
            type: 'contact',
            contact: contact.toJson(),
            repliedToId: reply?.id,
            repliedToText: reply?.text,
            repliedToSenderName: reply?.senderName,
      repliedToMeta: sendReplyMeta(reply),
          );
      photoOnSent('contact');
    } catch (_) {
      if (!mounted) return;
      setState(() => _pending.removeWhere((m) => m.id == pending.id));
      showChatSnack(context, s.errSendContact);
    }
  }
}
