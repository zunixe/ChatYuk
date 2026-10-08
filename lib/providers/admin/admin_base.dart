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

  /// Client untuk channel realtime monitor (dipakai layar chat + polling
  /// call). Produksi = `Supabase.instance.client`; test menyuntik mock
  /// supaya tidak ada socket/timer sungguhan.
  SupabaseClient get realtimeClient => _sb;

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
  // Seed sekali: fetchDevices pertama SETELAH arm menjadi baseline diam-diam
  // (pengganti fetch limit-1000 di armNotifications — hemat 1 RPC besar
  // tiap buka panel). Device baru selalu muncul di atas (ORDER BY last_seen
  // desc), jadi halaman-1 cukup sebagai baseline.
  bool _seedDone = false;
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
  static const kAdminAttributionKey = 'admin_attribution';
  static const kAdminRoomsKey = 'admin_rooms';
  static String adminDummyKey(String myUid) => 'admin_dummy_$myUid';
  static String adminChatMsgKey(String chatId) => 'admin_chatmsg_$chatId';
  static String adminRoomMsgKey(String roomId) => 'admin_roommsg_$roomId';

  /// Kunci cache yang dibersihkan tombol "Bersihkan cache admin".
  static const List<String> adminCacheKeys = [
    kAdminStatsKey,
    kAdminChatsKey,
    kAdminDevicesKey,
    kAdminDeletedKey,
    kAdminContactKey,
    kAdminAttributionKey,
    kAdminRoomsKey,
  ];

  // ── Revision counter per-domain (granular rebuild) ──
  // AdminProvider adalah SATU ChangeNotifier untuk semua domain. Tanpa
  // pemisahan, setiap notifyListeners() (60 titik, termasuk polling 60 dtk &
  // realtime call) me-rebuild SELURUH panel + semua tab yang sudah dibangun →
  // jank tak stabil saat buka tab berat (Perangkat/Terhapus/Chat).
  //
  // Tiap domain menaikkan counter-nya sendiri SEBELUM notifyListeners().
  // Tab memakai `ref.watch(adminProvider.select((p) => p.revXxx))` sehingga
  // HANYA rebuild saat domain-nya berubah — bukan saat domain lain berubah.
  int _revStats = 0;
  int _revDevices = 0;
  int _revChats = 0;
  int _revDeleted = 0;
  int _revContact = 0;
  int _revAttribution = 0;
  int _revChatOrg = 0;
  int _revCalls = 0;
  int _revStories = 0;
  int _revMarketing = 0;
  int _revRooms = 0;

  int get revStats => _revStats;
  int get revDevices => _revDevices;
  int get revChats => _revChats;
  int get revDeleted => _revDeleted;
  int get revContact => _revContact;
  int get revAttribution => _revAttribution;
  int get revChatOrg => _revChatOrg;
  int get revCalls => _revCalls;
  int get revStories => _revStories;
  int get revMarketing => _revMarketing;
  int get revRooms => _revRooms;

  /// Bump counter domain + notify. `domain` dipilih dari helper di bawah.
  void _bumpAndNotify(void Function() bump) {
    if (_disposed) return;
    bump();
    notifyListeners();
  }

  void _notifyStats() => _bumpAndNotify(() => _revStats++);
  void _notifyDevices() => _bumpAndNotify(() => _revDevices++);
  void _notifyChats() => _bumpAndNotify(() => _revChats++);
  void _notifyDeleted() => _bumpAndNotify(() => _revDeleted++);
  void _notifyContact() => _bumpAndNotify(() => _revContact++);
  void _notifyAttribution() => _bumpAndNotify(() => _revAttribution++);
  void _notifyChatOrg() => _bumpAndNotify(() => _revChatOrg++);
  void _notifyCalls() => _bumpAndNotify(() => _revCalls++);
  void _notifyStories() => _bumpAndNotify(() => _revStories++);
  void _notifyMarketing() => _bumpAndNotify(() => _revMarketing++);
  void _notifyRooms() => _bumpAndNotify(() => _revRooms++);
}
