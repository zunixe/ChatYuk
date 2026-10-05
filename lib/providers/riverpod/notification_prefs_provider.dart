import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/notification_prefs_service.dart';

/// Preferensi notifikasi (Riverpod) — action-only (pembungkus static service),
/// tanpa state reaktif. Migrasi dari ChangeNotifier (yang tak pernah notify).
class NotificationPrefsNotifier {
  const NotificationPrefsNotifier();

  Future<bool> isEnabled(String type) => NotificationPrefsService.isEnabled(type);
  Future<Map<String, bool>> allPrefs() => NotificationPrefsService.allPrefs();
  Future<void> setEnabled(String type, bool enabled) =>
      NotificationPrefsService.setEnabled(type, enabled);
  Future<void> setChatMuted(String chatId, bool muted) =>
      NotificationPrefsService.setChatMuted(chatId, muted);
  Future<bool> isChatMuted(String chatId) =>
      NotificationPrefsService.isChatMuted(chatId);
}

final notificationPrefsProvider =
    Provider<NotificationPrefsNotifier>((_) => const NotificationPrefsNotifier());
