import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/message_reaction_service.dart';

void main() {
  group('parseCachedStarred', () {
    test('wrapper {ids:[...]} dibaca apa adanya', () {
      final out = MessageReactionService.parseCachedStarred({
        'ids': ['m1', 'm2', 'm3'],
      });
      expect(out, {'m1', 'm2', 'm3'});
    });

    test('id kosong dibuang, duplikat disatukan (Set)', () {
      final out = MessageReactionService.parseCachedStarred({
        'ids': ['m1', '', 'm1', 'm2'],
      });
      expect(out, {'m1', 'm2'});
    });

    test('format rusak / tanpa ids → kosong (defensif)', () {
      expect(MessageReactionService.parseCachedStarred({}), isEmpty);
      expect(MessageReactionService.parseCachedStarred({'ids': 'bukan-list'}), isEmpty);
      expect(MessageReactionService.parseCachedStarred({'ids': null}), isEmpty);
    });

    test('cache key per chat', () {
      expect(MessageReactionService.starredCacheKey('abc'), 'starred:abc');
    });
  });
}
