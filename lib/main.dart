import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as lpn;
import 'firebase_options.dart';
import 'app.dart';
import 'models/room_model.dart';
import 'screens/private_chat_screen.dart';
import 'screens/room_chat_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Chat yang sedang dibuka di layar (null jika tidak ada).
/// Dipakai untuk menekan notifikasi saat user sedang di chat tersebut.
final ValueNotifier<String?> activeChatId = ValueNotifier(null);

final lpn.FlutterLocalNotificationsPlugin localNotifications =
    lpn.FlutterLocalNotificationsPlugin();

const String _channelId = 'chatyuk_chat';
const String _channelName = 'Notifikasi Chat';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Saat app di background/terminated, FCM menampilkan notifikasi system
  // otomatis dari payload `notification` (dikirim server).
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  final data = message.data;
  final chatKey = data['chatId'] ?? data['roomId'] ?? '';
  // Jangan tampil jika user sedang membuka chat yang sama
  if (chatKey.isNotEmpty && activeChatId.value == chatKey) return;
  final title = message.notification?.title ??
      (data['type'] == 'room' ? data['roomName'] ?? 'Room' : 'Pesan baru');
  final body = message.notification?.body ?? 'Pesan baru masuk';
  await localNotifications.show(
    id: (data['chatId'] ?? data['roomId'] ?? 'chatyuk').hashCode,
    title: title,
    body: body,
    notificationDetails: const lpn.NotificationDetails(
      android: lpn.AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Notifikasi pesan baru dari chat',
        importance: lpn.Importance.high,
        priority: lpn.Priority.high,
      ),
    ),
    payload: jsonEncode(data),
  );
}

void _openFromData(Map<String, dynamic> data) {
  final nav = navigatorKey.currentState;
  if (nav == null || data.isEmpty) return;
  nav.pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => data['type'] == 'room'
          ? RoomChatScreen(
              room: RoomModel(
                id: data['roomId'] ?? '',
                name: data['roomName'] ?? 'Room',
                description: '',
                icon: '💬',
                order: 0,
              ),
            )
          : PrivateChatScreen(
              chatId: data['chatId'] ?? '',
              otherName: data['otherName'] ?? 'Pengguna',
              otherUid: data['otherUid'] ?? '',
            ),
    ),
    (route) => route.isFirst,
  );
}

void _openFromMessage(RemoteMessage? message) {
  if (message == null) return;
  _openFromData(message.data);
}

Future<void> _initNotifications() async {
  final androidInit = const lpn.AndroidInitializationSettings('@mipmap/ic_launcher');
  final settings = lpn.InitializationSettings(android: androidInit);
  await localNotifications.initialize(
    settings: settings,
    onDidReceiveNotificationResponse: (response) {
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;
      try {
        _openFromData(jsonDecode(payload) as Map<String, dynamic>);
      } catch (_) {}
    },
  );

  final messaging = FirebaseMessaging.instance;

  // Izin notifikasi (Android 13+)
  final settingsNow = await messaging.getNotificationSettings();
  if (settingsNow.authorizationStatus != AuthorizationStatus.authorized) {
    final perm = await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (perm.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('FCM permission denied');
    }
  }

  // Token
  final token = await messaging.getToken();
  if (token != null) {
    debugPrint('FCM token: ${token.substring(0, 20)}...');
  }

  // Saat app di foreground → tampilkan notifikasi lokal
  FirebaseMessaging.onMessage.listen(_showLocalNotification);

  // Tap notifikasi saat app di background
  FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);

  // App dibuka dari notifikasi saat terminated
  final initial = await messaging.getInitialMessage();
  if (initial != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _openFromMessage(initial));
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
  await _initNotifications();
  runApp(const ChatYukApp());
}
