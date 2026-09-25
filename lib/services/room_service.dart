import '../utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/room_model.dart';
import '../config/supabase_config.dart';

class RoomService {
  /// Client opsional (LAZY) — test menyuntik client palsu.
  final SupabaseClient? _injected;
  RoomService([SupabaseClient? sb]) : _injected = sb;

  SupabaseClient get _sb => _injected ?? SupabaseConfig.client;

  // Sudah di-seed per negara dalam satu sesi app (session-lifetime).
  // Menghindari upsert berulang tiap kali room list dibuka.
  static final Set<String> _seededCountries = {};

  // rooms TIDAK di-enable realtime di DB (error RealtimeSubscribeException),
  // jadi pakai fetch langsung, bukan .stream().
  // Kolom rooms yang boleh di-select (password_hash sengaja dikecualikan —
  // di DB kolom itu di-revoke dari client).
  static const _roomCols =
      'id,name,description,icon,country,category,is_private,owner_id,owner_name,has_password,expires_at,created_at';

  Future<List<RoomModel>> fetchRooms(String country) async {
    // Seed sekali per negara (upsert idempotent) agar semua kategori lengkap
    // walaupun sebagian room sudah ada (mis. hasil tes/insert manual).
    await seedCountryRooms(country);
    final rows = await _sb
        .from('rooms')
        .select(_roomCols)
        .eq('country', country)
        .eq('is_private', false)
        .order('order')
        .limit(200);
    return rows.map((row) => RoomModel.fromMap('${row['id']}', row)).toList();
  }

  /// Buat/lengkapi room kategori untuk satu negara via RPC security definer.
  /// RLS rooms INSERT/UPDATE dibatasi admin (hardening) — seeding lewat
  /// RPC agar user biasa tetap bisa memunculkan room saat app dibuka.
  /// Hanya dijalankan sekali per negara per sesi app.
  Future<void> seedCountryRooms(String country) async {
    if (country.isEmpty) return;
    if (_seededCountries.contains(country)) return;
    await _sb.rpc('seed_rooms', params: {'p_country': country});
    _seededCountries.add(country);
  }

  Future<void> updateOnlineCount(String roomId, int count) async {
    // Online count dihitung dari room_presence — tidak perlu simpan, tapi pertahankan API.
    dlog(
      '[room] updateOnlineCount deprecation: roomId=$roomId count=$count',
    );
  }

  // ── Private Rooms ──

  /// Bersihkan room private kedaluwarsa (dipanggil saat buka lobby).
  Future<void> cleanupExpired() async {
    try {
      await _sb.rpc('cleanup_expired_rooms');
    } catch (e) {
      dlog('[room] cleanupExpired error: $e');
    }
  }

  /// Ambil private room untuk satu negara (yang belum kedaluwarsa).
  Future<List<RoomModel>> fetchPrivateRooms(String country) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = await _sb
        .from('rooms')
        .select(_roomCols)
        .eq('country', country)
        .eq('is_private', true)
        // Grup tanpa password = permanen (expires_at NULL) — jangan
        // difilter keluar seperti grup expired.
        .or('expires_at.is.null,expires_at.gt.$nowIso')
        .order('created_at', ascending: false)
        .limit(200);
    return rows.map((row) => RoomModel.fromMap('${row['id']}', row)).toList();
  }

  /// Room mana saja yang sudah jadi member (lolos password / owner).
  Future<Set<String>> fetchMyMemberships(String uid) async {
    try {
      final rows = await _sb
          .from('room_members')
          .select('room_id')
          .eq('user_id', uid)
          .limit(500);
      return rows.map((r) => '${r['room_id']}').toSet();
    } catch (e) {
      dlog('[room] fetchMyMemberships error: $e');
      return {};
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // PEMISAH GLOBAL vs GRUP — baca sebelum nambah cara bikin room baru.
  //   GLOBAL ROOM (tab Global Room): is_private=false, chat terbuka tanpa
  //     anggota/password, kelola via admin panel. Dibuat via createGlobalRoom
  //     (GRATIS, kategori ASLI, TANPA param password — server juga memaksa).
  //   GRUP (tab Grup, legacy 'private'): is_private=true + room_members +
  //     BISA password/approval. Dibuat via createPrivateRoom (bayar poin).
  // JANGAN: bikin room kategori lewat createPrivateRoom + password, atau
  // menampilkan grup private di explore (lihat list_room_explore).
  // ═══════════════════════════════════════════════════════════════════

  /// Buat GLOBAL room dalam kategori (GRATIS, terbuka, tanpa password).
  /// Return {id, points, join_token}. Lempar PostgrestException bila gagal.
  /// icon: emoji ATAU path storage `room-icons/<uid>/...` (upload dulu
  /// via StoragePhotoService.uploadRoomIcon).
  Future<Map<String, dynamic>> createGlobalRoom({
    required String name,
    required String icon,
    required String country,
    required String category,
  }) async {
    final res = await _sb.rpc(
      'create_private_room',
      params: {
        'p_name': name,
        'p_icon': icon,
        'p_country': country,
        'p_category': category,
      },
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Buat GRUP legacy (private + room_members, BISA password, BAYAR poin).
  /// JANGAN dipakai untuk room kategori — pakai createGlobalRoom.
  /// Return {id, points}. Lempar PostgrestException bila gagal.
  Future<Map<String, dynamic>> createPrivateRoom({
    required String name,
    required String icon,
    required String country,
    String? password,
  }) async {
    final res = await _sb.rpc(
      'create_private_room',
      params: {
        'p_name': name,
        'p_icon': icon,
        'p_country': country,
        'p_password': password,
      },
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Satu list explore (global + grup) beserta statistik untuk negara.
  /// Return list map mentah (snake_case) — mapping ke RoomModel di provider
  /// via snakeToCamel agar konsisten dengan chat_stream_session.
  Future<List<Map<String, dynamic>>> fetchExplore(String country) async {
    try {
      final res = await _sb.rpc(
        'list_room_explore',
        params: {'p_country': country},
      );
      if (res is List) {
        return res
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return const [];
    } catch (e) {
      dlog('[room] fetchExplore error: $e');
      return const [];
    }
  }

  /// Tandai room sudah dibaca (unread sync antar-device).
  Future<void> markRoomRead(String roomId) async {
    try {
      await _sb.rpc('mark_room_read', params: {'p_room_id': roomId});
    } catch (e) {
      dlog('[room] markRoomRead error: $e');
    }
  }

  /// Masuk private room. Return {ok, charged, points}.
  Future<Map<String, dynamic>> joinPrivateRoom(
    String roomId, {
    String? password,
  }) async {
    final res = await _sb.rpc(
      'join_private_room',
      params: {'p_room_id': roomId, 'p_password': password},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Perpanjang masa aktif room. Return {ok, points, expires_at}.
  Future<Map<String, dynamic>> extendRoom(String roomId) async {
    final res = await _sb.rpc(
      'extend_private_room',
      params: {'p_room_id': roomId},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  Future<void> deleteRoom(String roomId) async {
    await _sb.rpc('delete_private_room', params: {'p_room_id': roomId});
  }

  Future<Map<String, dynamic>> resetRoomPassword(String roomId, String? newPassword) async {
    final res = await _sb.rpc('reset_room_password', params: {'p_room_id': roomId, 'p_new_password': newPassword});
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Stream realtime perubahan tabel rooms (khusus private room) untuk
  /// negara tertentu. Dipakai supaya penghapusan/pembuatan room langsung
  /// tersinkron di semua device tanpa reload manual. Mengembalikan daftar
  /// private room terbaru setiap ada perubahan.
  Stream<List<RoomModel>> watchPrivateRooms(String country) {
    // Filter di SERVER (dulu tarik SELURUH tabel rooms lintas-negara lalu
    // filter di Dart → payload besar + realtime kirim ulang semua baris).
    return _sb
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('country', country)
        .eq('is_private', true)
        .map((rows) {
      final now = DateTime.now().toUtc();
      return rows
          .where(
            (row) =>
                row['expires_at'] != null &&
                DateTime.tryParse('${row['expires_at']}')?.isAfter(now) == true,
          )
          .map((row) => RoomModel.fromMap('${row['id']}', row))
          .toList()
        ..sort((a, b) {
          final ax = a.expiresAt;
          final bx = b.expiresAt;
          if (ax == null || bx == null) return 0;
          return bx.compareTo(ax);
        });
    });
  }

  /// Ambil satu room by id (untuk private room flow).
  Future<Map<String, dynamic>?> fetchRoomById(String roomId) async {
    try {
      final row = await _sb
          .from('rooms')
          .select(
              'id,name,description,icon,country,category,is_private,owner_id,owner_name,has_password,expires_at,created_at,live_uid,live_started_at,max_members')
          .eq('id', roomId)
          .maybeSingle();
      return row;
    } catch (e) {
      dlog('[room] fetchRoomById error: $e');
      return null;
    }
  }

  /// Batch: 1 query `in` untuk banyak room sekaligus (ganti N+1 fetchRoomById).
  Future<List<Map<String, dynamic>>> fetchRoomsByIds(
      List<String> roomIds) async {
    if (roomIds.isEmpty) return const [];
    try {
      final rows = await _sb
          .from('rooms')
          .select(
              'id,name,description,icon,country,category,is_private,owner_id,owner_name,has_password,expires_at,created_at,live_uid,live_started_at,max_members')
          .inFilter('id', roomIds);
      return ((rows as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      dlog('[room] fetchRoomsByIds error: $e');
      return const [];
    }
  }
}