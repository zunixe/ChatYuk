import 'dart:async';
import 'dart:typed_data';

import '../utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/story_model.dart';
import '../core/perf/perf_probe.dart';

/// Service story: tray, slide, upload, seen, penonton, hapus, realtime.
class StoryService {
  final SupabaseClient _sb;
  StoryService([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  String? get uid => _sb.auth.currentUser?.id;

  /// Tray story untuk halaman pengguna online (agregat per author).
  Future<List<StoryTrayItem>> fetchTray() async {
    try {
      final res = await PerfProbe.timed(
        'story.tray',
        () => _sb.rpc('story_tray'),
      );
      if (res is List) {
        return res
            .map(
              (e) => StoryTrayItem.fromMap(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      }
      return [];
    } catch (e) {
      dlog('[Story] fetchTray error: $e');
      return [];
    }
  }

  /// Semua slide aktif milik satu author (urut terlama → terbaru).
  Future<List<StorySlide>> fetchSlides(String authorId) async {
    try {
      final res = await PerfProbe.timed(
        'story.slides',
        () => _sb
            .rpc('story_slides', params: {'p_author': authorId})
            .timeout(const Duration(seconds: 6)),
      );
      if (res is List) {
        return res
            .map(
              (e) => StorySlide.fromMap(
                '${(e as Map)['id'] ?? ''}',
                Map<String, dynamic>.from(e),
              ),
            )
            .toList();
      }
      return [];
    } catch (e) {
      dlog('[Story] fetchSlides error: $e');
      return [];
    }
  }

  /// Buat slide story baru. Return id slide atau '' kalau gagal.
  /// `imagePath` WAJIB path storage `story/...` — base64/full-data
  /// ditolak di sini supaya tidak masuk kolom `stories.image_path`
  /// (viewer hanya download path; base64 boros DB).
  /// Video: kirim `videoPath` + `durationMs` (1-15 dtk); imagePath boleh
  /// string kosong (kolom image_path nullable di insert video).
  Future<String> createStory({
    required String imagePath,
    String textOverlay = '',
    double textX = 0.5,
    double textY = 0.85,
    int textColor = 0,
    int textSize = 1,
    double textScale = 1.0,
    bool textBg = false,
    String visibility = 'followers',
    String videoPath = '',
    int durationMs = 0,
  }) async {
    final isVideo = videoPath.isNotEmpty;
    if (!isVideo && !imagePath.startsWith('story/')) {
      dlog('[Story] createStory ditolak: imagePath bukan story/ path');
      return '';
    }
    if (isVideo && !videoPath.startsWith('story/')) {
      dlog('[Story] createStory ditolak: videoPath bukan story/ path');
      return '';
    }
    try {
      final res = await _sb.rpc(
        'create_story',
        params: {
          'p_image_path': imagePath,
          'p_text_overlay': textOverlay,
          'p_text_x': textX,
          'p_text_y': textY,
          'p_text_color': textColor,
          'p_text_size': textSize,
          'p_text_scale': textScale,
          'p_text_bg': textBg,
          'p_visibility': visibility,
          if (isVideo) 'p_media_type': 'video',
          if (isVideo) 'p_video_path': videoPath,
          if (isVideo) 'p_duration_ms': durationMs,
        },
      );
      if (res is Map) return '${res['id'] ?? ''}';
      return '';
    } catch (e) {
      dlog('[Story] createStory error: $e');
      return '';
    }
  }

  /// Unduh bytes video story (untuk VideoPlayer file). Null bila gagal.
  Future<Uint8List?> downloadVideo(String videoPath) async {
    try {
      final bytes = await _sb.storage
          .from('chat-photos')
          .download(videoPath)
          .timeout(const Duration(seconds: 30));
      if (bytes.isEmpty) return null;
      return bytes;
    } catch (e) {
      dlog('[Story] downloadVideo error: $e');
      return null;
    }
  }

  /// Tandai slide dilihat (idempoten).
  Future<void> markSeen(String storyId) async {
    try {
      await _sb.rpc('mark_story_seen', params: {'p_story_id': storyId});
    } catch (e) {
      dlog('[Story] markSeen error: $e');
    }
  }

  /// Bisukan / buka bisu story author (idempoten). Return false bila gagal.
  Future<bool> setStoryMuted(String authorId, bool muted) async {
    try {
      await _sb.rpc(
        muted ? 'mute_story_author' : 'unmute_story_author',
        params: {'p_author': authorId},
      ).timeout(const Duration(seconds: 15));
      return true;
    } catch (e) {
      dlog('[Story] setStoryMuted error: $e');
      return false;
    }
  }

  /// Tandai BANYAK slide sekaligus dalam satu round-trip (idempoten).
  /// Dipakai viewer: kumpulkan id slide yang benar-benar ditonton, kirim
  /// sekali saat keluar viewer / ganti author — dulu 1 RPC per slide.
  Future<void> markSeenBulk(List<String> storyIds) async {
    if (storyIds.isEmpty) return;
    PerfProbe.notifyCount('story.markSeenBulk');
    try {
      await _sb
          .rpc('mark_story_seen_bulk', params: {'p_ids': storyIds})
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      dlog('[Story] markSeenBulk error: $e');
      // Fallback: tandai satu-satu supaya ring tetap akurat walau RPC bulk
      // belum ter-apply di server (deploy belum jalan).
      for (final id in storyIds) {
        try {
          await _sb.rpc('mark_story_seen', params: {'p_story_id': id});
        } catch (_) {}
      }
    }
  }

  /// Toggle like satu slide. Return (liked, count) — null kalau gagal.
  Future<(bool, int)?> toggleLike(String storyId) async {
    try {
      final res = await _sb
          .rpc('toggle_story_like', params: {'p_story_id': storyId})
          .timeout(const Duration(seconds: 8));
      if (res is Map && res['ok'] == true) {
        return (res['liked'] == true, (res['count'] as num?)?.toInt() ?? 0);
      }
      return null;
    } catch (e) {
      dlog('[Story] toggleLike error: $e');
      return null;
    }
  }

  /// Daftar penonton slide (pemilik slide atau admin).
  ///
  /// Return `null` bila GAGAL (RPC error/unauthorized/network) dan `[]` bila
  /// benar-benar tak ada penonton. Dulu keduanya sama-sama `[]` sehingga
  /// kegagalan (mis. admin tanpa guard) menyamar jadi "belum ada penonton".
  Future<List<StoryViewer>?> fetchViewers(String storyId) async {
    try {
      // Timeout WAJIB: tanpa ini tap ikon mata saat jaringan stall
      // menggantung selamanya (sheet tak kunjung buka → dikira hang).
      // Timeout → null → UI tampil "gagal memuat" + bisa coba lagi.
      final res = await _sb
          .rpc('story_viewers', params: {'p_story_id': storyId})
          .timeout(const Duration(seconds: 10));
      if (res is List) {
        return res
            .map(
              (e) => StoryViewer.fromMap(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      }
      return const <StoryViewer>[];
    } catch (e) {
      dlog('[Story] fetchViewers error: $e');
      return null;
    }
  }

  /// Hapus slide milik sendiri. Return image_path untuk hapus file Storage.
  Future<({bool ok, String path})> deleteStory(String storyId) async {
    try {
      final res = await _sb.rpc(
        'delete_story',
        params: {'p_story_id': storyId},
      );
      // Sukses ditandai `ok` (bukan dari image_path — slide VIDEO punya
      // image_path poster/kosong sehingga dulu dianggap gagal padahal
      // terhapus). `path` untuk pembersihan file.
      if (res is Map && res['ok'] == true) {
        return (ok: true, path: '${res['image_path'] ?? ''}');
      }
      return (ok: false, path: '');
    } catch (e) {
      dlog('[Story] deleteStory error: $e');
      return (ok: false, path: '');
    }
  }

  /// Realtime perubahan stories (insert = slide baru, delete = slide habis).
  /// Provider cukup refresh tray — payload tak perlu detail.
  Stream<String> watchStories() {
    final controller = StreamController<String>.broadcast();
    final channel = _sb.channel('stories-realtime');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'stories',
      callback: (payload) {
        if (!controller.isClosed) controller.add(payload.eventType.name);
      },
    );
    channel.subscribe();
    controller.onCancel = () {
      _sb.removeChannel(channel);
    };
    return controller.stream;
  }

  /// Realtime story_views — untuk update ring "sudah dilihat" live.
  Stream<String> watchStoryViews() {
    final controller = StreamController<String>.broadcast();
    final channel = _sb.channel('story-views-realtime');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'story_views',
      callback: (payload) {
        if (!controller.isClosed) controller.add('insert');
      },
    );
    channel.subscribe();
    controller.onCancel = () {
      _sb.removeChannel(channel);
    };
    return controller.stream;
  }
}
