import 'dart:async';

import 'package:flutter/foundation.dart';
import '../utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/active_call_model.dart';
import '../services/admin_service.dart';
import '../services/admin_call_watch_service.dart';
export '../services/admin_call_watch_service.dart' show WatchSession;
import '../core/cache/message_cache.dart';
import '../core/cache/photo_cache.dart';
import '../core/admin_err.dart';
import '../services/storage_photo_service.dart';

part 'admin/admin_base.dart';
part 'admin/admin_notif.dart';
part 'admin/admin_passthrough.dart';
part 'admin/admin_stats.dart';
part 'admin/admin_devices.dart';
part 'admin/admin_deleted.dart';
part 'admin/admin_chats.dart';

/// AdminProvider: state global panel admin (statistik, devices, deleted,
/// chats, calls, contact, notifikasi) + passthrough RPC AdminService.
///
/// Dipecah per domain lewat `part` + mixin (pola `ChatService`):
/// notif, passthrough RPC, stats, devices, deleted, chats.
/// State bersama di [AdminBase]. Interface publik tidak berubah —
/// pemanggil & test tetap memakai `AdminProvider` satu entry ini.
class AdminProvider extends AdminBase
    with
        AdminNotifMx,
        AdminPassthroughMx,
        AdminStatsMx,
        AdminDevicesMx,
        AdminDeletedMx,
        AdminChatsMx {
  AdminProvider({super.service, super.sb});

  /// Hapus SEMUA cache data admin di perangkat ini (tombol di tab Global
  /// Setting). Dipakai bila HP bergantian dipakai orang lain — data admin
  /// memuat PII user (email/IP/device).
  /// Di core (bukan mixin chats) karena menyentuh state lintas-domain —
  /// member antar-mixin tak saling terlihat, tapi class akhir melihat semua.
  Future<void> clearAdminCache() async {
    for (final k in AdminBase.adminCacheKeys) {
      try {
        await MessageCache.instance.removeRawList(k);
        await MessageCache.instance.removeRawObj(k);
      } catch (_) {}
    }
    // Pesan monitor per-chat: kunci dinamis, bersihkan yang sedang terbuka.
    final cur = _chatMsgCacheFor;
    if (cur != null) {
      try {
        await MessageCache.instance.removeRawList(AdminBase.adminChatMsgKey(cur));
      } catch (_) {}
    }
    // Kosongkan state memori supaya UI tidak menampilkan data basi.
    _stats = null;
    _chats = const [];
    _devices = const [];
    _deleted = const [];
    _contactMessages = const [];
    _chatMessages = const [];
    _chatMsgCacheFor = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _callRealtimeDebounce?.cancel();
    try {
      _callChannel?.unsubscribe();
      _sb.removeChannel(_callChannel!);
    } catch (_) {}
    _callChannel = null;
    try {
      _notifCtrl.close();
    } catch (_) {}
    super.dispose();
  }
}
