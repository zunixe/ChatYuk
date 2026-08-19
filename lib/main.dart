import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as lpn;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'models/room_model.dart';
import 'providers/auth_provider.dart';
import 'providers/call_provider.dart';
import 'providers/locale_provider.dart';
import 'screens/incoming_call_screen.dart';
import 'screens/private_chat_screen.dart';
import 'screens/room_chat_screen.dart';
import 'config/supabase_config.dart';
import 'utils.dart';
import 'services/message_cache.dart';
import 'services/photo_cache.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final LocaleProvider localeProvider = LocaleProvider();

final ValueNotifier<String?> activeChatId = ValueNotifier(null);

final lpn.FlutterLocalNotificationsPlugin localNotifications =
    lpn.FlutterLocalNotificationsPlugin();

const String _channelId = 'chatyuk_chat';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final data = message.data;
  final type = data['type'];
  final isDataOnly = type == 'online' || type == 'follow' || type == 'friend_request' || type == 'subscribe' || type == 'call';
  final title = isDataOnly
      ? data['otherName'] ?? data['fromName'] ?? 'User'
      : message.notification?.title ??
          (type == 'room' ? data['roomName'] ?? 'Room' : 'New message');
  final body = isDataOnly
      ? (type == 'call'
          ? 'is calling you'
          : type == 'online'
              ? 'is online'
              : type == 'follow'
                  ? 'started following you'
                  : type == 'friend_request'
                      ? 'sent you a friend request'
                      : 'subscribed to you')
      : message.notification?.body ?? 'You have a new message';

  final androidInit = const lpn.AndroidInitializationSettings('@mipmap/ic_launcher');
  final settings = lpn.InitializationSettings(android: androidInit);
  final plugin = lpn.FlutterLocalNotificationsPlugin();
  await plugin.initialize(settings: settings);

  await plugin.show(
    id: notifIdForKey(data['chatId'] ?? data['roomId'] ?? data['callId'] ?? 'bg'),
    title: title,
    body: body,
    notificationDetails: lpn.NotificationDetails(
      android: lpn.AndroidNotificationDetails(
        _channelId,
        'Chat Notifications',
        channelDescription: 'New message notifications from chat',
        importance: lpn.Importance.high,
        priority: lpn.Priority.high,
      ),
    ),
    payload: jsonEncode(data),
  );
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  final data = message.data;
  final chatKey = data['chatId'] ?? data['roomId'] ?? '';
  if (chatKey.isNotEmpty && activeChatId.value == chatKey) return;

  final s = localeProvider.s;
  final type = data['type'];
  final isDataOnly = type == 'online' || type == 'follow' || type == 'friend_request' || type == 'subscribe' || type == 'call';
  final isOnline = type == 'online';
  final title = isDataOnly
      ? data['otherName'] ?? data['fromName'] ?? s.unknownUser
      : message.notification?.title ??
          (type == 'room' ? data['roomName'] ?? 'Room' : s.notifNewMessage);
  final body = isDataOnly
      ? (type == 'call'
          ? s.notifCallingBody
          : isOnline
              ? s.notifOnlineBody
              : type == 'follow'
                  ? s.notifFollowBody
                  : type == 'friend_request'
                      ? s.notifFriendRequestBody
                      : s.notifSubscribeBody)
      : message.notification?.body ?? s.notifNewMessageBody;

  await localNotifications.show(
    id: notifIdForKey(data['chatId'] ?? data['roomId'] ?? data['callId'] ?? 'local'),
    title: title,
    body: body,
    notificationDetails: lpn.NotificationDetails(
      android: lpn.AndroidNotificationDetails(
        _channelId,
        s.notifChannelName,
        channelDescription: s.notifChannelDesc,
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
  final s = localeProvider.s;
  // Panggilan masuk → buka IncomingCallScreen (tanpa reset stack, dan
  // dedupe kalau layar panggilan yang sama sudah terbuka).
  if (data['type'] == 'call') {
    final callId = data['callId'] ?? '';
    if (callId.isNotEmpty && CallProvider.instance.activeCallId != callId) {
      nav.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => IncomingCallScreen(
            callId: callId,
            callerUid: data['callerUid'] ?? '',
            callType: data['callType'] ?? 'video',
          ),
        ),
      );
    }
    return;
  }
  nav.pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => data['type'] == 'room'
          ? RoomChatScreen(
              room: RoomModel(
                id: data['roomId'] ?? '',
                name: data['roomName'] ?? 'Room',
                description: '',
                icon: '💬',
                country: '',
                category: data['roomId'] ?? '',
                order: 0,
              ),
            )
          : PrivateChatScreen(
              chatId: data['chatId'] ?? '',
              otherName: data['otherName'] ?? s.unknownUser,
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
  await localeProvider.init();

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

  final settingsNow = await messaging.getNotificationSettings();
  if (settingsNow.authorizationStatus != AuthorizationStatus.authorized) {
    final perm = await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (perm.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('FCM permission denied');
    }
  }

  String? token;
  try {
    token = await messaging.getToken().timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('FCM getToken failed: $e');
  }
  if (token != null) {
    debugPrint('FCM token: ${token.substring(0, 20)}...');
  }

  FirebaseMessaging.onMessage.listen(_showLocalNotification);
  FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);

  final initial = await messaging.getInitialMessage();
  if (initial != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _openFromMessage(initial));
  }

  // Deep link handler (chatyuk://)
  _initDeepLinks();
}

// Handle deep links: chatyuk://login-callback?token=...&type=recovery
void _initDeepLinks() {
  final appLinks = AppLinks();

  // Link saat app sudah berjalan di foreground
  appLinks.uriLinkStream.listen((uri) {
    if (kDebugMode) debugPrint('[DEEPLINK] incoming: $uri');
    _handleDeepLink(uri);
  }, onError: (e) {
    if (kDebugMode) debugPrint('[DEEPLINK] stream error: $e');
  });

  // Link saat app dibuka dari cold start via deep link
  appLinks.getInitialLink().then((uri) {
    if (uri != null) {
      if (kDebugMode) debugPrint('[DEEPLINK] initial: $uri');
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleDeepLink(uri));
    }
  }).catchError((e) {
    if (kDebugMode) debugPrint('[DEEPLINK] getInitialLink error: $e');
  });
}

Future<void> _setRecoverySession(String accessToken, String refreshToken) async {
  try {
    await Supabase.instance.client.auth.setSession(
      refreshToken,
      accessToken: accessToken,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('[DEEPLINK] setSession error: $e');
  }
}

void _handleDeepLink(Uri uri) {
  if (uri.scheme != 'chatyuk') return;

    // chatyuk://referral?u=<uid> — referrer tracking (share link).
    if (uri.host == 'referral') {
      final referrer = uri.queryParameters['u'];
      if (referrer != null && referrer.isNotEmpty) {
        // Update AuthProvider in-memory supaya referral juga ter-ikat saat
        // app sudah berjalan (bukan cuma cold start). Kalau AuthProvider
        // belum tersedia (loading), fallback ke prefs (dibaca saat konstruktor).
        try {
          final ctx = navigatorKey.currentContext;
          if (ctx != null) {
            Provider.of<AuthProvider>(ctx, listen: false).setPendingReferrer(referrer);
          } else {
            SharedPreferences.getInstance()
                .then((p) => p.setString('pending_referrer_uid', referrer));
          }
        } catch (_) {
          SharedPreferences.getInstance()
              .then((p) => p.setString('pending_referrer_uid', referrer));
        }
      }
    }

    // chatyuk://login-callback — Supabase password recovery / email confirm
    if (uri.host == 'login-callback') {
      final type = uri.queryParameters['type'];
      if (kDebugMode) debugPrint('[DEEPLINK] login-callback type=$type');
      // Supabase SDK menangani session via onAuthStateChange — tidak perlu
      // extract token manual di sini. Navigator ke ResetPasswordScreen dipicu
      // oleh passwordRecovery event di _AuthGate (app.dart).
      // Untuk email confirmation, SDK langsung update session.
      //
      // Jika ada fragment (#access_token=...), parse manual:
      final fragment = uri.fragment;
      if (fragment.isNotEmpty) {
        final params = Uri.splitQueryString(fragment);
        final accessToken = params['access_token'];
        final refreshToken = params['refresh_token'];
        final linkType = params['type'];
        if (accessToken != null && refreshToken != null) {
          if (kDebugMode) debugPrint('[DEEPLINK] setting session type=$linkType');
          // Set session recovery MANUAL. Deep link custom scheme (chatyuk://)
          // tidak selalu memicu session otomatis di SDK — tanpa session,
          // updateUser (set password baru) akan gagal.
          // Navigasi ke ResetPasswordScreen ditangani _AuthGate via event
          // passwordRecovery (app.dart) — JANGAN push manual di sini,
          // agar tidak double navigation (error "_dependents.isEmpty").
          _setRecoverySession(accessToken, refreshToken);
        }
      }
    }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    debugPrint('[FLUTTER-ERROR] ${details.exception}');
    debugPrint('[FLUTTER-ERROR] ${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PLATFORM-ERROR] $error\n$stack');
    return true;
  };
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }
  await SupabaseConfig.init();
  await MessageCache.instance.clearAllLegacy(); // bersihkan semua cache lama
  PhotoCache.instance.cleanOldPhotos(); // fire-and-forget, hapus foto >7 hari
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await _initNotifications();
  runApp(const ChatYukApp());
}
