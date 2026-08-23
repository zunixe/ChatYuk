import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Notifikasi "panggilan aktif" berbasis FOREGROUND SERVICE (gaya WhatsApp):
/// - Proses app tidak dibunuh OS saat app di-swipe dari recents → WebRTC
///   tetap hidup dan panggilan lanjut berjalan.
/// - Notifikasi permanen dengan ikon tampil di status bar.
/// - Tap notifikasi → Android membuka kembali activity → Flutter memulihkan
///   widget tree yang sama (chat + overlay call masih ada).
class CallNotification {
  static bool _inited = false;

  static Future<void> _ensureInit() async {
    if (_inited) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'call_active',
        channelName: 'ChatYuk Calls',
        channelDescription: 'Ongoing call notification',
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
      ),
    );
    _inited = true;
  }

  static Future<void> showActive({
    required String body,
    required String channelName,
    required String channelDesc,
    required String chatId,
    required String otherUid,
    required String otherName,
  }) async {
    await _ensureInit();
    await FlutterForegroundTask.startService(
      notificationTitle: 'ChatYuk',
      notificationText: body,
    );
  }

  static Future<void> cancel() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}
