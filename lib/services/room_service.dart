import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/room_model.dart';
import '../config/supabase_config.dart';

class RoomService {
  final SupabaseClient _sb = SupabaseConfig.client;

  // rooms TIDAK di-enable realtime di DB (error RealtimeSubscribeException),
  // jadi pakai fetch langsung, bukan .stream().
  Future<List<RoomModel>> fetchRooms() async {
    final rows = await _sb.from('rooms').select().order('order');
    return rows
        .map((row) => RoomModel.fromMap('${row['id']}', row))
        .toList();
  }

  Future<void> seedDefaultRooms() async {
    // Rooms di-seed langsung dari schema.sql — method ini dibiarkan no-op.
  }

  Future<void> updateOnlineCount(String roomId, int count) async {
    // Online count dihitung dari room_presence — tidak perlu simpan terpisah.
  }
}
