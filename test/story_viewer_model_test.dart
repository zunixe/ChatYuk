import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/story_model.dart';

/// Model penonton story — kontrak parsing RPC `story_viewers`.
///
/// Dulu tak ada test sama sekali, padahal `liked`/`viewed_at` dipakai UI
/// (ikon hati + waktu relatif). Perubahan guard server (admin bebas) tidak
/// mengubah bentuk payload, jadi kontrak ini yang dikunci.
void main() {
  group('StoryViewer.fromMap — field lengkap', () {
    test('memetakan semua field', () {
      final v = StoryViewer.fromMap({
        'viewer_id': 'u-1',
        'nickname': 'Budi',
        'avatar': 'avatar/u-1.jpg',
        'viewed_at': '2026-09-23T10:15:00.000Z',
        'liked': true,
      });

      expect(v.viewerId, 'u-1');
      expect(v.nickname, 'Budi');
      expect(v.avatar, 'avatar/u-1.jpg');
      expect(v.liked, isTrue);
      expect(v.viewedAt.toUtc().toIso8601String(), '2026-09-23T10:15:00.000Z');
    });
  });

  group('StoryViewer.fromMap — nilai hilang/null', () {
    test('map kosong → nilai aman, tidak throw', () {
      final v = StoryViewer.fromMap(const {});
      expect(v.viewerId, '');
      expect(v.nickname, '?');
      expect(v.avatar, '');
      expect(v.liked, isFalse);
    });

    test('liked hanya true kalau benar-benar true', () {
      expect(StoryViewer.fromMap({'liked': false}).liked, isFalse);
      expect(StoryViewer.fromMap({'liked': 1}).liked, isFalse);
      expect(StoryViewer.fromMap({'liked': 'true'}).liked, isFalse);
      expect(StoryViewer.fromMap({'liked': true}).liked, isTrue);
    });

    test('avatar null → string kosong (bukan "null")', () {
      final v = StoryViewer.fromMap({'avatar': null});
      expect(v.avatar, '');
    });

    test('viewer_id angka dikonversi ke string', () {
      final v = StoryViewer.fromMap({'viewer_id': 42});
      expect(v.viewerId, '42');
    });
  });

  group('StoryViewer — default constructor', () {
    test('avatar default kosong, liked default false', () {
      final v = StoryViewer(
        viewerId: 'u-9',
        nickname: 'Sari',
        viewedAt: DateTime.utc(2026, 9, 23),
      );
      expect(v.avatar, '');
      expect(v.liked, isFalse);
    });
  });

  group('StorySlide video', () {
    test('fromMap baca media_type/video_path/duration_ms', () {
      final s = StorySlide.fromMap('v1', {
        'author_id': 'a',
        'media_type': 'video',
        'video_path': 'story/a/v.mp4',
        'duration_ms': 8000,
        'created_at': '2026-09-26T00:00:00Z',
      });
      expect(s.isVideo, isTrue);
      expect(s.videoPath, 'story/a/v.mp4');
      expect(s.durationMs, 8000);
    });

    test('default image tanpa video', () {
      final s = StorySlide.fromMap('i1', {
        'author_id': 'a',
        'created_at': '2026-09-26T00:00:00Z',
      });
      expect(s.isVideo, isFalse);
      expect(s.mediaType, 'image');
    });

    test('copyWith pertahankan field video', () {
      final s = StorySlide(
        id: 'v1',
        authorId: 'a',
        authorName: 'A',
        imagePath: '',
        createdAt: DateTime.utc(2026, 9, 26),
        mediaType: 'video',
        videoPath: 'story/a/v.mp4',
        durationMs: 8000,
      );
      final c = s.copyWith(liked: true);
      expect(c.isVideo, isTrue);
      expect(c.videoPath, 'story/a/v.mp4');
      expect(c.liked, isTrue);
    });
  });

  group('StoryTrayItem video', () {
    test('fromMap baca has_video + copyWith', () {
      final t = StoryTrayItem.fromMap(
          {'author_id': 'a', 'has_video': true});
      expect(t.hasVideo, isTrue);
      expect(t.copyWith(hasVideo: false).hasVideo, isFalse);
      expect(StoryTrayItem.fromMap({'author_id': 'a'}).hasVideo, isFalse);
    });
  });
}
