part of 'main.dart';

// Handler notifikasi BACKGROUND (dipisah dari main_notifications.dart;
// REVIEW_2026-10-24 ARCH-01/R-11 — file utama > 1000 baris).
// Entry-point FCM & action lokal: tetap `@pragma('vm:entry-point')` dan
// didaftarkan dari main.dart seperti sebelumnya.

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
  // User disembunyikan dari daftar Online → jangan beri notif "online".
  if (type == 'online') {
    final ouid = '${data['otherUid'] ?? data['uid'] ?? ''}';
    if (await NotificationPrefsService.isOnlineHidden(ouid)) {
      dlog('[NOTIF_BG] drop online: $ouid disembunyikan');
      return;
    }
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

  // Pesan TEKS berisi LINK → deskripsi/judul preview (bukan URL mentah).
  final isChatMsg = type == 'message' || type == 'mention';
  final notifText = isChatMsg
      ? notifBodyForLinkPreview(Map<String, dynamic>.from(data as Map), body)
      : body;

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
  // Gambar preview LINK untuk BigPicture (hanya bila notifikasi TIDAK
  // ber-thread — MessagingStyle tidak bisa digabung BigPicture).
  final previewImg = isChatMsg ? '${data['previewImage'] ?? ''}' : '';
  final linkPic = (bgKey == null && isNotifPreviewImage(previewImg))
      ? await _notifImageFile(previewImg, tag: 'link')
      : null;
  final bgAndroid = linkPic != null
      ? lpn.AndroidNotificationDetails(
          _channelId,
          'Chat Notifications',
          channelDescription: 'New message notifications from chat',
          importance: lpn.Importance.max,
          priority: lpn.Priority.max,
          styleInformation: lpn.BigPictureStyleInformation(
            lpn.FilePathAndroidBitmap(linkPic),
            contentTitle: notifPreviewImageTitle(
              Map<String, dynamic>.from(data as Map),
            ),
            summaryText: notifText,
            hideExpandedLargeIcon: true,
          ),
          largeIcon: lpn.FilePathAndroidBitmap(linkPic),
        )
      : null;

  await plugin.show(
    id: notifIdForKey(
      data['callId'] ?? data['chatId'] ?? data['roomId'] ?? 'bg',
    ),
    title: bgKey != null ? bgTitle : title,
    body: notifText,
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
          : (bgAndroid ?? androidDetails),
    ),
    payload: jsonEncode(data),
  );
}
