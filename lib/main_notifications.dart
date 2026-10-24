part of 'main.dart';

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
  } catch (e) { dlog('[NOTIF]: $e'); }
}

/// Hapus thread + notif shade + segarkan ringkasan untuk satu chat.
Future<void> _clearChatNotif(String chatKey, {bool cancelShade = true}) async {
  try {
    _notifThreads.remove(chatKey);
    _notifPayloads.remove(chatKey);
    if (cancelShade) {
      await localNotifications.cancel(id: notifIdForKey(chatKey));
    }
    await _refreshNotifSummary(AppLocale.s);
  } catch (e) { dlog('[NOTIF]: $e'); }
}

/// Unduh gambar untuk BigPicture notifikasi (avatar ATAU gambar preview link).
///
/// Cache per-URL (nama file = hash) + prune (maks [_notifMediaKeep]) supaya
/// folder temp tidak menumpuk — dulu 1 file baru per notifikasi (bocor).
const int _notifMediaKeep = 24;

Future<String?> _notifImageFile(String url, {String tag = 'img'}) async {
  if (url.isEmpty || !url.startsWith('http')) return null;
  try {
    final dir = Directory('${(await getTemporaryDirectory()).path}/notif_media');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File('${dir.path}/${tag}_${url.hashCode.toRadixString(16)}.img');
    if (f.existsSync() && f.lengthSync() > 0) return f.path;
    final resp = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 4));
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
    if (resp.bodyBytes.length > 3 * 1024 * 1024) return null;
    await f.writeAsBytes(resp.bodyBytes, flush: true);
    try {
      final files = dir.listSync().whereType<File>().toList();
      if (files.length > _notifMediaKeep) {
        files.sort(
          (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
        );
        for (final old in files.take(files.length - _notifMediaKeep)) {
          try {
            old.deleteSync();
          } catch (e) { dlog('[NOTIF]: $e'); }
        }
      }
    } catch (e) { dlog('[NOTIF]: $e'); }
    return f.path;
  } catch (_) {
    return null;
  }
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
    final s = AppLocale.s;
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
  } catch (e) { dlog('[NOTIF]: $e'); }
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
    } catch (e) { dlog('[NOTIF]: $e'); }
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
  } catch (e) { dlog('[NOTIF]: $e'); }
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
    } catch (e) { dlog('[NOTIF]: $e'); }
    list.add(job);
    while (list.length > 10) {
      list.removeAt(0);
    }
    await prefs.setString(_pendingNotifActionsKey, jsonEncode(list));
  } catch (e) { dlog('[NOTIF]: $e'); }
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
      } catch (e) { dlog('[NOTIF]: $e'); }
    }
  } catch (e) { dlog('[NOTIF]: $e'); }
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
    } catch (e) { dlog('[NOTIF]: $e'); }
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
          publishableKey: AppEnv.supabaseAnonKey,
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
      } catch (e) { dlog('[NOTIF]: $e'); }
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
  } catch (e) { dlog('[NOTIF]: $e'); }
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

