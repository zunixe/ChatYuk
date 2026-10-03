import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/leaderboard_sheet.dart';

/// Mengunci kontrak CACHE Top Aktif — akar keluhan "tiap buka Top Aktif
/// selalu loading". Sheet menyimpan hasil per-scope supaya buka ulang &
/// ganti tab instan (tanpa RPC ulang), dengan TTL 60 dtk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LeaderboardSheet.clearCacheForTest());
  tearDown(() => LeaderboardSheet.clearCacheForTest());

  group('LeaderboardSheet cache — anti "selalu loading"', () {
    test('awal tanpa cache (buka pertama memang loading)', () {
      expect(LeaderboardSheet.hasCacheFor('weekly'), isFalse);
      expect(LeaderboardSheet.hasCacheFor('alltime'), isFalse);
    });

    test('seed cache → terdeteksi ada (buka ulang instan)', () {
      LeaderboardSheet.seedCacheForTest(
        'weekly',
        entries: [
          {'uid': 'u1', 'nickname': 'A'},
        ],
      );
      expect(LeaderboardSheet.hasCacheFor('weekly'), isTrue);
      expect(LeaderboardSheet.hasCacheFor('alltime'), isFalse,
          reason: 'cache terpisah per-scope');
    });

    test('cache per-scope terpisah (weekly vs alltime)', () {
      LeaderboardSheet.seedCacheForTest('weekly', entries: []);
      LeaderboardSheet.seedCacheForTest('alltime', entries: []);
      expect(LeaderboardSheet.hasCacheFor('weekly'), isTrue);
      expect(LeaderboardSheet.hasCacheFor('alltime'), isTrue);
    });

    test('TTL fresh = 60 dtk', () {
      expect(LeaderboardSheet.cacheFreshTtl, const Duration(seconds: 60));
    });

    test('clear mengosongkan semua (test hygiene)', () {
      LeaderboardSheet.seedCacheForTest('weekly', entries: []);
      LeaderboardSheet.clearCacheForTest();
      expect(LeaderboardSheet.hasCacheFor('weekly'), isFalse);
    });
  });
}
