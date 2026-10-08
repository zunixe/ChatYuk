import 'dart:async';

import 'package:flutter/foundation.dart';
import '../utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/active_call_model.dart';
import '../services/admin_service.dart';
import '../services/admin_call_watch_service.dart';
export '../services/admin_call_watch_service.dart'
    show WatchSession, WatchParticipant;
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
part 'admin/admin_chat_org.dart';
part 'admin/admin_attribution.dart';
part 'admin/admin_stories.dart';
part 'admin/admin_marketing.dart';
part 'admin/admin_rooms.dart';

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
        AdminChatsMx,
        AdminChatOrgMx,
        AdminAttributionMx,
        AdminStoriesMx,
        AdminMarketingMx,
        AdminRoomsMx {
  AdminProvider({super.service, super.sb}) {
    // Bridge sync organisasi monitor (pin/kategori) ke server — agar
    // kategori yang dibuat di 1 HP admin muncul di HP admin lain.
    orgGet = _service.getChatOrg;
    orgSet = (pinned, categories, map) => _service.setChatOrg(
      pinned: pinned,
      categories: categories,
      map: map,
    );
    // Muat organisasi monitor chat (pin/kategori) begitu provider dibuat —
    // supaya chip kategori siap walau layar monitor belum sempat initState
    // (TabBarView bisa membuang/membangun ulang layar).
    loadChatOrg();
  }

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
    // Kosongkan state memori supaya UI tidak menampilkan data basi.
    _stats = null;
    _chats = const [];
    _devices = const [];
    _deleted = const [];
    _contactMessages = const [];
    _chatMsgMem.clear();
    _chatMsgHasMore.clear();
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
