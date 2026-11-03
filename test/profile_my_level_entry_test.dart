import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regresi: My Level hanya untuk MALE + badge level di user_info.
/// - Entry menu My Level di profil di-gate `!isAnon && gender == 'male'`
///   (female/dummy tidak melihat — dummy = female).
/// - Badge `Lv.X` di user_info hanya bila level > 0 (levelShort).
/// - Semua teks lewat `s.*` (bilingual — tanpa hardcode).
void main() {
  final ui = File('lib/screens/profile/profile_ui.dart').readAsStringSync();
  final entry = File(
    'lib/screens/profile/widgets/my_level_entry.dart',
  ).readAsStringSync();
  final build = File('lib/screens/user_info/user_info_build.dart')
      .readAsStringSync();
  final body = File('lib/screens/user_info/profile_preview_body.dart')
      .readAsStringSync();
  final strings = File('lib/config/strings_points_mx.dart').readAsStringSync();

  test('entry My Level di-gate male-only (bukan anon)', () {
    final a = ui.indexOf('// Menu My Level');
    expect(a, greaterThanOrEqualTo(0));
    final blok = ui.substring(a, ui.indexOf('// Menu Saldo & Misi'));
    expect(blok, contains("!isAnon && profile?.gender == 'male'"));
    expect(blok, contains('MyLevelEntryCard'));
    // Navigasi ke layar My Level (di dalam kartu entry).
    expect(entry, contains('MyLevelScreen'));
    expect(entry, contains('myLevelProvider'));
  });

  test('badge level user_info hanya tampil bila level > 0', () {
    expect(build, contains('_levelBadge'));
    expect(build, contains('userLevelProvider'));
    expect(build, contains('if (lv <= 0) return const SizedBox.shrink();'));
    // Badge di-pass ke _PProfileBody (bukan digambar di mixin).
    expect(body, contains('levelBadge'));
    expect(body, contains('widget.levelBadge'));
  });

  test('string My Level bilingual (isId ? … : …)', () {
    expect(strings, contains("isId ? 'Level Saya' : 'My Level'"));
    expect(strings, contains("isId ? 'Keistimewaan' : 'Privileges'"));
    expect(strings, contains("isId ? 'Aturan Level' : 'Level Rule'"));
    expect(strings, contains("isId ? 'Badge Level' : 'Level Badge'"));
    expect(strings, contains("isId ? 'Bonus Koin' : 'Coin Bonus'"));
  });

  test('reward level masuk bucket bonus (non-withdrawable) di SQL', () {
    final sql = File(
      'supabase/migrations/20261101130000_my_level.sql',
    ).readAsStringSync();
    expect(sql, contains("ledger_credit(me, 'bonus', 'level_reward'"));
    expect(sql, contains("bucket = 'topup' and amount > 0"));
    expect(sql, contains("v_gender = 'male'"));
    expect(sql, contains('reward_granted_level'));
  });
}
