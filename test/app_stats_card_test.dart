import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/screens/admin_panel/widgets/app_stats_card.dart';

void main() {
  group('AdminAppStatsCard.versionFromScaled', () {
    test('decode major.minor.patch', () {
      expect(AdminAppStatsCard.versionFromScaled(10260), '1.2.60');
      expect(AdminAppStatsCard.versionFromScaled(10261), '1.2.61');
      expect(AdminAppStatsCard.versionFromScaled(10059), '1.0.59');
    });

    test('patch dua digit & satu digit', () {
      expect(AdminAppStatsCard.versionFromScaled(10000), '1.0.0');
      expect(AdminAppStatsCard.versionFromScaled(10209), '1.2.9');
    });

    test('nilai tidak valid → -', () {
      expect(AdminAppStatsCard.versionFromScaled(0), '-');
      expect(AdminAppStatsCard.versionFromScaled(-5), '-');
    });

    test('versi besar', () {
      expect(AdminAppStatsCard.versionFromScaled(20500), '2.5.0');
      expect(AdminAppStatsCard.versionFromScaled(31234), '3.12.34');
    });
  });
}
