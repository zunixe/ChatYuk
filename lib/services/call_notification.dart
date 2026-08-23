import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifikasi "panggilan aktif" yang tetap muncul (ongoing) saat app di-background
/// supaya user tahu masih ada call berjalan & bisa tap untuk kembali ke layar call.
/// Catatan: notifikasi ini membuat info call terlihat saat app cuma di-background
/// (tidak di-force-kill). Kalau proses app benar-benar dimatikan OS, call akan putus
/// (butuh foreground service native untuk bertahan saat force-kill).
class CallNotification {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const int _id = 991;

  static Future<void> _ensureInit() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
    } catch (_) {}
  }

  static Future<void> showActive({
    required String body,
    required String channelName,
    required String channelDesc,
  }) async {
    await _ensureInit();
    await _plugin.show(
      id: _id,
      title: 'ChatYuk',
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'call_active',
          channelName,
          channelDescription: channelDesc,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
        ),
      ),
    );
  }

  static Future<void> cancel() async {
    await _plugin.cancel(id: _id);
  }
}
