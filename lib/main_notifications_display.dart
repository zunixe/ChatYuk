part of 'main.dart';

// Pembuatan CHANNEL Android + tampilan notifikasi lokal (dipisah dari
// main_notifications.dart; REVIEW_2026-10-24 ARCH-01/R-11).

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
      if (_rootContainer!.read(callProvider.notifier).activeCallId == callId) {
        _rootContainer!.read(callProvider.notifier).unregisterCall(callId);
      }
      // JANGAN pop buta di sini: IncomingCallScreen menutup sendiri via
      // subscription status realtime (canceled/ended → _close). Pop buta
      // menutup rute TERATAS apa pun (mis. room chat yang sedang dibuka)
      // dan pop paksa menembus PopScope → dispose melempar → navigator
      // rusak (back mati, UI seperti hang, CPU 0%).
      try {
        final dynamic prov = _rootContainer!.read(callProvider.notifier);
        if (prov.activeSession != null) {
          await prov.clearSession();
        }
      } catch (e) { dlog('[NOTIF]: $e'); }
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
    final title = _pick(data, ['otherName', 'callerName'], AppLocale.s.unknownUser);
    final body = _notifBody(message, data) ?? AppLocale.s.notifCallEndedBody;
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
      } catch (e) { dlog('[NOTIF]: $e'); }
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
      if (_rootContainer!.read(callProvider.notifier).activeCallId == callId) {
        _rootContainer!.read(callProvider.notifier).unregisterCall(callId);
      }
      // JANGAN pop buta (lihat call_ended di atas): IncomingCallScreen
      // menutup sendiri via realtime; pop buta bisa menutup layar yang
      // salah dan merusak navigator.
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
  // User disembunyikan dari daftar Online → jangan beri notif "online".
  if (_fcmType == 'online') {
    final ouid = '${data['otherUid'] ?? data['uid'] ?? ''}';
    if (await NotificationPrefsService.isOnlineHidden(ouid)) return;
  }

  final s = AppLocale.s;
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
  final rawBody = isDataOnly
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
  // Pesan berisi LINK → deskripsi/judul preview (bukan URL mentah).
  final isChatMsgFg = type == 'message' || type == 'mention';
  final body = isChatMsgFg
      ? notifBodyForLinkPreview(
          Map<String, dynamic>.from(data as Map),
          rawBody,
        )
      : rawBody;

  // BigPicture: gambar preview LINK diutamakan (pesan berisi link), lalu
  // avatar pengirim. Cache + prune di `_notifImageFile`.
  final previewImgFg = isChatMsgFg ? '${data['previewImage'] ?? ''}' : '';
  final preferLink = isNotifPreviewImage(previewImgFg);
  final picUrl = preferLink ? previewImgFg : (data['avatarUrl'] as String?);
  final String? bigPicPath = picUrl == null
      ? null
      : await _notifImageFile(picUrl, tag: preferLink ? 'link' : 'avatar');
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
