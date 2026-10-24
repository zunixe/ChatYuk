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
