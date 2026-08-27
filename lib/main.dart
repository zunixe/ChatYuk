import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as lpn;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'core/admin_gate.dart';
import 'app.dart';
import 'models/room_model.dart';
import 'providers/auth_provider.dart';
import 'providers/call_provider.dart';
import 'providers/locale_provider.dart';
import 'screens/incoming_call_screen.dart';
import 'screens/private_chat_screen.dart';
import 'screens/room_chat_screen.dart';
import 'config/supabase_config.dart';
import 'services/auth_service.dart';
import 'utils.dart';
import 'services/message_cache.dart';
import 'services/photo_cache.dart';
import 'services/chat_background.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final LocaleProvider localeProvider = LocaleProvider();

/// Override opsi Firebase untuk build admin (di-set oleh lib/main_admin.dart).
/// Dipakai juga oleh background isolate handler notifikasi.
FirebaseOptions? kFirebaseOptionsOverride;

final ValueNotifier<String?> activeChatId = ValueNotifier(null);

bool _firebaseReady = false;

final lpn.FlutterLocalNotificationsPlugin localNotifications =
    lpn.FlutterLocalNotificationsPlugin();

const String _channelId = 'chatyuk_chat';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: kFirebaseOptionsOverride ?? DefaultFirebaseOptions.currentPlatform,
  );
  final data = message.data;
  final type = data['type'];
  // call_canceled → panggilan dibatalkan/diputus sebelum dijawab. Batalkan
  // notifikasi call yang masih tampil (gaya panggilan berakhir).
  if (type == 'call_canceled') {
    final androidInit = const lpn.AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final settings = lpn.InitializationSettings(android: androidInit);
    final plugin = lpn.FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: settings);
    final key = data['chatId'] ?? data['callId'] ?? '';
    await plugin.cancel(id: notifIdForKey(key));
    // juga batalkan varian callId jika beda
    final alt = data['callId'] as String?;
    if (alt != null && alt.isNotEmpty && alt != key) {
      await plugin.cancel(id: notifIdForKey(alt));
    }
    return;
  }
  final isDataOnly =
      type == 'online' ||
      type == 'follow' ||
      type == 'friend_request' ||
      type == 'subscribe' ||
      type == 'call';
  final isMessage = type == 'message' ||
      (type == null && data.containsKey('chatId'));
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
      : message.notification?.body ?? (isMessage ? 'New message' : 'You have a new message');

  final androidInit = const lpn.AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  final settings = lpn.InitializationSettings(android: androidInit);
  final plugin = lpn.FlutterLocalNotificationsPlugin();
  await plugin.initialize(settings: settings);
  await _ensureAndroidChannels(plugin);

  // Panggilan masuk → notifikasi gaya telepon: suara alarm (loop channel),
  // full-screen intent, tampil di lockscreen. Channel 'chatyuk_calls' dibuat
  // sekali oleh sistem dengan suara raw/ringtone.mp3.
  final isCall = type == 'call';
  final androidDetails = isCall
      ? lpn.AndroidNotificationDetails(
          'chatyuk_calls',
          'Incoming Calls',
          channelDescription: 'Incoming call alerts with ringtone',
          importance: lpn.Importance.max,
          priority: lpn.Priority.max,
          sound: const lpn.RawResourceAndroidNotificationSound('ringtone'),
          audioAttributesUsage: lpn.AudioAttributesUsage.alarm,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          category: lpn.AndroidNotificationCategory.call,
          visibility: lpn.NotificationVisibility.public,
        )
      : lpn.AndroidNotificationDetails(
          _channelId,
          'Chat Notifications',
          channelDescription: 'New message notifications from chat',
          importance: lpn.Importance.high,
          priority: lpn.Priority.high,
        );

  await plugin.show(
    id: notifIdForKey(
      data['chatId'] ?? data['roomId'] ?? data['callId'] ?? 'bg',
    ),
    title: title,
    body: body,
    notificationDetails: lpn.NotificationDetails(android: androidDetails),
    payload: jsonEncode(data),
  );
}

/// Buat channel notifikasi Android wajib (Android 8+ butuh channel terlebih
/// dahulu — tanpa ini notifikasi lokal & FCM tidak muncul). Dipanggil dari
/// background handler DAN `_initNotifications`.
Future<void> _ensureAndroidChannels(
  lpn.FlutterLocalNotificationsPlugin plugin,
) async {
  const chat = lpn.AndroidNotificationChannel(
    'chatyuk_chat',
    'Chat Notifications',
    description: 'New message notifications from chat',
    importance: lpn.Importance.high,
  );
  const calls = lpn.AndroidNotificationChannel(
    'chatyuk_calls',
    'Incoming Calls',
    description: 'Incoming call alerts with ringtone',
    importance: lpn.Importance.max,
    playSound: true,
  );
  const active = lpn.AndroidNotificationChannel(
    'call_active',
    'ChatYuk Calls',
    description: 'Ongoing call notification',
    importance: lpn.Importance.low,
  );
  await plugin
      .resolvePlatformSpecificImplementation<
          lpn.AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(chat);
  await plugin
      .resolvePlatformSpecificImplementation<
          lpn.AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(calls);
  await plugin
      .resolvePlatformSpecificImplementation<
          lpn.AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(active);
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  final data = message.data;
  // call_canceled → batalkan notifikasi call yang masih tampil + tutup
  // IncomingCallScreen yang mungkin masih terbuka.
  if (data['type'] == 'call_canceled') {
    final key = data['chatId'] ?? data['callId'] ?? '';
    await localNotifications.cancel(id: notifIdForKey(key));
    final alt = data['callId'] as String?;
    if (alt != null && alt.isNotEmpty && alt != key) {
      await localNotifications.cancel(id: notifIdForKey(alt));
    }
    // tutup layar panggilan masuk yang masih nongol (jika ada)
    final callId = (data['callId'] ?? data['chatId']) as String?;
    if (callId != null && callId.isNotEmpty) {
      if (CallProvider.instance.activeCallId == callId) {
        CallProvider.instance.unregisterCall(callId);
      }
      final nav = navigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        // IncomingCallScreen adalah fullscreenDialog di atas stack — cukup pop sekali
        nav.pop();
      }
    }
    return;
  }
  // Panggilan masuk saat app TERBUKA ditangani Supabase Realtime
  // (IncomingCallScreen dengan ringtone sendiri) — jangan tampilkan notif.
  if (data['type'] == 'call') return;
  final chatKey = data['chatId'] ?? data['roomId'] ?? '';
  if (chatKey.isNotEmpty && activeChatId.value == chatKey) return;

  final s = localeProvider.s;
  final type = data['type'];
  final isDataOnly =
      type == 'online' ||
      type == 'follow' ||
      type == 'friend_request' ||
      type == 'subscribe' ||
      type == 'call';
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
    id: notifIdForKey(
      data['chatId'] ?? data['roomId'] ?? data['callId'] ?? 'local',
    ),
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

/// Tunggu sampai sesi Supabase dipulihkan (maks [timeout]).
/// Dipakai untuk tap notifikasi dari cold start — tanpa ini layar panggilan
/// bisa terbuka sebelum login siap dan tombol terima gagal oleh RLS.
Future<bool> _waitForSession({
  Duration timeout = const Duration(seconds: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  try {
    while (DateTime.now().isBefore(deadline)) {
      if (Supabase.instance.client.auth.currentSession != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  } catch (_) {}
  return false;
}

void _openFromData(Map<String, dynamic> data) {
  final nav = navigatorKey.currentState;
  if (nav == null || data.isEmpty) return;
  final s = localeProvider.s;
  // Panggilan aktif (tap notifikasi ongoing) → kembali ke chat yang sedang call.
  if (data['type'] == 'active_call') {
    final chatId = data['chatId'] ?? '';
    final otherUid = data['otherUid'] ?? '';
    final otherName = data['otherName'] ?? s.unknownUser;
    if (chatId.isNotEmpty) {
      final target = privateChatRoute(chatId);
      if (routeTracker.contains(target)) {
        // Chat sudah terbuka di stack → cukup angkat ke depan, jangan buat
        // instance duplikat (list kosong & kirim gagal RLS).
        nav.popUntil((r) => r.isFirst || r.settings.name == target);
      } else {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(
            settings: RouteSettings(name: target),
            builder: (_) => PrivateChatScreen(
              chatId: chatId,
              otherName: otherName,
              otherUid: otherUid,
            ),
          ),
          (route) => route.isFirst,
        );
      }
    }
    return;
  }
  // Panggilan masuk → buka IncomingCallScreen (tanpa reset stack, dan
  // dedupe kalau layar panggilan yang sama sudah terbuka).
  // Tunggu sesi login pulih dulu (cold start) supaya tombol terima tidak gagal.
  if (data['type'] == 'call') {
    final callId = data['callId'] ?? '';
    if (callId.isNotEmpty && CallProvider.instance.activeCallId != callId) {
      unawaited(
        _waitForSession().then((ready) async {
          if (!ready || navigatorKey.currentState == null) return;
          // guard: klik notif basi setelah caller sudah end → jangan buka
          // IncomingCallScreen yang langsung jadi "calling" stuck.
          try {
            final row = await Supabase.instance.client
                .from('calls')
                .select('status')
                .eq('id', callId)
                .maybeSingle();
            final st = row?['status'] as String?;
            if (st != null && st != 'ringing') {
              // batalkan notif basi
              final k = (data['chatId'] ?? callId) as String;
              await localNotifications.cancel(id: notifIdForKey(k));
              await localNotifications.cancel(id: notifIdForKey(callId));
              return;
            }
          } catch (_) {}
          if (navigatorKey.currentState == null) return;
          navigatorKey.currentState!.push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => IncomingCallScreen(
                callId: callId,
                callerUid: data['callerUid'] ?? '',
                callType: data['callType'] ?? 'video',
                chatId: data['chatId'] ?? '',
              ),
            ),
          );
        }),
      );
    }
    return;
  }
  if (data['type'] == 'call_canceled') {
    // tap pada notif call_canceled atau stale call→call_canceled push — cukup
    // batalkan notif, jangan reset navigation stack
    final key = (data['chatId'] ?? data['callId'] ?? '') as String;
    if (key.isNotEmpty) {
      localNotifications.cancel(id: notifIdForKey(key));
      final alt = data['callId'] as String?;
      if (alt != null && alt.isNotEmpty && alt != key) {
        localNotifications.cancel(id: notifIdForKey(alt));
      }
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

  final androidInit = const lpn.AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  final iosInit = const lpn.DarwinInitializationSettings();
  final settings = lpn.InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );
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
  // Android 8+: wajib buat channel sebelum show notif. Android 13+: wajib
  // dapat izin runtime POST_NOTIFICATIONS — tanpa keduanya notifikasi tidak
  // pernah muncul meski FCM terkirim.
  await _ensureAndroidChannels(localNotifications);
  if (kIsWeb == false) {
    try {
      final androidImpl = localNotifications
          .resolvePlatformSpecificImplementation<
              lpn.AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImpl?.requestNotificationsPermission();
      debugPrint('[NOTIF] POST_NOTIFICATIONS granted=$granted');
    } catch (e) {
      debugPrint('[NOTIF] requestNotificationsPermission error: $e');
    }
  }

  if (!_firebaseReady) {
    debugPrint('[FCM] dilewati, Firebase belum init');
    _initDeepLinks();
    return;
  }

  final messaging = FirebaseMessaging.instance;

  final settingsNow = await messaging.getNotificationSettings();
  if (settingsNow.authorizationStatus != AuthorizationStatus.authorized) {
    final perm = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
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
    final auth = AuthService();
    if (auth.isSignedIn) {
      unawaited(auth.updateFcmToken(token));
    } else {
      unawaited(
        _waitForSession().then((ready) {
          if (ready) unawaited(AuthService().updateFcmToken(token!));
        }),
      );
    }
  }

  // Token bisa dirotasi FCM kapan saja (umumnya setelah reinstall app).
  // Simpan otomatis ke profiles supaya push call/chat tidak ditolak
  // FCM dengan error NotRegistered (token mati di DB).
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    final auth = AuthService();
    if (auth.isSignedIn) {
      unawaited(auth.updateFcmToken(newToken));
    } else {
      unawaited(
        _waitForSession().then((ready) {
          if (ready) unawaited(AuthService().updateFcmToken(newToken));
        }),
      );
    }
  });

  FirebaseMessaging.onMessage.listen(_showLocalNotification);
  FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);

  final initial = await messaging.getInitialMessage();
  if (initial != null) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openFromMessage(initial),
    );
  }

  // Deep link handler (chatyuk://)
  _initDeepLinks();
}

// Handle deep links: chatyuk://login-callback?token=...&type=recovery
void _initDeepLinks() {
  final appLinks = AppLinks();

  // Link saat app sudah berjalan di foreground
  appLinks.uriLinkStream.listen(
    (uri) {
      if (kDebugMode) debugPrint('[DEEPLINK] incoming: $uri');
      _handleDeepLink(uri);
    },
    onError: (e) {
      if (kDebugMode) debugPrint('[DEEPLINK] stream error: $e');
    },
  );

  // Link saat app dibuka dari cold start via deep link
  appLinks
      .getInitialLink()
      .then((uri) {
        if (uri != null) {
          if (kDebugMode) debugPrint('[DEEPLINK] initial: $uri');
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _handleDeepLink(uri),
          );
        }
      })
      .catchError((e) {
        if (kDebugMode) debugPrint('[DEEPLINK] getInitialLink error: $e');
      });
}

Future<void> _setRecoverySession(
  String accessToken,
  String refreshToken,
) async {
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
          Provider.of<AuthProvider>(
            ctx,
            listen: false,
          ).setPendingReferrer(referrer);
        } else {
          SharedPreferences.getInstance().then(
            (p) => p.setString('pending_referrer_uid', referrer),
          );
        }
      } catch (_) {
        SharedPreferences.getInstance().then(
          (p) => p.setString('pending_referrer_uid', referrer),
        );
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

/// Entry BUILD RILIS (user). Flavor apkpure & play memakai target ini
/// secara DEFAULT — tidak mengandung satu pun kode admin.
/// Build admin memakai `-t lib/main_admin.dart` (JANGAN untuk rilis store).
Future<void> main() => bootstrap();

/// Bootstrap aplikasi — dipakai kedua entry (user & admin).
Future<void> bootstrap({FirebaseOptions? firebaseOptions}) async {
  WidgetsFlutterBinding.ensureInitialized();
  kFirebaseOptionsOverride = firebaseOptions;
  FlutterError.onError = (details) {
    debugPrint('[FLUTTER-ERROR] ${details.exception}');
    debugPrint('[FLUTTER-ERROR] ${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PLATFORM-ERROR] $error\n$stack');
    return true;
  };
  try {
    await Firebase.initializeApp(
      options: firebaseOptions ?? DefaultFirebaseOptions.currentPlatform,
    );
    _firebaseReady = true;
  } on UnsupportedError catch (e) {
    debugPrint('[FIREBASE] iOS belum dikonfigurasi, lewati: $e');
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      _firebaseReady = true;
    } else {
      debugPrint('[FIREBASE] init gagal: $e');
    }
  } catch (e) {
    debugPrint('[FIREBASE] init error: $e');
  }
  await SupabaseConfig.init();
  await AdminGate.postInit?.call();
  await MessageCache.instance
      .clearLegacyV1Only(); // bersihkan hanya cache format lama v1
  // Buka DB pesan (SQLite terenkripsi) + purge sisa cache prefs lama —
  // fire-and-forget supaya buka chat pertama tidak menanggung latensi ini.
  unawaited(MessageCache.instance.prewarmDb());
  PhotoCache.instance.cleanOldPhotos(); // fire-and-forget, hapus foto >7 hari
  if (_firebaseReady) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  await _initNotifications();
  await warmChatBackground();
  runApp(const ChatYukApp());
}
