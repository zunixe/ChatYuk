import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/admin/admin_grouping.dart';
import 'package:chatyuk/utils.dart';

/// Fase D — logika bersama (murni): grouping device admin + matchesQuery.
void main() {
  group('groupByDevice', () {
    Map<String, dynamic> row(
      String install,
      String uid,
      String nick, {
      String seen = '2026-01-01T00:00:00Z',
    }) =>
        {
          'install_id': install,
          'user_id': uid,
          'nickname': nick,
          'brand': 'Xiaomi',
          'model': 'M1',
          'last_seen_at': seen,
        };

    test('kelompokkan per install_id, dedupe user (uid|nick)', () {
      final out = groupByDevice([
        row('d1', 'u1', 'Budi'),
        row('d1', 'u1', 'Budi'), // dobel -> di-dedupe
        row('d1', 'u2', 'Siti'),
        row('d2', 'u3', 'Andi'),
      ]);
      expect(out.length, 2);
      final d1 = out.firstWhere((g) => g['install_id'] == 'd1');
      expect((d1['users'] as List).length, 2);
      // uid sama tapi nick beda -> dianggap user berbeda (snapshot berubah).
      final out2 = groupByDevice([row('d1', 'u1', 'Budi'), row('d1', 'u1', 'Budi2')]);
      expect((out2.first['users'] as List).length, 2);
    });

    test('install_id kosong dilewati', () {
      final out = groupByDevice([row('', 'u1', 'X')]);
      expect(out, isEmpty);
    });

    test('last_seen grup = baris terbaru; urut desc', () {
      final out = groupByDevice([
        row('d1', 'u1', 'A', seen: '2026-01-01T00:00:00Z'),
        row('d1', 'u2', 'B', seen: '2026-02-01T00:00:00Z'),
        row('d2', 'u3', 'C', seen: '2026-03-01T00:00:00Z'),
      ]);
      expect(out.first['install_id'], 'd2');
      final d1 = out.firstWhere((g) => g['install_id'] == 'd1');
      expect(d1['last_seen_at'], '2026-02-01T00:00:00Z');
    });
  });

  group('filterDeviceGroups', () {
    final groups = [
      {
        'install_id': 'd1',
        'brand': 'Xiaomi',
        'model': 'Redmi',
        'users': [
          {'user_id': 'u1', 'nickname': 'Budi'},
        ],
      },
    ];

    test('query kosong -> semua', () {
      expect(filterDeviceGroups(groups, '  '), groups);
    });

    test('cocok brand/model/install_id', () {
      expect(filterDeviceGroups(groups, 'xiaomi').length, 1);
      expect(filterDeviceGroups(groups, 'redmi').length, 1);
      expect(filterDeviceGroups(groups, 'd1').length, 1);
    });

    test('cocok user di dalam grup', () {
      expect(filterDeviceGroups(groups, 'budi').length, 1);
      expect(filterDeviceGroups(groups, 'u1').length, 1);
    });

    test('tidak cocok -> kosong', () {
      expect(filterDeviceGroups(groups, 'zzz'), isEmpty);
    });
  });

  group('matchesQuery', () {
    final m = {'nickname': 'Budi Santoso', 'email': 'Budi@Mail.com', 'n': 7};

    test('kosong -> true', () => expect(matchesQuery(m, '', const ['nickname']), isTrue));
    test('case-insensitive', () => expect(matchesQuery(m, 'BUDI', const ['email']), isTrue));
    test('cocok salah satu field', () => expect(matchesQuery(m, 'santo', const ['email', 'nickname']), isTrue));
    test('angka jadi string', () => expect(matchesQuery(m, '7', const ['n']), isTrue));
    test('tak cocok', () => expect(matchesQuery(m, 'xyz', const ['nickname', 'email']), isFalse));
    test('field null tidak crash', () => expect(matchesQuery({'a': null}, 'x', const ['a']), isFalse));
  });
}
