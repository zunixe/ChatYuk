import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/room_model.dart';
import '../config/supabase_config.dart';

/// Kategori room yang sama dipakai untuk SETIAP negara.
const List<Map<String, String>> roomCategories = [
  {'id': 'general', 'name': 'General', 'icon': '💬', 'desc': 'Chat umum'},
  {'id': 'curhat', 'name': 'Curhat', 'icon': '💭', 'desc': 'Cerita & curhat'},
  {'id': 'pertemanan', 'name': 'Pertemanan', 'icon': '🤝', 'desc': 'Cari teman baru'},
  {'id': 'teknologi', 'name': 'Teknologi', 'icon': '💻', 'desc': 'Diskusi tech'},
  {'id': 'gaming', 'name': 'Gaming', 'icon': '🎮', 'desc': 'Main & bahas game'},
  {'id': 'musik', 'name': 'Musik', 'icon': '🎵', 'desc': 'Sharing musik'},
  {'id': 'film', 'name': 'Film & TV', 'icon': '🎬', 'desc': 'Review film'},
  {'id': 'joke', 'name': 'Joke & Meme', 'icon': '😂', 'desc': 'Bikin ngakak'},
  {'id': 'belajar', 'name': 'Belajar', 'icon': '📚', 'desc': 'Diskusi belajar'},
  {'id': 'flirt', 'name': 'Flirt', 'icon': '💘', 'desc': 'Ngobrol asyik'},
];

class RoomService {
  final SupabaseClient _sb = SupabaseConfig.client;

  // rooms TIDAK di-enable realtime di DB (error RealtimeSubscribeException),
  // jadi pakai fetch langsung, bukan .stream().
  Future<List<RoomModel>> fetchRooms(String country) async {
    var rows = await _sb
        .from('rooms')
        .select()
        .eq('country', country)
        .order('order');
    if (rows.isEmpty) {
      await seedCountryRooms(country);
      rows = await _sb
          .from('rooms')
          .select()
          .eq('country', country)
          .order('order');
    }
    return rows
        .map((row) => RoomModel.fromMap('${row['id']}', row))
        .toList();
  }

  /// Buat/lengkapi room kategori untuk satu negara (id = '<negara>_<kategori>').
  Future<void> seedCountryRooms(String country) async {
    if (country.isEmpty) return;
    final rows = [
      for (int i = 0; i < roomCategories.length; i++)
        {
          'id': '${country}_${roomCategories[i]['id']}',
          'name': roomCategories[i]['name']!,
          'description': roomCategories[i]['desc']!,
          'icon': roomCategories[i]['icon']!,
          'country': country,
          'category': roomCategories[i]['id']!,
          'order': i + 1,
        },
    ];
    await _sb.from('rooms').upsert(rows, onConflict: 'id');
  }

  Future<void> updateOnlineCount(String roomId, int count) async {
    // Online count dihitung dari room_presence — tidak perlu simpan terpisah.
  }
}