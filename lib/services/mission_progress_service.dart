import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils.dart';

/// Service untuk tracking progress misi (dipanggil dari berbagai action di app)
class MissionProgressService {
  final SupabaseClient? _client;

  MissionProgressService({SupabaseClient? client}) : _client = client;

  /// Client di-resolve LAZY (bukan di konstruktor) supaya test yang tidak
  /// menginisialisasi Supabase tetap bisa membuat instance ini.
  SupabaseClient get _sb => _client ?? Supabase.instance.client;

  String? get _userId => _sb.auth.currentUser?.id;

  /// Generic update - dipakai PointsNotifier.trackMission()
  Future<void> updateProgress(String missionKey, {int increment = 1}) async {
    try {
      final uid = _userId;
      if (uid == null) return;
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': missionKey,
        'p_increment': increment,
      });
    } catch (e) {
      // Tracking misi = efek samping non-kritis; jangan sampai melempar
      // ke pemanggil (kirim pesan/like/follow tidak boleh gagal karena ini).
      dlog('[MISSIONS] updateProgress($missionKey) dilewati: $e');
    }
  }

  // ── Durasi Online ──

  /// Dipanggil setiap 30 detik oleh PointsNotifier._checkOnlineMilestones
  Future<void> trackOnlineMinutes(int minutes) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'daily_online_minutes',
        'p_increment': minutes,
      });
    } catch (e) {
      dlog('[MISSIONS] trackOnlineMinutes error: $e');
    }
  }

  /// Dipanggil setiap 30 detik oleh PointsNotifier._checkOnlineMilestones
  Future<void> trackCallMinutes(int minutes) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'call_minutes',
        'p_increment': minutes,
      });
    } catch (e) {
      dlog('[MISSIONS] trackCallMinutes error: $e');
    }
  }

  /// Dipanggil setiap 60 detik untuk misi "Durasi Online Harian"
  Future<void> trackOnlineDuration(int minutes) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'daily_online_duration',
        'p_increment': minutes,
      });
    } catch (e) {
      dlog('[MISSIONS] trackOnlineDuration error: $e');
    }
  }

  // ── Konten ──

  /// Dipanggil saat user mengunggah foto
  Future<void> trackPhotoUpload() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'upload_photos',
        'p_increment': 1,
      });
    } catch (e) {
      dlog('[MISSIONS] trackPhotoUpload error: $e');
    }
  }

  /// Dipanggil saat user membuat postingan
  Future<void> trackPostCreated() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'create_posts',
        'p_increment': 1,
      });
    } catch (e) {
      dlog('[MISSIONS] trackPostCreated error: $e');
    }
  }

  // ── Match/Call ──

  /// Dipanggil saat user menyelesaikan video match
  Future<void> trackMatchCall() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'match_calls',
        'p_increment': 1,
      });
    } catch (e) {
      dlog('[MISSIONS] trackMatchCall error: $e');
    }
  }

  /// Dipanggil saat user panggilan 1:1 (private call)
  Future<void> trackPrivateCall() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'private_calls',
        'p_increment': 1,
      });
    } catch (e) {
      dlog('[MISSIONS] trackPrivateCall error: $e');
    }
  }

  // ── Sosial ──

  /// Dipanggil setiap user kirim pesan ke user berbeda
  Future<void> trackMessageSent() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'message_various_users',
        'p_increment': 1,
      });
    } catch (e) {
      dlog('[MISSIONS] trackMessageSent error: $e');
    }
  }

  /// Dipanggil setiap user tambah teman
  Future<void> trackFriendAdded() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'add_friends_in_call',
        'p_increment': 1,
      });
    } catch (e) {
      dlog('[MISSIONS] trackFriendAdded error: $e');
    }
  }

  /// Dipanggil setiap user balas pesan
  Future<void> trackMessageReply() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'reply_users',
        'p_increment': 1,
      });
    } catch (e) {
      dlog('[MISSIONS] trackMessageReply error: $e');
    }
  }

  /// Dipanggil setiap user like posting
  Future<void> trackPostLiked() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'like_posts',
        'p_increment': 1,
      });
    } catch (e) {
      dlog('[MISSIONS] trackPostLiked error: $e');
    }
  }

  /// Dipanggil setiap user terima hadiah
  Future<void> trackGiftReceived() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'daily_receive_gift',
        'p_increment': 1,
      });
    } catch (e) {
      dlog('[MISSIONS] trackGiftReceived error: $e');
    }
  }

  /// Dipanggil setiap user panggilan match harian
  Future<void> trackDailyMatchCall() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'daily_match_calls',
        'p_increment': 1,
      });
    } catch (e) {
      dlog('[MISSIONS] trackDailyMatchCall error: $e');
    }
  }

  /// Dipanggil setiap user kirim pesan ke user berbeda (daily)
  Future<void> trackDailyMessageSent() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'daily_message_users',
        'p_increment': 1,
      });
    } catch (e) {
      dlog('[MISSIONS] trackDailyMessageSent error: $e');
    }
  }

  /// Dipanggil setiap user total durasi panggilan pribadi (daily)
  Future<void> trackDailyPrivateCallDuration(int minutes) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'daily_private_call_duration',
        'p_increment': minutes,
      });
    } catch (e) {
      dlog('[MISSIONS] trackDailyPrivateCallDuration error: $e');
    }
  }

  /// Dipanggil setiap user online di jam 19:00-23:00
  Future<void> trackEveningOnline(int minutes) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'evening_online_call',
        'p_increment': minutes,
      });
    } catch (e) {
      dlog('[MISSIONS] trackEveningOnline error: $e');
    }
  }

  /// Dipanggil setiap user online di jam 01:00-05:00
  Future<void> trackNightOwlOnline(int minutes) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'night_owl_online_call',
        'p_increment': minutes,
      });
    } catch (e) {
      dlog('[MISSIONS] trackNightOwlOnline error: $e');
    }
  }

  /// Dipanggil setiap user kumpulkan 1000 poin (nyonya_1000)
  Future<void> trackNyonya1000(int coins) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _sb.rpc('update_mission_progress', params: {
        'p_user_id': uid,
        'p_mission_key': 'nyonya_1000',
        'p_increment': coins,
      });
    } catch (e) {
      dlog('[MISSIONS] trackNyonya1000 error: $e');
    }
  }
}
