import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/story_model.dart';

/// Service story: tray, slide, upload, seen, penonton, hapus, realtime.
class StoryService {
  final SupabaseClient _sb;
  StoryService([SupabaseClient? sb])
      : _sb = sb ?? Supabase.instance.client;

  String? get uid => _sb.auth.currentUser?.id;

  /// Tray story untuk halaman pengguna online (agregat per author).
  Future<List<StoryTrayItem>> fetchTray() async {
    try {
      final res = await _sb.rpc('story_tray');
      if (res is List) {
        return res
            .map((e) =>
                StoryTrayItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[Story] fetchTray error: $e');
      return [];
    }
  }

  /// Semua slide aktif milik satu author (urut terlama → terbaru).
  Future<List<StorySlide>> fetchSlides(String authorId) async {
    try {
      final res = await _sb
          .rpc('story_slides', params: {'p_author': authorId}).timeout(
        const Duration(seconds: 6),
      );
      if (res is List) {
        return res
            .map((e) => StorySlide.fromMap(
                '${(e as Map)['id'] ?? ''}', Map<String, dynamic>.from(e)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[Story] fetchSlides error: $e');
      return [];
    }
  }

  /// Buat slide story baru. Return id slide atau '' kalau gagal.
  Future<String> createStory({
    required String imagePath,
    String textOverlay = '',
    double textX = 0.5,
    double textY = 0.85,
    int textColor = 0,
    int textSize = 1,
    double textScale = 1.0,
    bool textBg = false,
    String visibility = 'registered',
  }) async {
    try {
      final res = await _sb.rpc('create_story', params: {
        'p_image_path': imagePath,
        'p_text_overlay': textOverlay,
        'p_text_x': textX,
        'p_text_y': textY,
        'p_text_color': textColor,
        'p_text_size': textSize,
        'p_text_scale': textScale,
        'p_text_bg': textBg,
        'p_visibility': visibility,
      });
      if (res is Map) return '${res['id'] ?? ''}';
      return '';
    } catch (e) {
      debugPrint('[Story] createStory error: $e');
      return '';
    }
  }

  /// Tandai slide dilihat (idempoten).
  Future<void> markSeen(String storyId) async {
    try {
      await _sb.rpc('mark_story_seen', params: {'p_story_id': storyId});
    } catch (e) {
      debugPrint('[Story] markSeen error: $e');
    }
  }

  /// Daftar penonton slide milik sendiri.
  Future<List<StoryViewer>> fetchViewers(String storyId) async {
    try {
      final res = await _sb
          .rpc('story_viewers', params: {'p_story_id': storyId});
      if (res is List) {
        return res
            .map((e) =>
                StoryViewer.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('[Story] fetchViewers error: $e');
      return [];
    }
  }

  /// Hapus slide milik sendiri. Return image_path untuk hapus file Storage.
  Future<String> deleteStory(String storyId) async {
    try {
      final res = await _sb.rpc('delete_story', params: {
        'p_story_id': storyId,
      });
      if (res is Map) return '${res['image_path'] ?? ''}';
      return '';
    } catch (e) {
      debugPrint('[Story] deleteStory error: $e');
      return '';
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
