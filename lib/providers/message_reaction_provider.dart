import 'package:flutter/foundation.dart';

import '../services/message_reaction_service.dart';

/// Provider reaksi pesan — screen tidak import `services/`.
class MessageReactionProvider extends ChangeNotifier {
  final MessageReactionService service;
  MessageReactionProvider({MessageReactionService? service})
      : service = service ?? MessageReactionService.instance;

  Future<ToggleResult> toggleReaction({
    required String chatType,
    required String chatId,
    required String messageId,
    required String emoji,
  }) =>
      service.toggleReaction(
        chatType: chatType,
        chatId: chatId,
        messageId: messageId,
        emoji: emoji,
      );

  Future<bool> removeReaction({
    required String chatType,
    required String messageId,
    required String emoji,
  }) =>
      service.removeReaction(
        chatType: chatType,
        messageId: messageId,
        emoji: emoji,
      );

  Future<ToggleResult> toggleStar({
    required String chatType,
    required String chatId,
    required String messageId,
  }) =>
      service.toggleStar(
        chatType: chatType,
        chatId: chatId,
        messageId: messageId,
      );

  Future<Map<String, Map<String, int>>> loadCachedReactions(String chatId) =>
      service.loadCachedReactions(chatId);
  Future<void> saveCachedReactions(
    String chatId,
    Map<String, Map<String, int>> reactions,
  ) =>
      service.saveCachedReactions(chatId, reactions);
  Stream<Map<String, Map<String, int>>> watchReactions(String chatId) =>
      service.watchReactions(chatId);
  Stream<Set<String>> watchStarred(String chatId) =>
      service.watchStarred(chatId);
}
