import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/message_reaction_service.dart';

void main() {
  group('parseCachedReactions', () {
    test('format normal lolos apa adanya', () {
      final out = MessageReactionService.parseCachedReactions({
        'm1': {'👍': 2, '❤️': 1},
        'm2': {'😂': 3},
      });
      expect(out, {
        'm1': {'👍': 2, '❤️': 1},
        'm2': {'😂': 3},
      });
    });

    test('entri rusak dibuang, yang sehat dipertahankan', () {
      final out = MessageReactionService.parseCachedReactions({
        'm1': {'👍': 0, '': 5, '❤️': 'dua'},
        'm2': 'bukan-map',
        '': {'👍': 1},
        'm3': {'😂': 1},
      });
      expect(out, {
        'm3': {'😂': 1},
      });
    });

    test('angka string ikut diparse', () {
      final out = MessageReactionService.parseCachedReactions({
        'm1': {'👍': '4'},
      });
      expect(out, {
        'm1': {'👍': 4},
      });
    });

    test('cache key per chat', () {
      expect(
        MessageReactionService.reactionCacheKey('abc'),
        'reactions:abc',
      );
    });
  });
}
