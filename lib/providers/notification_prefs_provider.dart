import 'package:flutter/foundation.dart';

import '../services/notification_prefs_service.dart';

/// Provider preferensi notifikasi — screen tidak import `services/`.
class NotificationPrefsProvider extends ChangeNotifier {
  NotificationPrefsProvider();

  Future<bool> isEnabled(String type) => NotificationPrefsService.isEnabled(type);
  Future<Map<String, bool>> allPrefs() => NotificationPrefsService.allPrefs();
  Future<void> setEnabled(String type, bool enabled) =>
      NotificationPrefsService.setEnabled(type, enabled);
  Future<void> setChatMuted(String chatId, bool muted) =>
      NotificationPrefsService.setChatMuted(chatId, muted);
  Future<bool> isChatMuted(String chatId) =>
      NotificationPrefsService.isChatMuted(chatId);
}
