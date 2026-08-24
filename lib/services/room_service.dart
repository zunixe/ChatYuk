import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/room_model.dart';
import '../config/supabase_config.dart';

/// Kategori room yang sama dipakai untuk SETIAP negara.
const List<Map<String, String>> roomCategories = [
  {'id': 'general', 'name': 'General', 'icon': '💬', 'desc': 'Chat umum'},
  {'id': 'curhat', 'name': 'Curhat', 'icon': '💭', 'desc': 'Cerita & curhat'},
  {
    'id': 'pertemanan',
    'name': 'Pertemanan',
    'icon': '🤝',
    'desc': 'Cari teman baru',
  },
  {
    'id': 'teknologi',
    'name': 'Teknologi',
    'icon': '💻',
    'desc': 'Diskusi tech',
  },
  {'id': 'gaming', 'name': 'Gaming', 'icon': '🎮', 'desc': 'Main & bahas game'},
  {'id': 'musik', 'name': 'Musik', 'icon': '🎵', 'desc': 'Sharing musik'},
  {'id': 'film', 'name': 'Film & TV', 'icon': '🎬', 'desc': 'Review film'},
  {'id': 'joke', 'name': 'Joke & Meme', 'icon': '😂', 'desc': 'Bikin ngakak'},
  {'id': 'belajar', 'name': 'Belajar', 'icon': '📚', 'desc': 'Diskusi belajar'},
  {'id': 'flirt', 'name': 'Flirt', 'icon': '💘', 'desc': 'Ngobrol asyik'},
];

class RoomService {
  final SupabaseClient _sb = SupabaseConfig.client;

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
        .order('order');
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
    debugPrint(
      '[room] updateOnlineCount deprecation: roomId=$roomId count=$count',
    );
  }

  // ── Private Rooms ──

  /// Bersihkan room private kedaluwarsa (dipanggil saat buka lobby).
  Future<void> cleanupExpired() async {
    try {
      await _sb.rpc('cleanup_expired_rooms');
    } catch (e) {
      debugPrint('[room] cleanupExpired error: $e');
    }
  }

  /// Ambil private room untuk satu negara (yang belum kedaluwarsa).
  Future<List<RoomModel>> fetchPrivateRooms(String country) async {
    final rows = await _sb
        .from('rooms')
        .select(_roomCols)
        .eq('country', country)
        .eq('is_private', true)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false);
    return rows.map((row) => RoomModel.fromMap('${row['id']}', row)).toList();
  }

  /// Room mana saja yang sudah jadi member (lolos password / owner).
  Future<Set<String>> fetchMyMemberships(String uid) async {
    try {
      final rows = await _sb
          .from('room_members')
          .select('room_id')
          .eq('user_id', uid);
      return rows.map((r) => '${r['room_id']}').toSet();
    } catch (e) {
      debugPrint('[room] fetchMyMemberships error: $e');
      return {};
    }
  }

  /// Buat private room. Return {id, points}. Lempar PostgrestException bila gagal.
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

  /// Stream realtime perubahan tabel rooms (khusus private room) untuk
  /// negara tertentu. Dipakai supaya penghapusan/pembuatan room langsung
  /// tersinkron di semua device tanpa reload manual. Mengembalikan daftar
  /// private room terbaru setiap ada perubahan.
  Stream<List<RoomModel>> watchPrivateRooms(String country) {
    return _sb.from('rooms').stream(primaryKey: ['id']).map((rows) {
      final now = DateTime.now().toUtc();
      return rows
          .where(
            (row) =>
                row['is_private'] == true &&
                row['country'] == country &&
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
}
