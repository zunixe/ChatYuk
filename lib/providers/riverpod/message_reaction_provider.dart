import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/message_reaction_service.dart';

/// Reaksi & bintang pesan (Riverpod) — action-only (pembungkus service),
/// tanpa state reaktif. Migrasi dari ChangeNotifier (0 notifyListeners).
class MessageReactionNotifier {
  final MessageReactionService service;
  MessageReactionNotifier([MessageReactionService? service])
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
  Future<Set<String>> loadCachedStarred(String chatId) =>
      service.loadCachedStarred(chatId);
  /// Versi SINKRON — untuk mengisi bintang sebelum frame pertama (anti-glich).
  Set<String> peekCachedStarred(String chatId) =>
      service.peekCachedStarred(chatId);
  Future<void> preloadCachedStarred(String chatId) =>
      service.preloadCachedStarred(chatId);
  Future<void> preloadAllStarred() => service.preloadAllStarred();
  Future<void> saveCachedStarred(String chatId, Set<String> ids) =>
      service.saveCachedStarred(chatId, ids);
}

final messageReactionProvider =
    Provider<MessageReactionNotifier>((_) => MessageReactionNotifier());
