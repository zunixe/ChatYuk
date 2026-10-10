part of 'admin_service.dart';

// ignore_for_file: unused_element

mixin _AdminOpsMx on _AdminBase {
  Future<Map<String, dynamic>> setAiSettings({
    bool? globalEnabled,
    int? maxReplies,
    int? minInterval,
    bool? guardEnabled,
    bool? aiAiEnabled,
    String? apiBase,
    String? apiKey,
    String? defaultModel,
  }) async {
    final params = <String, dynamic>{
      if (globalEnabled != null) 'p_global_enabled': globalEnabled,
      if (maxReplies != null) 'p_max_replies': maxReplies,
      if (minInterval != null) 'p_min_interval': minInterval,
      if (guardEnabled != null) 'p_guard_enabled': guardEnabled,
      if (aiAiEnabled != null) 'p_ai_ai_enabled': aiAiEnabled,
      if (apiBase != null && apiBase.isNotEmpty) 'p_api_base': apiBase,
      if (apiKey != null && apiKey.isNotEmpty) 'p_api_key': apiKey,
      if (defaultModel != null && defaultModel.isNotEmpty)
        'p_default_model': defaultModel,
    };
    final res = await _rpc('admin_ai_settings', params: params);
    return (res as Map<String, dynamic>?) ?? const {};
  }

  /// Daftar provider AI (id, label, base, key, model, is_active).
  /// Baris legacy 'global' (wadah setting lama, kosong) DISEMBUNYIKAN bila
  /// tidak aktif — itu system row yang di-seed ulang server, bukan provider
  /// sungguhan; menampilkannya hanya membingungkan (dihapus → muncul lagi).
  Future<List<Map<String, dynamic>>> getAiProviders() async {
    final res = await _rpc('admin_ai_provider_list');
    if (res is List) {
      return res
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((p) => '${p['id']}' != 'global' || p['is_active'] == true)
          .toList();
    }
    return const [];
  }

  /// Simpan provider (id kosong = tambah baru, slug otomatis).
  /// Return row tersimpan.
  Future<Map<String, dynamic>> saveAiProvider({
    String? id,
    String? label,
    String? apiBase,
    String? apiKey,
    String? defaultModel,
    String? storyModel,
    String? fallbackModel,
  }) async {
    final res = await _rpc(
      'admin_ai_provider_save',
      params: {
        if (id != null) 'p_id': id,
        if (label != null) 'p_label': label,
        if (apiBase != null) 'p_api_base': apiBase,
        if (apiKey != null) 'p_api_key': apiKey,
        if (defaultModel != null) 'p_default_model': defaultModel,
        if (storyModel != null) 'p_story_model': storyModel,
        if (fallbackModel != null) 'p_fallback_model': fallbackModel,
      },
    );
    return (res as Map<String, dynamic>?) ?? const {};
  }

  /// Hapus provider. Server menolak hapus provider AKTIF kecuali ada
  /// pengganti (failover otomatis di RPC); UI sebaiknya failover dulu
  /// via activateAiProvider supaya UX satu klik.
  Future<void> deleteAiProvider(String id) async {
    await _rpc('admin_ai_provider_delete', params: {'p_id': id});
  }

  /// Aktifkan provider (yang dipakai edge function).
  Future<void> activateAiProvider(String id) async {
    await _rpc('admin_ai_provider_activate', params: {'p_id': id});
  }

  /// Hapus akun dummy + history chat-nya. Return {'ok': bool, 'chats_deleted': int}.
  Future<Map<String, dynamic>> deleteDummy(String uid) async {
    final res = await _rpc('admin_delete_dummy', params: {'p_uid': uid});
    return (res as Map<String, dynamic>?) ?? {};
  }

  // ── Pesan Kontak (Hubungi Kami) ──
  /// List pesan kontak dengan pagination. Return {'total': int, 'items': [...]}.
  Future<Map<String, dynamic>> listContactMessages({
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _rpc(
      'admin_contact_messages_page',
      params: {'p_limit': limit, 'p_offset': offset},
    ).timeout(_openTimeout);
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Tandai pesan terbaca / belum terbaca.
  Future<void> setContactRead(String id, {bool read = true}) async {
    await _rpc('admin_contact_set_read', params: {'p_id': id, 'p_read': read});
  }

  /// Hapus pesan kontak.
  Future<void> deleteContactMessage(String id) async {
    await _rpc('admin_contact_delete', params: {'p_id': id});
  }

  // ── Monitor Grup (private rooms user) ──
  /// Daftar grup privat (paging + search + filter negara).
  /// Return {'total': int, 'items': [...]}.
  Future<Map<String, dynamic>> listPrivateRoomsPage({
    int limit = 50,
    int offset = 0,
    String search = '',
    String country = '',
  }) async {
    final res = await _rpc(
      'admin_list_private_rooms_page',
      params: {
        'p_limit': limit,
        'p_offset': offset,
        'p_search': search,
        'p_country': country,
      },
    ).timeout(_openTimeout);
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Daftar anggota satu grup (JOIN profiles → nickname/gender/avatar).
  Future<List<Map<String, dynamic>>> getRoomMembers(String roomId) async {
    final res = await _rpc(
      'admin_room_members',
      params: {'p_room_id': roomId},
    ).timeout(_openTimeout);
    return res is List ? List<Map<String, dynamic>>.from(res) : const [];
  }

  /// Pesan satu grup (paging, terbaru dulu). Return {'total': int, 'items': [...]}.
  Future<Map<String, dynamic>> getRoomMessagesPage(
    String roomId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _rpc(
      'admin_room_messages_page',
      params: {'p_room_id': roomId, 'p_limit': limit, 'p_offset': offset},
    ).timeout(_openTimeout);
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Ambil image_data satu pesan grup (lazy-load foto; RPC kosongkan di list).
  Future<String> fetchRoomMessageImage(int messageId) async {
    final res = await _rpc(
      'admin_room_message_image',
      params: {'p_message_id': messageId},
    ).timeout(_openTimeout);
    return (res as String?) ?? '';
  }

  /// Hapus room apa pun (admin only). FK cascade membersihkan pesan/anggota.
  Future<void> adminDeleteRoom(String roomId) async {
    await _rpc(
      'admin_delete_room',
      params: {'p_room_id': roomId},
    ).timeout(_openTimeout);
  }

  // ── Popup update aplikasi (app_settings) ──
  /// Baca konfigurasi update. Return null bila gagal.
  Future<Map<String, dynamic>?> getUpdateConfig() async {
    try {
      return await _sb
          .from('app_settings')
          .select('update_enabled,latest_version,min_version,update_notes')
          .eq('id', 'global')
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  /// Simpan konfigurasi update. RLS membatasi tulis ke admin.
  Future<void> saveUpdateConfig({
    required bool enabled,
    required String latestVersion,
    required String minVersion,
    required String notes,
  }) async {
    await _sb.from('app_settings').upsert({
      'id': 'global',
      'update_enabled': enabled,
      'latest_version': latestVersion.trim(),
      'min_version': minVersion.trim(),
      'update_notes': notes.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Push popup update MANUAL: set `app_settings.update_push_at = now()`.
  /// Klien menampilkan popup saat app dibuka bila stempel ini lebih baru
  /// dari push terakhir yang dilihat user. RPC guard admin.
  Future<void> pushUpdate() async {
    await _rpc('admin_push_update');
  }

  /// Waktu push manual terakhir (null bila belum pernah). Dipakai UI admin
  /// untuk menampilkan status "terakhir dikirim ...".
  Future<DateTime?> getUpdatePushAt() async {
    try {
      final row = await _sb
          .from('app_settings')
          .select('update_push_at')
          .eq('id', 'global')
          .maybeSingle();
      final raw = row?['update_push_at'];
      return raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
    } catch (_) {
      return null;
    }
  }

  // ── STORY (tab admin) ──────────────────────────────────────────────

  /// Semua slide story aktif lintas user (moderasi). [filter] ∈
  /// `all|public|followers|friends|private`. Urut terbaru di atas (server).
  Future<List<Map<String, dynamic>>> adminStoryAll({
    String filter = 'all',
    int limit = 200,
  }) async {
    final res = await _rpc(
      'admin_story_all',
      params: {'p_limit': limit, 'p_filter': filter},
    ).timeout(_openTimeout);
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  /// Atur visibilitas satu slide. [state] ∈
  /// `public|followers|friends|private`. Return true bila sukses.
  Future<bool> adminSetStoryVisibility(String storyId, String state) async {
    try {
      final res = await _rpc(
        'admin_set_story_visibility',
        params: {'p_story_id': storyId, 'p_state': state},
      ).timeout(_openTimeout);
      return res is Map && res['ok'] == true;
    } catch (e) {
      dlog('[AdminService] adminSetStoryVisibility error: $e');
      return false;
    }
  }

  /// Hapus PERMANEN slide (moderasi). Return (ok, image_path, video_path)
  /// agar client membersihkan file Storage.
  Future<({bool ok, String imagePath, String videoPath})> adminStoryDelete(
    String storyId,
  ) async {
    try {
      final res = await _rpc(
        'admin_story_delete',
        params: {'p_story_id': storyId},
      ).timeout(_openTimeout);
      if (res is Map && res['ok'] == true) {
        return (
          ok: true,
          imagePath: '${res['image_path'] ?? ''}',
          videoPath: '${res['video_path'] ?? ''}',
        );
      }
      return (ok: false, imagePath: '', videoPath: '');
    } catch (e) {
      dlog('[AdminService] adminStoryDelete error: $e');
      return (ok: false, imagePath: '', videoPath: '');
    }
  }

  // ── Email Marketing ──────────────────────────────────────────

  Future<List<Map<String, dynamic>>> emailCampaignsPage({
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _rpc(
      'admin_email_campaigns_page',
      params: {'p_limit': limit, 'p_offset': offset},
    ).timeout(_openTimeout);
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> emailStats() async {
    final res = await _rpc('admin_email_stats').timeout(_openTimeout);
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  Future<Map<String, dynamic>> emailEstimateSegment(
    Map<String, dynamic> segment,
  ) async {
    final res = await _rpc(
      'admin_email_estimate_segment',
      params: {'p_segment': segment},
    ).timeout(_openTimeout);
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  Future<Map<String, dynamic>> emailCampaignSave({
    int? id,
    required String name,
    required String subject,
    required String html,
    required Map<String, dynamic> segment,
  }) async {
    final res = await _rpc(
      'admin_email_campaign_save',
      params: {
        'p_id': id,
        'p_name': name,
        'p_subject': subject,
        'p_html': html,
        'p_segment': segment,
      },
    ).timeout(_openTimeout);
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  Future<bool> emailCampaignDelete(int id) async {
    try {
      final res = await _rpc(
        'admin_email_campaign_delete',
        params: {'p_id': id},
      ).timeout(_openTimeout);
      return res is Map && res['ok'] == true;
    } catch (e) {
      dlog('[AdminService] emailCampaignDelete error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> emailCampaignDetail(
    int id, {
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await _rpc(
      'admin_email_campaign_detail',
      params: {'p_id': id, 'p_limit': limit, 'p_offset': offset},
    ).timeout(_openTimeout);
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  Future<Map<String, dynamic>> emailEnqueue(int id) async {
    final res = await _rpc(
      'admin_email_enqueue',
      params: {'p_id': id},
    ).timeout(_openTimeout);
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }
}
