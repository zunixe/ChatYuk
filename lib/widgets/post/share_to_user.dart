import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user_model.dart';
import '../../providers/riverpod/auth_provider.dart';
import '../../providers/riverpod/chat_provider.dart';
import '../../utils.dart';

Future<bool> sendShareToUser(
  BuildContext context,
  UserModel user,
  String content,
) async {
  final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
  final chat = ProviderScope.containerOf(context, listen: false).read(chatProvider.notifier);
  final myUid = auth.uid ?? '';
  if (myUid.isEmpty || user.uid.isEmpty) return false;
  try {
    final myName = auth.profile?.nickname ?? '';
    final chatId = await chat.startPrivateChat(
      myUid: myUid,
      otherUid: user.uid,
      myName: myName,
      otherName: user.nickname,
      myGender: auth.profile?.gender ?? '',
      otherGender: user.gender,
    );
    if (chatId.isEmpty) return false;
    final msgId = await chat.sendPrivateMessage(
      chatId: chatId,
      senderId: myUid,
      senderName: myName,
      senderGender: auth.profile?.gender ?? '',
      text: content,
    );
    return msgId != null;
  } catch (e) {
    dlog('[PostCard] share ke user error: $e');
    return false;
  }
}
