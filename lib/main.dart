import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as lpn;
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'core/admin_gate.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'core/battery_optimization_service.dart';
import 'core/media/image_cache_budget.dart';
import 'core/perf/abc_toggle.dart';
import 'core/nav_gate.dart';
import 'app.dart';
import 'models/room_model.dart';
import 'providers/riverpod/auth_provider.dart';
import 'providers/riverpod/call_provider.dart';
import 'providers/riverpod/locale_provider.dart';
import 'providers/riverpod/nav_provider.dart';
import 'providers/riverpod/update_provider.dart';
import 'screens/incoming_call_screen.dart';
import 'screens/point_history/widgets/topup_sheet.dart';
import 'screens/call_screen.dart';
import 'screens/friend_requests_screen.dart';
import 'screens/user_info_screen.dart';
import 'screens/post_detail_screen.dart';
import 'screens/private_chat_screen.dart';
import 'screens/room_chat_screen.dart';
import 'config/env.dart';
import 'config/strings.dart';
import 'config/supabase_config.dart';
import 'config/theme.dart';
import 'services/auth_service.dart';
import 'services/attribution_service.dart';
import 'services/tiktok_service.dart';
import 'services/chat_service.dart';
import 'utils.dart';
import 'core/cache/message_cache.dart';
import 'core/cache/media_disk_cache.dart';
import 'core/cache/video_file_cache.dart';
import 'core/cache/photo_cache.dart';
import 'core/cache/chat_poster_cache.dart';
import 'core/cache/photo_aspect_cache.dart';
import 'core/media/image_cache_hygiene.dart';
import 'core/cache/post_photo_cache.dart';
import 'core/media/chat_background.dart';
import 'core/media/link_preview_service.dart';
import 'core/perf/perf_probe.dart';
import 'services/meta_analytics_service.dart';
import 'services/notification_prefs_service.dart';
import 'services/storage_photo_service.dart';
import 'services/topup_service.dart';
import 'widgets/voice_bubble.dart';
import 'widgets/chat_route.dart';
import 'widgets/video_prefetch.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'main_notifications.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Container Riverpod global — untuk akses provider TANPA BuildContext
/// (mis. bootstrap `checkOnStart` update). Diisi saat runApp.
ProviderContainer? _rootContainer;

/// Override opsi Firebase untuk build admin (di-set oleh lib/main_admin.dart).
/// Dipakai juga oleh background isolate handler notifikasi.
FirebaseOptions? kFirebaseOptionsOverride;

final ValueNotifier<String?> activeChatId = ValueNotifier(null);


bool _firebaseReady = false;

final lpn.FlutterLocalNotificationsPlugin localNotifications =
    lpn.FlutterLocalNotificationsPlugin();

const String _channelId = 'chatyuk_chat';

/// Gaya WhatsApp: thread pesan per chat untuk MessagingStyle + grup +
/// ringkasan. Disimpan di memori proses (hilang saat app dibunuh — mulai
/// baru dari pesan berikutnya, sama seperti sesi notif sistem).
class _ThreadMsg {
  final String sender;
  final String text;
  final DateTime time;
  const _ThreadMsg(this.sender, this.text, this.time);
}

final _notifThreads = <String, List<_ThreadMsg>>{};
final _notifPayloads = <String, Map<String, dynamic>>{};
const String _notifGroupKey = 'chatyuk_messages';
const int _summaryNotifId = 2000000001;
const int _maxThreadMsgs = 8;
const String _pendingNotifActionsKey = 'pending_notif_actions';

/// Kunci thread + info grup dari payload FCM. Null = bukan notif chat.
({String key, String title, bool grouped, bool canReply, bool canMarkRead})?
    notifThreadOf(Map<String, dynamic> data) {
  final type = data['type'];
  if (type == 'message' || (type == null && data.containsKey('chatId'))) {
    final chatId = '${data['chatId'] ?? ''}';
    if (chatId.isEmpty) return null;
    return (
      key: chatId,
      title: '${data['otherName'] ?? ''}',
      grouped: false,
      canReply: true,
      canMarkRead: true,
    );
  }
  if (type == 'room' || type == 'mention' || type == 'room_invite') {
    final roomId = '${data['roomId'] ?? ''}';
    if (roomId.isEmpty) return null;
    return (
      key: roomId,
      title: '${data['roomName'] ?? 'Room'}',
      grouped: true,
      canReply: type != 'room_invite', // invite bukan chat → tanpa balas
      canMarkRead: false,
    );
  }
  return null;
}

lpn.MessagingStyleInformation _threadStyle(
  String title,
  List<_ThreadMsg> entries, {
  required bool grouped,
}) {
  return lpn.MessagingStyleInformation(
    lpn.Person(name: title),
    conversationTitle: grouped ? title : null,
    groupConversation: grouped,
    messages: [
      for (final e in entries)
        lpn.Message(e.text, e.time, lpn.Person(name: e.sender)),
    ],
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

/// Buka layar CallScreen fullscreen bila ada sesi call aktif & belum
/// terbuka. Dipakai: (a) tap notifikasi "panggilan aktif" (foreground
/// service tanpa payload), (b) app kembali ke foreground saat call jalan.
/// Return true bila layar call aktif/dipaksa tampil.
bool ensureCallScreenRoute(NavigatorState? navIn) {
  if (navIn == null) return false;
  final nav = navIn;
  final sess = _rootContainer!.read(callProvider.notifier).activeSession;
  if (sess == null) return false;
  if (routeTracker.contains(kCallScreenRoute)) return true;
  nav.push(
    MaterialPageRoute(
      fullscreenDialog: true,
      settings: const RouteSettings(name: kCallScreenRoute),
      builder: (_) => CallScreen(
        callId: sess.callId,
        remoteUid: sess.remoteUid,
        remoteName: sess.remoteName,
        callType: sess.callType,
        isCaller: sess.isCaller,
        session: sess,
      ),
    ),
  );
  return true;
}

void _openFromData(Map<String, dynamic> data) {
  final nav = navigatorKey.currentState;
  if (nav == null || data.isEmpty) return;
  // Buka chat dari tap notif → thread shade ikut dibersihkan (autoCancel
  // menutup notifnya; thread + ringkasan dibersihkan di sini).
  final openedKey = data['type'] == 'room' || data['type'] == 'broadcast'
      ? '${data['roomId'] ?? ''}'
      : '${data['chatId'] ?? ''}';
  if (openedKey.isNotEmpty) unawaited(_clearChatNotif(openedKey, cancelShade: false));
  final s = AppLocale.s;
  // Timeline post baru → buka langsung postingannya (detail). Tanpa postId
  // (notif lama) fallback ke tab Timeline seperti dulu.
  if (data['type'] == 'timeline_post' || data['type'] == 'timeline') {
    final postId = '${data['postId'] ?? ''}';
    if (postId.isNotEmpty) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
        (route) => route.isFirst,
      );
      return;
    }
    nav.popUntil((r) => r.isFirst);
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      try {
        ProviderScope.containerOf(ctx, listen: false).read(navProvider.notifier).goTo(2);
      } catch (_) {}
    }
    return;
  }
  // Permintaan pertemanan (tap notif) → layar daftar permintaan
  // (terima/tolak). Tanpa ini jatuh ke PrivateChatScreen kosong.
  if (data['type'] == 'friend_request') {
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const FriendRequestsScreen()),
      (route) => route.isFirst,
    );
    return;
  }
  // Panggilan aktif (tap notifikasi ongoing / buka app) → LAYAR call.
  if (data['type'] == 'active_call') {
    if (ensureCallScreenRoute(navigatorKey.currentState)) return;
    // Tidak ada sesi aktif (sudah berakhir) → fallback buka chat.
    final chatId = data['chatId'] ?? '';
    final otherUid = data['otherUid'] ?? '';
    final otherName = data['otherName'] ?? s.unknownUser;
    if (chatId.isNotEmpty) {
      final target = privateChatRoute(chatId);
      if (routeTracker.contains(target)) {
        nav.popUntil((r) => r.isFirst || r.settings.name == target);
      } else {
  // Notif "X online" tanpa chat 1:1 (teman/follower baru) → buka PROFIL-nya,
  // bukan chat kosong (chatId '').
  if (data['type'] == 'online' && '${data['chatId'] ?? ''}'.isEmpty) {
    final ouid = '${data['otherUid'] ?? ''}';
    if (ouid.isNotEmpty) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => UserInfoScreen(
            userId: ouid,
            fallbackName: '${data['otherName'] ?? s.unknownUser}',
          ),
        ),
        (route) => route.isFirst,
      );
    }
    return;
  }
  nav.pushAndRemoveUntil(
          chatRoute(
            chatId: chatId,
            otherName: otherName,
            otherUid: otherUid,
            routeName: target,
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
    if (callId.isNotEmpty && _rootContainer!.read(callProvider.notifier).activeCallId != callId) {
      // Nama pemanggil dari payload push → dipakai langsung oleh ring sistem
      // (tidak menunggu query nickname). Ring jadi muncul lebih cepat.
      _rootContainer!.read(callProvider.notifier).setPendingIncomingName(
        (data['callerName'] ?? data['otherName'] ?? '') as String,
      );
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
      builder: (_) =>
          data['type'] == 'room' ||
                  data['type'] == 'broadcast' ||
                  data['type'] == 'mention' ||
                  data['type'] == 'room_invite'
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

bool _activeChatNotifHooked = false;

Future<void> _initNotificationsFast() async {
  await AppLocale.init();
  final androidInit = const lpn.AndroidInitializationSettings('@mipmap/ic_launcher');
  final iosInit = const lpn.DarwinInitializationSettings();
  final settings = lpn.InitializationSettings(android: androidInit, iOS: iosInit);
  await localNotifications.initialize(
    settings: settings,
    onDidReceiveNotificationResponse: (response) async {
      // Aksi Balas/Tandai dibaca (foreground) — selain itu buka chat.
      if (response.actionId == 'reply' || response.actionId == 'mark_read') {
        await _handleNotifAction(response);
        return;
      }
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;
      try { _openFromData(jsonDecode(payload) as Map<String, dynamic>); } catch (_) {}
    },
    onDidReceiveBackgroundNotificationResponse: _notifActionBgHandler,
  );
  await _ensureAndroidChannels(localNotifications);
  // Buka chat di dalam app → notif shade-nya ikut hilang ala WA.
  if (!_activeChatNotifHooked) {
    _activeChatNotifHooked = true;
    activeChatId.addListener(() {
      final k = activeChatId.value;
      if (k != null && k.isNotEmpty) unawaited(_clearChatNotif(k));
    });
  }
  // Kerjakan aksi notif tertunda dari isolate background.
  unawaited(_consumePendingNotifActions());
  if (kIsWeb == false) {
    try {
      final androidImpl = localNotifications.resolvePlatformSpecificImplementation<lpn.AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImpl?.requestNotificationsPermission();
      dlog('[NOTIF] POST_NOTIFICATIONS granted=$granted');
    } catch (e) { dlog('[NOTIF] requestNotificationsPermission error: $e'); }
  }
  if (!_firebaseReady) { dlog('[FCM] dilewati, Firebase belum init'); _initDeepLinks(); return; }
  final messaging = FirebaseMessaging.instance;
  final settingsNow = await messaging.getNotificationSettings();
  if (settingsNow.authorizationStatus != AuthorizationStatus.authorized) {
    final perm = await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (perm.authorizationStatus != AuthorizationStatus.authorized) dlog('FCM permission denied');
  }
  FirebaseMessaging.onMessage.listen(
    _showLocalNotification,
    onError: (e) => dlog('FCM onMessage stream error: $e'),
  );
  FirebaseMessaging.onMessageOpenedApp.listen(
    _openFromMessage,
    onError: (e) => dlog('FCM onMessageOpened app stream error: $e'),
  );
  final initial = await messaging.getInitialMessage();
  if (initial != null) WidgetsBinding.instance.addPostFrameCallback((_) => _openFromMessage(initial));
  _initDeepLinks();
}

Future<void> _initFcmTokenLazy() async {
  if (!_firebaseReady) return;
  final messaging = FirebaseMessaging.instance;
  String? token;
  try { token = await messaging.getToken().timeout(const Duration(seconds: 5)); } catch (e) { dlog('FCM getToken failed: $e'); }
  if (token != null) {
    dlog('FCM token: ${token.substring(0, 20)}...');
    final auth = AuthService();
    if (auth.isSignedIn) unawaited(auth.updateFcmToken(token));
    else unawaited(_waitForSession().then((ready) { if (ready) unawaited(AuthService().updateFcmToken(token!)); }));
  }
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    final auth = AuthService();
    if (auth.isSignedIn) unawaited(auth.updateFcmToken(newToken));
    else unawaited(_waitForSession().then((ready) { if (ready) unawaited(AuthService().updateFcmToken(newToken)); }));
  });
}

// Handle deep links: chatyuk://login-callback?token=...&type=recovery
void _initDeepLinks() {
  final appLinks = AppLinks();

  // Link saat app sudah berjalan di foreground
  appLinks.uriLinkStream.listen(
    (uri) {
      if (kDebugMode) dlog('[DEEPLINK] incoming: $uri');
      _handleDeepLink(uri);
    },
    onError: (e) {
      if (kDebugMode) dlog('[DEEPLINK] stream error: $e');
    },
  );

  // Link saat app dibuka dari cold start via deep link
  appLinks
      .getInitialLink()
      .then((uri) {
        if (uri != null) {
          if (kDebugMode) dlog('[DEEPLINK] initial: $uri');
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _handleDeepLink(uri),
          );
        }
      })
      .catchError((e) {
        if (kDebugMode) dlog('[DEEPLINK] getInitialLink error: $e');
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
    if (kDebugMode) dlog('[DEEPLINK] setSession error: $e');
  }
}

void _handleDeepLink(Uri uri) {
  if (uri.scheme != 'chatyuk') return;

  // chatyuk://referral?u=<uid> — referrer tracking (share link).
  if (uri.host == 'referral') {
    final referrer = uri.queryParameters['u'];
    if (referrer != null && referrer.isNotEmpty) {
      // Update AuthNotifier in-memory supaya referral juga ter-ikat saat
      // app sudah berjalan (bukan cuma cold start). Kalau AuthNotifier
      // belum tersedia (loading), fallback ke prefs (dibaca saat konstruktor).
      try {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          ProviderScope.containerOf(ctx, listen: false)
              .read(authProvider.notifier)
              .setPendingReferrer(referrer);
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
    if (kDebugMode) dlog('[DEEPLINK] login-callback type=$type');
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
        if (kDebugMode) dlog('[DEEPLINK] setting session type=$linkType');
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
  // Batasi cache bitmap Flutter: default 1000 gambar/100MB terlalu longgar
  // untuk chat penuh foto — bitmap 12MP (~48MB) menumpuk di native heap
  // sampai ratusan MB (pernah 500MB → ngetik & buka halaman ngelag).
  //
  // Bubble chat & foto post SUDAH di-cap decode (ResizeImage/cacheWidth ≤1080px
  // ≈ 4.4MB/bitmap). 60 entri / 24MB: cukup untuk viewport + 1 layar di atas;
  // sisanya dibuang & di-decode ulang saat scroll (murah, dari disk cache).
  // Angka ini sengaja konservatif — prioritas "ringan" > "nol re-decode",
  // terutama di HP yang memorinya ketat (free RAM kecil → halaman ter-swap →
  // ngetik terasa freeze saat page ter-swap di-fault balik).
  // Kalau ada laporan "foto kedip saat scroll", naikkan bertahap 72/36.
  // NAIK 2026-10-11 (laporan nyata): "scroll cepat = card dulu baru foto".
  // 60/24MB → 120/40MB: saat scroll cepat, lebih banyak thumb tetap di-decode
  // cache → kartu masuk viewport langsung gambar (bukan placeholder). Tetap
  // BOUNDED (bukan unbounded) supaya memori tak membengkak; thumb post ~135KB
  // → 120 entry ≈ 16MB bitmap, aman bersama cap lain.
  // Cap ADAPTIF ke RAM device (A) — ambil RAM fisik, lalu set cap.
  // SANITY: `device_info_plus` kadang return 0 ATAU nilai tak wajar (<2GB) di
  // sebagian ROM (HyperOS: terukur "0.0GB" di HP RAM 11GB) → kalau dipakai apa
  // adanya, clamp jatuh ke cap TERKECIL (16MB). Hanya percaya nilai >= 2GB;
  // selain itu pakai fallback 4GB (→ 32MB). Aman & tidak lagi salah-rendah.
  const int kMinSaneRamBytes = 2 * 1024 * 1024 * 1024;
  int ramBytes = kImageCacheFallbackRamBytes;
  try {
    if (Platform.isAndroid) {
      final v = (await DeviceInfoPlugin().androidInfo).physicalRamSize;
      if (v >= kMinSaneRamBytes) ramBytes = v;
    }
  } catch (_) {}
  // A/B TERKONTROL: `--dart-define=PERF_ABC_OFF=true` → pakai cap STATIS LAMA
  // (40MB/120) untuk baseline, tanpa mengubah kode. Default = A/B/C aktif.
  final capBytes =
      kPerfAbcOff ? (40 << 20) : imageCacheBytesForRam(ramBytes);
  final capEntries = kPerfAbcOff ? 120 : imageCacheEntriesForRam(ramBytes);
  PaintingBinding.instance.imageCache.maximumSize = capEntries;
  PaintingBinding.instance.imageCache.maximumSizeBytes = capBytes;
  dlog('[IMGCACHE] ram=${(ramBytes / (1 << 30)).toStringAsFixed(1)}GB '
      'cap=${(capBytes / (1 << 20)).toStringAsFixed(0)}MB/$capEntries entri');
  kFirebaseOptionsOverride = firebaseOptions;
  // Crashlytics butuh Firebase ter-init dulu — aktifkan pasca-init di bawah.
  // Handler di sini hanya dlog; setelah FlutterError.crashlytics disambung,
  // error berikutnya otomatis terkirim (dan error sebelum init tetap ter-log).
  FlutterError.onError = (details) {
    dlog('[FLUTTER-ERROR] ${details.exception}');
    dlog('[FLUTTER-ERROR] ${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    dlog('[PLATFORM-ERROR] $error\n$stack');
    return true;
  };
  // Paralel: Supabase + Firebase + kunci Keystore/SQLite (independen) —
  // prewarmDb di sini (bukan setelah init) supaya antrean Keystore tidak
  // menunggu auth selesai. Hemat 0.5-2s di Xiaomi cold start.
  //
  // Boundary: inject di composition root (core/widgets dilarang import services/).
  MessageCache.isStoragePath = StoragePhotoService.instance.isPath;
  MessageCache.isStorageVoicePath = StoragePhotoService.instance.isVoicePath;
  VoicePrefetch.downloader = StoragePhotoService.instance.downloadBytes;
  VideoPrefetch.downloader = StoragePhotoService.instance.downloadBytes;
  VideoPrefetch.posterGenerator = StoragePhotoService.instance.storyVideoPoster;
  VideoPrefetch.posterDownloader = StoragePhotoService.instance.downloadBytes;
  //
  // Setiap anggota DIBATASI timeout: satu init yang menggantung (Keystore /
  // SQLite / Firebase) tidak boleh menahan first-frame selamanya → gejala
  // "stuck di logo". Yang timeout dilewati + dicatat ke logcat ([BOOT]).
  Future<void> guard(String name, Future<void> Function() fn, int secs) async {
    debugPrint('[BOOT] start $name');
    try {
      await fn().timeout(Duration(seconds: secs));
      debugPrint('[BOOT] done $name');
    } on TimeoutException {
      debugPrint('[BOOT] TIMEOUT $name (${secs}s) — dilewati, app tetap jalan');
    } catch (e) {
      debugPrint('[BOOT] error $name: $e');
    }
  }

  await Future.wait([
    guard('supabase', SupabaseConfig.init, 20),
    guard('msgdb', MessageCache.instance.prewarmDb, 15),
    // Index disk media siap sebelum frame pertama — readSync avatar
    // (Online/Chat/Timeline) langsung hit, tanpa prewarm race.
    guard('mediadisk', () async {
      await MediaDiskCache.instance.prewarm();
      await VideoFileCache.instance.prewarm(); // video persisten (spt voice).
      await PostPhotoCache.instance.prewarm(); // thumb post (anti-kedip TL).
      // Aspek foto chat persisten (bubble tidak "melompat" saat cold start).
      await PhotoAspectCache.instance.prewarm();
      // Poster kecil foto chat (frame pertama langsung bergambar).
      await ChatPosterCache.instance.prewarm();
      // CATATAN: poster/aspek TIDAK didaftarkan ke ImageCacheHygiene — hygiene
      // dipanggil saat background/idle (app.dart) sehingga poster (yang justru
      // harus PERSISTEN untuk cold start) akan terhapus. Keduanya dibersihkan
      // HANYA saat logout (chat_provider.reset()).
    }, 15),
    guard('firebase', () async {
      try {
        // Flavor dev (Supabase local): Firebase dev belum dikonfigurasi —
        // skip init supaya build & runtime jalan tanpa google-services.json.
        if (AppEnv.isDev) {
          dlog('[FIREBASE] dev mode: FCM dinonaktifkan');
          return;
        }
        await Firebase.initializeApp(options: firebaseOptions ?? DefaultFirebaseOptions.currentPlatform);
        _firebaseReady = true;
        // Crash reporting aktif hanya di rilis — debug jangan spam console
        // (default: enabled in release, disabled in debug).
        await FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(kReleaseMode);
        FlutterError.onError = (details) {
          // dlog dulu (logcat/profile terlihat) — lalu kirim ke Crashlytics.
          // Tanpa dlog, error framework SETELAH Firebase init hilang dari
          // logcat (recordFlutterFatalError tak menulis apa pun ke log) →
          // sulit melacak crash "app menciut sendiri".
          dlog('[FLUTTER-ERROR] ${details.exception}');
          dlog('[FLUTTER-ERROR] ${details.stack}');
          FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          dlog('[PLATFORM-ERROR] $error\n$stack');
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
      } on UnsupportedError catch (e) {
        dlog('[FIREBASE] iOS belum dikonfigurasi, lewati: $e');
      } on FirebaseException catch (e) {
        if (e.code == 'duplicate-app') _firebaseReady = true; else dlog('[FIREBASE] init gagal: $e');
      } catch (e) {
        dlog('[FIREBASE] init error: $e');
      }
    }, 25),
  ]);
  debugPrint('[BOOT] all init done — lanjut runApp');
  // Topup YukCoin (Google Play Billing) — hanya aktif di build play.
  try {
    await TopupService.instance.init();
  } catch (e) {
    dlog('[BOOT] topup init error: $e');
  }
  // Swap dummy ⇄ admin: hapus notifikasi akun lama yang masih tampil.
  AdminGate.onDummySwap = () async {
    try {
      await localNotifications.cancelAll();
    } catch (_) {}
  };
  // Simpan uid sesi aktif untuk filter anti-bocor background isolate.
  try {
    final uid0 = Supabase.instance.client.auth.currentUser?.id ?? '';
    final prefs0 = await SharedPreferences.getInstance();
    if (uid0.isNotEmpty) {
      await prefs0.setString('current_uid', uid0);
    }
    Supabase.instance.client.auth.onAuthStateChange.listen((d) {
      SharedPreferences.getInstance().then((p) {
        final uid = d.session?.user.id ?? '';
        if (uid.isNotEmpty) {
          p.setString('current_uid', uid);
        } else {
          p.remove('current_uid');
        }
      });
    }, onError: (e) => dlog('uid-persist auth stream error: $e'));
  } catch (_) {}
  // Fire-and-forget yang tidak block TTI
  unawaited(AdminGate.postInit?.call());
  // Battery Saver exemption (gaya WhatsApp): minta SEKALI saat app pernah
  // dibuka (ditunda 2s agar tak ganggu boot). Tanpa ini UI lag saat battery
  // saver ON (refresh dikunci 60Hz + bg di-throttle, khusus MIUI).
  unawaited(() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    try {
      final sp = await SharedPreferences.getInstance();
      final asked = sp.getBool('battery_opt_asked') ?? false;
      if (await BatteryOptimizationService.isIgnoring()) return;
      if (asked) return; // sudah pernah minta sekali — jangan nagging.
      await BatteryOptimizationService.requestIgnore();
      await sp.setBool('battery_opt_asked', true);
    } catch (e) {
      dlog('[BATTERY] prompt error: $e');
    }
  }());
  // NavGate: jembatan navigasi/dialog UI (provider dilarang import screens/).
  NavGate.incomingCallBuilder = ({
    required String callId,
    required String callerUid,
    required String callType,
    required String chatId,
    bool autoAccept = false,
  }) =>
      IncomingCallScreen(
        callId: callId,
        callerUid: callerUid,
        callType: callType,
        chatId: chatId,
        autoAccept: autoAccept,
      );
  NavGate.topupSheet = showTopupSheet;
  // Meta App Events (FB Ads): no-op selama App ID belum diisi.
  unawaited(MetaAnalytics.init());
  // TikTok App Events (TikTok Ads) — init SDK native (App ID dari manifest,
  // Access Token dari --dart-define). Best-effort, tidak memblok boot.
  unawaited(
    TikTokService.instance.init(
      accessToken: AppEnv.tiktokAccessToken,
      debug: AppEnv.tiktokDebug,
    ),
  );
  // Atribusi sumber user (Play Install Referrer + Firebase Analytics).
  // Baca sekali; aman & murah bila dipanggil berkali-kali.
  unawaited(AttributionService.instance.readOnce());
  // Wiring downloader foto post (core/ tidak boleh import services/).
  PostPhotoCache.downloader = StoragePhotoService.instance.downloadBytes;
  // Thumb server-side (transformasi) untuk timeline — hemat data vs unduh full.
  // WAJIB `resize: contain` (+ width): tanpa itu Supabase TIDAK menjaga
  // aspek (terukur: width=400 → 400×1440, bukan 400×533). Dengan contain,
  // aspek proporsional & byte jauh lebih kecil (31,7KB → 22,7KB per sampel).
  PostPhotoCache.thumbDownloader = (path, width) =>
      StoragePhotoService.instance.downloadThumbBytes(
        path,
        width: width,
        resize: ResizeMode.contain,
        quality: 80,
      );
  // LP-F: link preview via Edge Function (server-side fetch) — lebih andal
  // utk situs anti-bot (TikTok/Shopee) & konsisten lintas device. Gagal →
  // LinkPreviewService fallback ke fetch device (service tetap aman).
  LinkPreviewService.serverFetch = (url) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'link-preview',
        body: {'url': url},
      );
      final d = res.data;
      if (d is Map && d['ok'] == true) {
        return LinkPreviewData(
          url: url,
          title: '${d['title'] ?? ''}',
          description: '${d['description'] ?? ''}',
          image: '${d['image'] ?? ''}',
          siteName: '${d['siteName'] ?? ''}',
        );
      }
    } catch (_) {}
    return null; // → service fallback ke fetch device
  };
  unawaited(MessageCache.instance.clearLegacyV1Only());
  unawaited(PhotoCache.instance.cleanOldPhotos());
  unawaited(PostPhotoCache.instance.cleanOldPhotos());
  // PERF: mulai sesi dengan cache RAM bersih (basis nol) supaya sisa data
  // proses lama (hot-restart / restore) tidak menahan memori sia-sia.
  // Murah: cache RAM memang belum terisi saat cold start.
  try {
    MessageCache.instance.trimMemCache();
  } catch (_) {}
  try {
    PhotoCache.instance.trimMemCache();
  } catch (_) {}
  try {
    PostPhotoCache.instance.trimMemCache();
  } catch (_) {}
  if (_firebaseReady) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  // Channel + permission cepat (tanpa getToken 5s) — getToken lazy setelah runApp.
  // DIBATASI timeout: ketiganya menyentuh plugin/jaringan (notifications,
  // asset decode, GoogleFonts.pendingFonts) — satu yang menggantung menahan
  // first-frame selamanya → "stuck di logo".
  await guard('notifications', _initNotificationsFast, 15);
  await guard('chatbg', warmChatBackground, 10);
  await guard('theme', AppTheme.init, 15);
  // Jaring aman edge-to-edge Android 15: pastikan mode default (edgeToEdge)
  // selalu aktif di start. Bila proses di-kill saat Story composer terbuka
  // (mode manual menyembunyikan nav bar), state bisa tertinggal untuk frame
  // berikutnya — reset di sini supaya inset benar sejak awal.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Kunci portrait DILEPAS (2026): Android 16 mengabaikan pembatasan
  // orientasi di layar besar (tablet/foldable) + Play menolak
  // screenOrientation — app mendukung rotasi penuh. Jangan kembalikan
  // setPreferredOrientations tanpa QA landscape (kamera, call, story).
  // Probe frame (no-op bila PERF_PROBE off) — ukur build/raster per frame.
  PerfProbe.hookFrameTimings();
  debugPrint('[BOOT] runApp');
  // ProviderScope (Riverpod) membungkus root — berdampingan dengan
  // MultiProvider yang ada selama migrasi Provider -> Riverpod.
  // `_rootContainer` disimpan agar kode NON-WIDGET (mis. bootstrap update)
  // bisa membaca provider Riverpod tanpa BuildContext.
  final container = ProviderContainer();
  _rootContainer = container;
  runApp(UncontrolledProviderScope(container: container, child: const ChatYukApp()));
  // Token FCM lambat (5s) - lazy setelah UI tampil, tidak block TTI
  unawaited(_initFcmTokenLazy());
  // Cek update (silent) — tunda sedikit supaya frame pertama + warm-gate
  // selesai dulu; popup update tidak boleh menahan TTI.
  unawaited(
    Future<void>.delayed(const Duration(seconds: 4)).then(
      (_) => _rootContainer
          ?.read(updateProvider.notifier)
          .check(navigatorKey: navigatorKey),
    ),
  );
  // Warm-up jalur RPC: panggilan Supabase PERTAMA selalu jauh lebih mahal
  // (terukur 839ms vs 127-170ms setelahnya) karena TLS handshake + koneksi
  // pool dingin. Bayar biaya itu SEKARANG saat user masih melihat layar
  // pertama, supaya saat mereka membuka tab Pesan/Online jalurnya sudah
  // hangat. Fire-and-forget: gagal = abaikan (bukan jalur kritis).
  unawaited(_warmupRpcConnection());
}

/// Hangatkan koneksi RPC Supabase dengan satu panggilan paling ringan yang
/// tersedia. Dijalankan setelah UI tampil (tidak menahan TTI) dan hasilnya
/// sengaja diabaikan — tujuannya hanya memanaskan koneksi/TLS.
///
/// PENTING (perf): dipanggil juga saat app RESUME dari idle. Koneksi HTTP
/// keep-alive Supabase menjadi BASI setelah idle → request pertama user
/// (get_wallet, online.rpc) menggantung sampai OS TCP timeout (~13 detik,
/// terukur di PerfProbe). Warm-up ini "membuang" koneksi basi lebih dulu
/// sehingga request nyata berikutnya memakai koneksi segar.
Future<void> _warmupRpcConnection() async {
  try {
    // PERF (2026-10-12, terukur): dulu jeda 600 ms — tapi RPC boot (dari tab
    // Online/warm-gate) sudah menembak di ~0 ms, sehingga mereka KENA koneksi
    // dingin (TLS) dan warm-up justru telat. Sekarang warm-up yang menang
    // lomba: mulai setelah frame pertama saja (16 ms), supaya handshake TLS
    // selesai/koneksi pool siap SEBELUM burst RPC boot mengantre.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await warmupRpcConnection();
  } catch (e) {
    dlog('[WARMUP] dilewati: $e');
  }
}

/// Inti warm-up (tanpa jeda) — dipanggil saat boot & saat resume.
/// Timeout PENDEK (2s): kalau koneksi basi menggantung, kita lepaskan cepat
/// dan biarkan retry/permintaan berikutnya memakai koneksi baru, alih-alih
/// menunggu timeout TCP ~13 detik.
///
/// SINGLETON IN-FLIGHT: banyak pemanggil saat resume (app.dart + tiap tab
/// admin yang menembak RPC dari timer resume-nya) berbagi SATU warm-up yang
/// sama. Tanpa ini, tiap pemanggil menembak query sendiri ke koneksi basi →
/// banjir request yang semuanya menggantung.
Future<void>? _warmupInflight;

Future<void> warmupRpcConnection() {
  final running = _warmupInflight;
  if (running != null) return running;
  final fut = _warmupRpcConnectionImpl();
  _warmupInflight = fut;
  fut.whenComplete(() {
    if (identical(_warmupInflight, fut)) _warmupInflight = null;
  });
  return fut;
}

Future<void> _warmupRpcConnectionImpl() async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null || uid.isEmpty) return;
  await Supabase.instance.client
      .from('app_settings')
      .select('id')
      .eq('id', 'global')
      .maybeSingle()
      .timeout(const Duration(seconds: 2));
  dlog('[WARMUP] koneksi RPC siap');
}

/// Dipanggil dari handler resume layar (mis. tab admin) SEBELUM menembak RPC.
/// Menunggu warm-up singleton selesai supaya RPC berikutnya memakai koneksi
/// segar — bukan koneksi basi yang menggantung ~13 detik. Aman dipanggil
/// berkali-kali & dari banyak layar (berbagi warm-up yang sama).
///
/// Batas tunggu 2,5s: kalau warm-up sendiri tersendat, jangan menahan UI
/// selamanya — lanjut saja (koneksi baru akan dipakai request berikutnya).
Future<void> resumeWarmup() async {
  try {
    await warmupRpcConnection().timeout(
      const Duration(milliseconds: 2500),
    );
  } catch (_) {
    // Lewati — lebih baik mencoba fetch daripada menahan UI.
  }
}
