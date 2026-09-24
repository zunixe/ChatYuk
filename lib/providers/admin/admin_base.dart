part of '../admin_provider.dart';

/// State instance BERSAMA lintas domain admin.
///
/// Mixin per-domain (file `part`) mengaksesnya — satu library via `part`,
/// jadi sah, dan interface `AdminProvider` tidak berubah (mock test aman).
/// Pola sama dengan `ChatBase` di `services/chat_service.dart`.
abstract class AdminBase extends ChangeNotifier {
  /// Service disuntik dari luar (default produksi) — pola sama dengan
  /// `ChatProvider`/`RoomProvider`. Test: `AdminProvider(service: mock)`.
  final AdminService _service;

  /// Client Supabase untuk realtime monitor (bisa disuntik di test).
  /// LAZY: tidak menyentuh `Supabase.instance` saat konstruksi.
  final SupabaseClient? _injectedSb;
  SupabaseClient get _sb => _injectedSb ?? Supabase.instance.client;

  AdminBase({AdminService? service, SupabaseClient? sb})
      : _service = service ?? AdminService(),
        _injectedSb = sb;

  bool _disposed = false;

  // ── Notifikasi admin (device baru / call video aktif) ──
  // State di base (bukan mixin notif) supaya mixin devices & calls bisa
  // memakai _emit/_seen* langsung — member antar-mixin TIDAK saling
  // terlihat (hanya member sendiri + base), jadi state bersama wajib di base.
  final StreamController<String> _notifCtrl =
      StreamController<String>.broadcast();
  final Set<String> _seenDeviceIds = {};
  final Set<String> _seenCallIds = {};
  bool _notifArmed = false;
  bool _seenDevicesLoaded = false;
  static const String _kSeenDevicesKey = 'admin_seen_device_ids';

  void _emit(String msg) {
    if (_disposed) return;
    try {
      if (!_notifCtrl.isClosed) _notifCtrl.add(msg);
    } catch (_) {}
  }

  Future<void> _persistSeenDevice(String installId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kSeenDevicesKey) ?? <String>[];
      if (!list.contains(installId)) {
        list.add(installId);
        // Batasi ukuran list (simpan 500 terbaru).
        while (list.length > 500) {
          list.removeAt(0);
        }
        await prefs.setStringList(_kSeenDevicesKey, list);
      }
    } catch (_) {}
  }

  // ── Cache disk data admin ──
  // Data admin disimpan terenkripsi (MessageCache → SQLCipher + Keystore)
  // supaya saat OFFLINE panel tetap menampilkan data terakhir, bukan layar
  // error. Kunci `admin_*` supaya tombol "bersihkan cache admin" bisa
  // menghapusnya selektif (lihat clearAdminCache()).
  static const kAdminStatsKey = 'admin_stats';
  static const kAdminChatsKey = 'admin_chats';
  static const kAdminDevicesKey = 'admin_devices';
  static const kAdminDeletedKey = 'admin_deleted';
  static const kAdminContactKey = 'admin_contact';
  static String adminDummyKey(String myUid) => 'admin_dummy_$myUid';
  static String adminChatMsgKey(String chatId) => 'admin_chatmsg_$chatId';

  /// Kunci cache yang dibersihkan tombol "Bersihkan cache admin".
  static const List<String> adminCacheKeys = [
    kAdminStatsKey,
    kAdminChatsKey,
    kAdminDevicesKey,
    kAdminDeletedKey,
    kAdminContactKey,
  ];
}
