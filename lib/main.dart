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
import 'providers/nav_provider.dart';
import 'screens/incoming_call_screen.dart';
import 'screens/call_screen.dart';
import 'screens/private_chat_screen.dart';
import 'screens/room_chat_screen.dart';
import 'config/env.dart';
import 'config/strings.dart';
import 'config/supabase_config.dart';
import 'config/theme.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'utils.dart';
import 'core/cache/message_cache.dart';
import 'core/cache/media_disk_cache.dart';
import 'core/cache/photo_cache.dart';
import 'services/post_photo_cache.dart';
import 'core/media/chat_background.dart';
import 'services/meta_analytics_service.dart';
import 'services/notification_prefs_service.dart';

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
  if (type == 'room' || type == 'mention') {
    final roomId = '${data['roomId'] ?? ''}';
    if (roomId.isEmpty) return null;
    return (
      key: roomId,
      title: '${data['roomName'] ?? 'Room'}',
      grouped: true,
      canReply: true,
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

List<lpn.AndroidNotificationAction> _chatNotifActions(
  S s, {
  required bool canReply,
  required bool canMarkRead,
}) {
  return [
    if (canReply)
      lpn.AndroidNotificationAction(
        'reply',
        s.menuReply,
        inputs: [lpn.AndroidNotificationActionInput(label: s.menuReply)],
        cancelNotification: false,
      ),
    if (canMarkRead)
      lpn.AndroidNotificationAction(
        'mark_read',
        s.notifActionMarkRead,
        cancelNotification: false,
      ),
  ];
}

lpn.AndroidNotificationDetails _chatNotifDetails(
  S s, {
  required String title,
  required List<_ThreadMsg> entries,
  required bool grouped,
  required bool canReply,
  required bool canMarkRead,
}) {
  return lpn.AndroidNotificationDetails(
    _channelId,
    s.notifChannelName,
    channelDescription: s.notifChannelDesc,
    importance: lpn.Importance.max,
    priority: lpn.Priority.max,
    category: lpn.AndroidNotificationCategory.message,
    visibility: lpn.NotificationVisibility.public,
    autoCancel: true,
    groupKey: _notifGroupKey,
    styleInformation: entries.isEmpty
        ? null
        : _threadStyle(title, entries, grouped: grouped),
    actions: _chatNotifActions(
      s,
      canReply: canReply,
      canMarkRead: canMarkRead,
    ),
  );
}

/// Tampilkan/perbarui notif ringkasan grup ("N pesan dari M chat") ala WA.
/// Hanya saat ≥2 chat aktif; selain itu pastikan ringkasan hilang.
Future<void> _refreshNotifSummary(S s) async {
  try {
    if (_notifThreads.length >= 2) {
      var total = 0;
      final lines = <String>[];
      for (final e in _notifThreads.entries.take(5)) {
        final last = e.value.isEmpty ? null : e.value.last;
        if (last == null) continue;
        total += e.value.length;
        final t = last.text.length > 60
            ? '${last.text.substring(0, 60)}…'
            : last.text;
        lines.add('${last.sender}: $t');
      }
      await localNotifications.show(
        id: _summaryNotifId,
        title: 'ChatYuk',
        body: s.notifSummary(_notifThreads.length, total),
        notificationDetails: lpn.NotificationDetails(
          android: lpn.AndroidNotificationDetails(
            _channelId,
            s.notifChannelName,
            channelDescription: s.notifChannelDesc,
            importance: lpn.Importance.max,
            priority: lpn.Priority.max,
            groupKey: _notifGroupKey,
            setAsGroupSummary: true,
            groupAlertBehavior: lpn.GroupAlertBehavior.children,
            styleInformation: lpn.InboxStyleInformation(
              lines,
              contentTitle: 'ChatYuk',
              summaryText: s.notifSummary(_notifThreads.length, total),
            ),
          ),
        ),
      );
    } else {
      await localNotifications.cancel(id: _summaryNotifId);
    }
  } catch (_) {}
}

/// Hapus thread + notif shade + segarkan ringkasan untuk satu chat.
Future<void> _clearChatNotif(String chatKey, {bool cancelShade = true}) async {
  try {
    _notifThreads.remove(chatKey);
    _notifPayloads.remove(chatKey);
    if (cancelShade) {
      await localNotifications.cancel(id: notifIdForKey(chatKey));
    }
    await _refreshNotifSummary(localeProvider.s);
  } catch (_) {}
}

void _appendNotifThread(String chatKey, String sender, String text) {
  final list = _notifThreads.putIfAbsent(chatKey, () => []);
  list.add(_ThreadMsg(sender, text, DateTime.now()));
  while (list.length > _maxThreadMsgs) {
    list.removeAt(0);
  }
}

/// Identitas pengirim untuk Balas via notif (tanpa BuildContext).
Future<({String uid, String name, String gender})?> _mySenderInfo() async {
  try {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return null;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('nickname, gender')
          .eq('id', uid)
          .maybeSingle();
      final m = row as Map?;
      final name = '${m?['nickname'] ?? ''}'.trim();
      return (
        uid: uid,
        name: name.isEmpty ? 'Anon' : name,
        gender: '${m?['gender'] ?? ''}',
      );
    } catch (_) {
      return (uid: uid, name: 'Anon', gender: '');
    }
  } catch (_) {
    return null;
  }
}

/// Tampilkan ulang notif satu chat dari thread tersimpan (mis. sesudah
/// Balas via notif agar balasan ikut tampil di thread).
Future<void> _reshowChatNotif(String chatKey) async {
  try {
    final data = _notifPayloads[chatKey];
    final entries = _notifThreads[chatKey];
    if (data == null || entries == null || entries.isEmpty) return;
    final info = notifThreadOf(data);
    if (info == null) return;
    final s = localeProvider.s;
    await localNotifications.show(
      id: notifIdForKey(chatKey),
      title: info.title.isEmpty ? s.notifNewMessage : info.title,
      body: entries.last.text,
      notificationDetails: lpn.NotificationDetails(
        android: _chatNotifDetails(
          s,
          title: info.title,
          entries: entries,
          grouped: info.grouped,
          canReply: info.canReply,
          canMarkRead: info.canMarkRead,
        ),
      ),
      payload: jsonEncode(data),
    );
    await _refreshNotifSummary(s);
  } catch (_) {}
}

/// Aksi notif foreground: Balas inline / Tandai dibaca.
Future<void> _handleNotifAction(lpn.NotificationResponse response) async {
  try {
    final action = response.actionId;
    if (action != 'reply' && action != 'mark_read') return;
    Map<String, dynamic>? data;
    try {
      final p = response.payload;
      if (p != null && p.isNotEmpty) {
        data = Map<String, dynamic>.from(jsonDecode(p) as Map);
      }
    } catch (_) {}
    if (data == null) return;
    final info = notifThreadOf(data);
    if (info == null) return;
    final me = await _mySenderInfo();
    if (me == null) return;
    final chat = ChatService();
    if (action == 'mark_read') {
      if (!info.canMarkRead) return;
      await chat.markAsRead(info.key, me.uid);
      await _clearChatNotif(info.key);
      return;
    }
    final text = (response.input ?? '').trim();
    if (text.isEmpty) return;
    final short = text.length > 2000 ? text.substring(0, 2000) : text;
    if (data['roomId'] != null && '${data['roomId']}'.isNotEmpty) {
      await chat.sendRoomMessage(
        roomId: info.key,
        senderId: me.uid,
        senderName: me.name,
        senderGender: me.gender,
        text: short,
      );
    } else {
      await chat.sendPrivateMessage(
        chatId: info.key,
        senderId: me.uid,
        senderName: me.name,
        senderGender: me.gender,
        text: short,
      );
      await chat.markAsRead(info.key, me.uid);
    }
    _appendNotifThread(info.key, me.name, short);
    await _reshowChatNotif(info.key);
  } catch (_) {}
}

/// Simpan aksi notif untuk dikerjakan saat app hidup (dipakai jalur
/// background bila sesi belum bisa dipakai langsung).
Future<void> _stashPendingNotifAction(Map<String, dynamic> job) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingNotifActionsKey);
    List list = [];
    try {
      if (raw != null && raw.isNotEmpty) {
        list = List.from(jsonDecode(raw) as List);
      }
    } catch (_) {}
    list.add(job);
    while (list.length > 10) {
      list.removeAt(0);
    }
    await prefs.setString(_pendingNotifActionsKey, jsonEncode(list));
  } catch (_) {}
}

/// Kerjakan aksi notif tertunda (Balas/Tandai) sekali sesi pulih.
Future<void> _consumePendingNotifActions() async {
  try {
    if (!await _waitForSession()) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingNotifActionsKey);
    if (raw == null || raw.isEmpty) return;
    List list;
    try {
      list = List.from(jsonDecode(raw) as List);
    } catch (_) {
      return;
    }
    await prefs.remove(_pendingNotifActionsKey);
    final me = await _mySenderInfo();
    if (me == null) return;
    final chat = ChatService();
    for (final j in list) {
      try {
        final m = Map<String, dynamic>.from(j as Map);
        final action = '${m['action'] ?? ''}';
        final chatKey = '${m['chatKey'] ?? ''}';
        if (chatKey.isEmpty) continue;
        if (action == 'mark_read' && m['canMark'] == true) {
          await chat.markAsRead(chatKey, me.uid);
          await _clearChatNotif(chatKey);
        } else if (action == 'reply') {
          final text = '${m['text'] ?? ''}'.trim();
          if (text.isEmpty) continue;
          if (m['isRoom'] == true) {
            await chat.sendRoomMessage(
              roomId: chatKey,
              senderId: me.uid,
              senderName: me.name,
              senderGender: me.gender,
              text: text,
            );
          } else {
            await chat.sendPrivateMessage(
              chatId: chatKey,
              senderId: me.uid,
              senderName: me.name,
              senderGender: me.gender,
              text: text,
            );
            await chat.markAsRead(chatKey, me.uid);
          }
          await _clearChatNotif(chatKey);
        }
      } catch (_) {}
    }
  } catch (_) {}
}

/// Tap aksi notif saat app mati: coba kerjakan langsung (sesi Supabase
/// dipulihkan di isolate), gagal → antre ke prefs untuk sesi berikutnya.
@pragma('vm:entry-point')
Future<void> _notifActionBgHandler(lpn.NotificationResponse response) async {
  try {
    final action = response.actionId;
    if (action != 'reply' && action != 'mark_read') return;
    Map<String, dynamic>? data;
    try {
      final p = response.payload;
      if (p != null && p.isEmpty == false) {
        data = Map<String, dynamic>.from(jsonDecode(p) as Map);
      }
    } catch (_) {}
    if (data == null) return;
    final type = data['type'];
    final isRoom = type == 'room';
    final chatKey = isRoom ? '${data['roomId'] ?? ''}' : '${data['chatId'] ?? ''}';
    if (chatKey.isEmpty) return;
    if (action == 'mark_read' && !isRoom) {
      // hanya private yang didukung mark_read
    } else if (action == 'mark_read' && isRoom) {
      return;
    }
    final text = (response.input ?? '').trim();
    if (action == 'reply' && text.isEmpty) return;
    try {
      try {
        Supabase.instance.client;
      } catch (_) {
        await Supabase.initialize(
          url: AppEnv.supabaseUrl,
          anonKey: AppEnv.supabaseAnonKey,
        );
      }
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) throw StateError('no-session');
      String name = 'Anon';
      String gender = '';
      try {
        final row = await Supabase.instance.client
            .from('profiles')
            .select('nickname, gender')
            .eq('id', uid)
            .maybeSingle();
        final m = row as Map?;
        final n = '${m?['nickname'] ?? ''}'.trim();
        if (n.isNotEmpty) name = n;
        gender = '${m?['gender'] ?? ''}';
      } catch (_) {}
      final chat = ChatService();
      if (action == 'mark_read') {
        await chat.markAsRead(chatKey, uid);
      } else {
        final short = text.length > 2000 ? text.substring(0, 2000) : text;
        if (isRoom) {
          await chat.sendRoomMessage(
            roomId: chatKey,
            senderId: uid,
            senderName: name,
            senderGender: gender,
            text: short,
          );
        } else {
          await chat.sendPrivateMessage(
            chatId: chatKey,
            senderId: uid,
            senderName: name,
            senderGender: gender,
            text: short,
          );
          await chat.markAsRead(chatKey, uid);
        }
      }
      final plugin = lpn.FlutterLocalNotificationsPlugin();
      const androidInit = lpn.AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      await plugin.initialize(
        settings: const lpn.InitializationSettings(android: androidInit),
      );
      await plugin.cancel(id: response.id ?? notifIdForKey(chatKey));
    } catch (_) {
      await _stashPendingNotifAction({
        'action': action,
        'chatKey': chatKey,
        'isRoom': isRoom,
        'canMark': action == 'mark_read' && !isRoom,
        'text': action == 'reply' ? text : '',
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    }
  } catch (_) {}
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: kFirebaseOptionsOverride ?? DefaultFirebaseOptions.currentPlatform,
  );
  final data = message.data;
  final type = data['type'];
  final shouldShow = await NotificationPrefsService.shouldShowForFcmType(type as String?);
  dlog('[NOTIF_BG] type=$type shouldShow=$shouldShow data=$data');
  if (!shouldShow) return;
  // Isolate tidak punya BuildContext — baca bahasa dari prefs langsung.
  final bgPrefs = await SharedPreferences.getInstance();
  // Anti-bocor multi-akun (admin ⇄ dummy satu HP): push yang bukan untuk
  // sesi aktif dibuang. Server mengirim toUid = penerima; isolate tidak
  // punya sesi Supabase jadi bandingkan dengan uid tersimpan.
  final bgToUid = '${data['toUid'] ?? ''}';
  if (bgToUid.isNotEmpty) {
    final bgMyUid = bgPrefs.getString('current_uid') ?? '';
    if (bgMyUid.isNotEmpty && bgToUid != bgMyUid) {
      dlog('[NOTIF_BG] drop: toUid=$bgToUid != sesi $bgMyUid');
      return;
    }
  }
  final s = S(isId: (bgPrefs.getString('app_lang') ?? 'id') == 'id');
  // Chat yang dibisukan → tidak ada notifikasi (background).
  final bgChatId = '${data['chatId'] ?? ''}';
  if (bgChatId.isNotEmpty &&
      (type == 'message' ||
          type == 'mention' ||
          (type == null && data.containsKey('chatId'))) &&
      await NotificationPrefsService.isChatMuted(bgChatId)) {
    return;
  }
  // call_ended → panggilan selesai/dibatalkan. UPDATE notif call yang sama
  // (id = callId) jadi "Call ended". Langsung show dengan id sama (update
  // in-place) tanpa cancel dulu — cancel+show di MIUI justru menyisakan
  // notif kosong (ghost) + notif baru = 2 notif.
  if (type == 'call_ended') {
    final androidInit = const lpn.AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final settings = lpn.InitializationSettings(android: androidInit);
    final plugin = lpn.FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: settings);
    await _ensureAndroidChannels(plugin);
    final key = data['callId'] ?? data['chatId'] ?? '';
    if (key.isEmpty) return;
    dlog('[NOTIF_BG] call_ended key=$key data=$data');
    String _pick(Map d, List<String> keys, String fallback) {
      for (final k in keys) {
        final v = d[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return fallback;
    }
    String? _notifBody(RemoteMessage m, Map d) {
      final nb = m.notification?.body;
      if (nb != null && nb.trim().isNotEmpty) return nb.trim();
      final db = d['body'];
      if (db is String && db.trim().isNotEmpty) return db.trim();
      return null;
    }
    final title = _pick(data, ['otherName', 'callerName'], s.unknownUser);
    final body = _notifBody(message, data) ?? s.notifCallEndedBody;
    await plugin.show(
      id: notifIdForKey(key),
      title: title,
      body: body,
      notificationDetails: lpn.NotificationDetails(
        android: lpn.AndroidNotificationDetails(
          'chatyuk_calls',
          'Incoming Calls',
          channelDescription: 'Incoming call alerts with ringtone',
          importance: lpn.Importance.max,
          priority: lpn.Priority.max,
          autoCancel: true,
        ),
      ),
      payload: jsonEncode(data),
    );
    return;
  }
  // call_canceled → lama; pertahankan sebagai fallback: batalkan notif.
  if (type == 'call_canceled') {
    final androidInit = const lpn.AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final settings = lpn.InitializationSettings(android: androidInit);
    final plugin = lpn.FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: settings);
    final key = data['callId'] ?? data['chatId'] ?? '';
    await plugin.cancel(id: notifIdForKey(key));
    final alt = data['chatId'] as String?;
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
      type == 'broadcast' ||
      type == 'call' ||
      type == 'message' ||
      type == 'mention';
  final isMessage = type == 'message' ||
      (type == null && data.containsKey('chatId'));
  final title = isDataOnly
      ? (type == 'mention'
            ? data['roomName'] ?? 'Room'
            : data['otherName'] ?? data['fromName'] ?? s.unknownUser)
      : message.notification?.title ??
            (type == 'room' ? data['roomName'] ?? 'Room' : s.notifNewMessage);
  final body = isDataOnly
      ? (type == 'call'
            ? s.notifCallingBody
            : type == 'mention'
            ? ((data['body'] as String?)?.isNotEmpty == true
                  ? data['body'] as String
                  : s.mentionHint(''))
            : type == 'message'
            // Urutan fallback: data['body'] (trigger baru) → data['message']
            // (payload lama) → s.notifNewMessage. Jangan tampilkan string kosong.
            ? ((data['body'] as String?)?.isNotEmpty == true
                  ? data['body'] as String
                  : ((data['message'] as String?)?.isNotEmpty == true
                        ? data['message'] as String
                        : s.notifNewMessage))
            : type == 'broadcast'
            ? s.notifBroadcastBody((data['roomName'] as String?) ?? 'Room')
            : type == 'online'
            ? s.notifOnlineBody
            : type == 'follow'
            ? s.notifFollowBody
            : type == 'friend_request'
            ? s.notifFriendRequestBody
            : s.notifSubscribeBody)
      : message.notification?.body ?? (isMessage ? s.notifNewMessage : s.notifNewMessageBody);

  final androidInit = const lpn.AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  final settings = lpn.InitializationSettings(android: androidInit);
  final plugin = lpn.FlutterLocalNotificationsPlugin();
  await plugin.initialize(settings: settings);
  await _ensureAndroidChannels(plugin);

  // Panggilan masuk → notifikasi gaya telepon: suara alarm (loop channel),
  // heads-up di lockscreen. fullScreenIntent dihapus — USE_FULL_SCREEN_INTENT
  // ditolak Google Play (kebijakan hanya untuk app alarm/telepon).
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
          ongoing: true,
          autoCancel: false,
          category: lpn.AndroidNotificationCategory.call,
          visibility: lpn.NotificationVisibility.public,
        )
      : lpn.AndroidNotificationDetails(
          _channelId,
          'Chat Notifications',
          channelDescription: 'New message notifications from chat',
          importance: lpn.Importance.max,
          priority: lpn.Priority.max,
        );

  // Gaya WhatsApp (isolate background tidak punya thread tersimpan —
  // tampilkan entri tunggal + grup + aksi yang sama).
  final bgThread = notifThreadOf(Map<String, dynamic>.from(data as Map));
  final bgBroadcastKey =
      type == 'broadcast' ? '${data['roomId'] ?? 'broadcast'}' : null;
  final bgKey = bgThread?.key ?? bgBroadcastKey;
  final bgTitle = bgThread != null && bgThread.title.isNotEmpty
      ? bgThread.title
      : title;
  final bgSender = bgThread != null && bgThread.title.isNotEmpty
      ? bgThread.title
      : title;
  final bgGrouped = bgThread?.grouped ?? type == 'broadcast';
  await plugin.show(
    id: notifIdForKey(
      data['callId'] ?? data['chatId'] ?? data['roomId'] ?? 'bg',
    ),
    title: bgKey != null ? bgTitle : title,
    body: body,
    notificationDetails: lpn.NotificationDetails(
      android: bgKey != null
          ? lpn.AndroidNotificationDetails(
              _channelId,
              'Chat Notifications',
              channelDescription: 'New message notifications from chat',
              importance: lpn.Importance.max,
              priority: lpn.Priority.max,
              category: lpn.AndroidNotificationCategory.message,
              visibility: lpn.NotificationVisibility.public,
              autoCancel: true,
              groupKey: _notifGroupKey,
              styleInformation: _threadStyle(
                bgTitle,
                [_ThreadMsg(bgSender, body, DateTime.now())],
                grouped: bgGrouped,
              ),
              actions: _chatNotifActions(
                s,
                canReply: bgThread?.canReply ?? false,
                canMarkRead: bgThread?.canMarkRead ?? false,
              ),
            )
          : androidDetails,
    ),
    payload: jsonEncode(data),
  );
}

/// Buat channel notifikasi Android wajib (Android 8+ butuh channel terlebih
/// dahulu — tanpa ini notifikasi lokal & FCM tidak muncul). Dipanggil dari
/// background handler DAN `_initNotifications`.
Future<void> _ensureAndroidChannels(
  lpn.FlutterLocalNotificationsPlugin plugin,
) async {
  final androidImpl = plugin.resolvePlatformSpecificImplementation<lpn.AndroidFlutterLocalNotificationsPlugin>();
  // Hapus channel lama (high) supaya bisa recreate jadi max — Android tidak update importance channel yang sudah ada.
  try { await androidImpl?.deleteNotificationChannel(channelId: 'chatyuk_chat'); } catch (_) {}
  const chat = lpn.AndroidNotificationChannel(
    'chatyuk_chat',
    'Chat Notifications',
    description: 'New message notifications from chat',
    importance: lpn.Importance.max,
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
  final currentUid = Supabase.instance.client.auth.currentUser?.id;
  // Anti-bocor multi-akun (admin ⇄ dummy satu HP): push yang bukan untuk
  // sesi aktif dibuang — token FCM lama bisa masih hidup di server.
  final toUid = '${data['toUid'] ?? ''}';
  if (toUid.isNotEmpty &&
      currentUid != null &&
      currentUid.isNotEmpty &&
      toUid != currentUid) {
    dlog('[NOTIF_FG] drop: toUid=$toUid != sesi $currentUid');
    return;
  }
  // Jangan tampilkan notifikasi untuk diri sendiri (online, message, call, timeline, room)
  if (currentUid != null && currentUid.isNotEmpty) {
    final senderUid = (data['uid'] ?? data['otherUid'] ?? data['callerUid'] ?? data['authorId'] ?? data['sender_id'] ?? data['senderId'] ?? '') as String;
    if (senderUid.isNotEmpty && senderUid == currentUid) return;
    // Online khusus: data['uid'] adalah yang online
    if (data['type'] == 'online' && (data['uid'] as String?) == currentUid) return;
    // Timeline: authorId
    if ((data['type'] == 'timeline' || data['type'] == 'timeline_post') && (data['authorId'] as String?) == currentUid) return;
    // Room: cek jika data mengandung ownerId/sender
    if (data['type'] == 'room' && (data['ownerId'] as String?) == currentUid) return;
  }
  final shouldShow = await NotificationPrefsService.shouldShowForFcmType(data['type'] as String?);
  dlog('[NOTIF_FG] type=${data['type']} shouldShow=$shouldShow data=$data');
  if (!shouldShow) return;
  // call_ended → update notif call yang sama jadi "Call ended" + tutup
  // IncomingCallScreen & foreground service jika masih tampil (sinkron DB
  // notify_call_ended yang kini kirim type call_ended untuk semua status
  // terminal, bukan call_canceled).
  if (data['type'] == 'call_ended') {
    final key = data['callId'] ?? data['chatId'] ?? '';
    if (key.isEmpty) return;
    dlog('[NOTIF] call_ended key=$key title=${data['otherName']} body=${data['body']}');
    // Langsung update notif yang sama (id = callId) tanpa cancel dulu — cancel+show
    // di MIUI menyisakan ghost kosong.
    // Tutup IncomingCallScreen yang mungkin masih nongol (app foreground)
    final callId = (data['callId'] ?? data['chatId']) as String?;
    if (callId != null && callId.isNotEmpty) {
      if (CallProvider.instance.activeCallId == callId) {
        CallProvider.instance.unregisterCall(callId);
      }
      final nav = navigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        try { nav.pop(); } catch (_) {}
      }
      try {
        final dynamic prov = CallProvider.instance;
        if (prov.activeSession != null) {
          await prov.clearSession();
        }
      } catch (_) {}
    }
    String _pick(Map d, List<String> keys, String fallback) {
      for (final k in keys) {
        final v = d[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return fallback;
    }
    String? _notifBody(RemoteMessage m, Map d) {
      final nb = m.notification?.body;
      if (nb is String && nb.trim().isNotEmpty) return nb.trim();
      final db = d['body'];
      if (db is String && db.trim().isNotEmpty) return db.trim();
      return null;
    }
    final title = _pick(data, ['otherName', 'callerName'], localeProvider.s.unknownUser);
    final body = _notifBody(message, data) ?? localeProvider.s.notifCallEndedBody;
    String? bigPicPath;
    final avatarUrl2 = data['avatarUrl'] as String?;
    if (avatarUrl2 != null && avatarUrl2.startsWith('http')) {
      try {
        final resp = await http.get(Uri.parse(avatarUrl2)).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/notif_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await file.writeAsBytes(resp.bodyBytes);
          bigPicPath = file.path;
        }
      } catch (_) {}
    }
    await localNotifications.show(
      id: notifIdForKey(key),
      title: title,
      body: body,
      notificationDetails: lpn.NotificationDetails(
        android: lpn.AndroidNotificationDetails(
          'chatyuk_calls',
          'Incoming Calls',
          channelDescription: 'Incoming call alerts with ringtone',
          importance: lpn.Importance.max,
          priority: lpn.Priority.max,
          autoCancel: true,
          styleInformation: bigPicPath != null ? lpn.BigPictureStyleInformation(lpn.FilePathAndroidBitmap(bigPicPath), hideExpandedLargeIcon: true) : null,
          largeIcon: bigPicPath != null ? lpn.FilePathAndroidBitmap(bigPicPath) : null,
        ),
        iOS: bigPicPath != null ? lpn.DarwinNotificationDetails(attachments: [lpn.DarwinNotificationAttachment(bigPicPath)]) : null,
      ),
      payload: jsonEncode(data),
    );
    return;
  }
  // call_canceled → batalkan notifikasi call yang masih tampil + tutup
  // IncomingCallScreen yang mungkin masih terbuka.
  if (data['type'] == 'call_canceled') {
    final key = data['callId'] ?? data['chatId'] ?? '';
    await localNotifications.cancel(id: notifIdForKey(key));
    final alt = data['chatId'] as String?;
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
  // Chat yang dibisukan → tidak ada notifikasi (foreground).
  // NOTE: `type` dideklarasikan di bawah — pakai data mentah di sini.
  final _fcmType = data['type'];
  // Chat/room yang dibisukan → tidak ada notifikasi (foreground).
  // NOTE: `type` dideklarasikan di bawah — pakai data mentah di sini.
  // chatKey mencakup roomId (mute per-room pakai set yang sama).
  if (chatKey.isNotEmpty &&
      (_fcmType == 'message' ||
          _fcmType == 'room' ||
          _fcmType == 'mention' ||
          (_fcmType == null && data.containsKey('chatId'))) &&
      await NotificationPrefsService.isChatMuted(chatKey)) {
    return;
  }

  final s = localeProvider.s;
  final type = data['type'];
  final isDataOnly =
      type == 'online' ||
      type == 'follow' ||
      type == 'friend_request' ||
      type == 'subscribe' ||
      type == 'broadcast' ||
      type == 'call' ||
      type == 'message' ||
      type == 'mention';
  final isOnline = type == 'online';
  final title = isDataOnly
      ? (type == 'mention'
            ? data['roomName'] ?? 'Room'
            : data['otherName'] ?? data['fromName'] ?? s.unknownUser)
      : message.notification?.title ??
            (type == 'room' ? data['roomName'] ?? 'Room' : s.notifNewMessage);
  final body = isDataOnly
      ? (type == 'call'
            ? (data['callType'] == 'video'
                ? s.notifCallingVideoBody
                : s.notifCallingVoiceBody)
            : type == 'mention'
            ? ((data['body'] as String?)?.isNotEmpty == true
                  ? data['body'] as String
                  : s.mentionHint(''))
            : type == 'message'
            // Sama seperti background handler: body → message → fallback.
            ? ((data['body'] as String?)?.isNotEmpty == true
                  ? data['body'] as String
                  : ((data['message'] as String?)?.isNotEmpty == true
                        ? data['message'] as String
                        : s.notifNewMessageBody))
            : type == 'broadcast'
            ? s.notifBroadcastBody((data['roomName'] as String?) ?? 'Room')
            : isOnline
            ? s.notifOnlineBody
            : type == 'follow'
            ? s.notifFollowBody
            : type == 'friend_request'
            ? s.notifFriendRequestBody
            : s.notifSubscribeBody)
      : message.notification?.body ?? s.notifNewMessageBody;

  // Avatar BigPicture jika ada avatarUrl http
  String? bigPicPath;
  final avatarUrl = data['avatarUrl'] as String?;
  if (avatarUrl != null && avatarUrl.startsWith('http')) {
    try {
      final resp = await http.get(Uri.parse(avatarUrl)).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/notif_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await file.writeAsBytes(resp.bodyBytes);
        bigPicPath = file.path;
      }
    } catch (_) {}
  }
  // Gaya WhatsApp: thread MessagingStyle + grup + aksi (hanya untuk
  // pesan chat/room/broadcast; notif lain tetap teks polos + BigPicture).
  final threadInfo = notifThreadOf(
    Map<String, dynamic>.from(data as Map),
  );
  final broadcastKey = type == 'broadcast'
      ? '${data['roomId'] ?? 'broadcast'}'
      : null;
  final threadKey = threadInfo?.key ?? broadcastKey;
  var canReply = false;
  var canMarkRead = false;
  var grouped = false;
  var threadTitle = title;
  if (threadKey != null) {
    final sender = threadInfo != null
        ? (threadInfo.title.isEmpty ? title : threadInfo.title)
        : title;
    _appendNotifThread(threadKey, sender, body);
    _notifPayloads[threadKey] = Map<String, dynamic>.from(data as Map);
    grouped = threadInfo?.grouped ?? type == 'broadcast';
    threadTitle = threadInfo?.title.isNotEmpty == true
        ? threadInfo!.title
        : title;
    canReply = threadInfo?.canReply ?? false;
    canMarkRead = threadInfo?.canMarkRead ?? false;
  }
  await localNotifications.show(
    id: notifIdForKey(
      data['callId'] ?? data['chatId'] ?? data['roomId'] ?? 'local',
    ),
    title: threadKey != null ? threadTitle : title,
    body: body,
    notificationDetails: lpn.NotificationDetails(
      android: threadKey != null
          ? _chatNotifDetails(
              s,
              title: threadTitle,
              entries: _notifThreads[threadKey] ?? [],
              grouped: grouped,
              canReply: canReply,
              canMarkRead: canMarkRead,
            )
          : lpn.AndroidNotificationDetails(
              _channelId,
              s.notifChannelName,
              channelDescription: s.notifChannelDesc,
              importance: lpn.Importance.max,
              priority: lpn.Priority.max,
              styleInformation: bigPicPath != null
                  ? lpn.BigPictureStyleInformation(lpn.FilePathAndroidBitmap(bigPicPath), hideExpandedLargeIcon: true)
                  : null,
              largeIcon: bigPicPath != null ? lpn.FilePathAndroidBitmap(bigPicPath) : null,
            ),
      iOS: bigPicPath != null
          ? lpn.DarwinNotificationDetails(attachments: [lpn.DarwinNotificationAttachment(bigPicPath)])
          : null,
    ),
    payload: jsonEncode(data),
  );
  if (threadKey != null) {
    await _refreshNotifSummary(s);
  }
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
  final sess = CallProvider.instance.activeSession;
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
  final s = localeProvider.s;
  // Timeline post baru dari yang diikuti
  if (data['type'] == 'timeline_post') {
    nav.popUntil((r) => r.isFirst);
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      try {
        ctx.read<NavProvider>().goTo(2);
      } catch (_) {}
    }
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
      builder: (_) =>
          data['type'] == 'room' ||
                  data['type'] == 'broadcast' ||
                  data['type'] == 'mention'
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
  await localeProvider.init();
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
  FirebaseMessaging.onMessage.listen(_showLocalNotification);
  FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);
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
  await Future.wait([
    SupabaseConfig.init(),
    MessageCache.instance.prewarmDb(),
    // Index disk media siap sebelum frame pertama — readSync avatar
    // (Online/Chat/Timeline) langsung hit, tanpa prewarm race.
    MediaDiskCache.instance.prewarm(),
    Future(() async {
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
        FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
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
    }),
  ]);
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
    });
  } catch (_) {}
  // Fire-and-forget yang tidak block TTI
  unawaited(AdminGate.postInit?.call());
  // Meta App Events (FB Ads): no-op selama App ID belum diisi.
  unawaited(MetaAnalytics.init());
  unawaited(MessageCache.instance.clearLegacyV1Only());
  unawaited(PhotoCache.instance.cleanOldPhotos());
  unawaited(PostPhotoCache.instance.cleanOldPhotos());
  if (_firebaseReady) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  // Channel + permission cepat (tanpa getToken 5s) — getToken lazy setelah runApp
  await _initNotificationsFast();
  await warmChatBackground();
  await AppTheme.init();
  // Jaring aman edge-to-edge Android 15: pastikan mode default (edgeToEdge)
  // selalu aktif di start. Bila proses di-kill saat Story composer terbuka
  // (mode manual menyembunyikan nav bar), state bisa tertinggal untuk frame
  // berikutnya — reset di sini supaya inset benar sejak awal.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Kunci portrait dua lapis (manifest sudah portrait — ini lapisan Dart,
  // menutup edge-case hot-restart / perangkat yang mengabaikan manifest).
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const ChatYukApp());
  // Token FCM lambat (5s) - lazy setelah UI tampil, tidak block TTI
  unawaited(_initFcmTokenLazy());
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
Future<void> _warmupRpcConnection() async {
  try {
    // Beri jeda sangat singkat supaya frame pertama + warm-gate (cap 400ms)
    // selesai dulu; warm-up tidak boleh berebut dengan render awal.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    await Supabase.instance.client
        .from('app_settings')
        .select('id')
        .eq('id', 'global')
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    dlog('[WARMUP] koneksi RPC siap');
  } catch (e) {
    dlog('[WARMUP] dilewati: $e');
  }
}
