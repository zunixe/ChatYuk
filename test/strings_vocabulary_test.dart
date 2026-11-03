import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/config/strings_admin.dart';

/// Konsistensi kosakata mata uang (diputuskan 2026-10-31): SEMUA string
/// user-facing untuk mata uang memakai "YukCoin" — bukan "Poin"/"Koin".
/// Test ini menjaga getter koin agar tak kembali memakai istilah lama.
///
/// Daftar getter = daftar eksplisit — tambahkan saat string koin baru dibuat.
void main() {
  // Getter yang WAJIB menyebut mata uang → harus 'YukCoin' di kedua bahasa.
  // Format: (label, fungsi ID, fungsi EN).
  final cases = <String, (String Function(S), String Function(S))>{
    'pointsBalance': ((s) => s.pointsBalance, (s) => s.pointsBalance),
    'outOfPointsTitle': ((s) => s.outOfPointsTitle, (s) => s.outOfPointsTitle),
    'pointsAnonymousLose': (
      (s) => s.pointsAnonymousLose,
      (s) => s.pointsAnonymousLose
    ),
    'pointsDeduct(5)': ((s) => s.pointsDeduct(5), (s) => s.pointsDeduct(5)),
    'pointsGain(5,x)': (
      (s) => s.pointsGain(5, 'x'),
      (s) => s.pointsGain(5, 'x')
    ),
    'pointsStreakToast(3,5)': (
      (s) => s.pointsStreakToast(3, 5),
      (s) => s.pointsStreakToast(3, 5)
    ),
    'pointHistoryTitle': (
      (s) => s.pointHistoryTitle,
      (s) => s.pointHistoryTitle
    ),
    'pointHistoryAdminReset': (
      (s) => s.pointHistoryAdminReset,
      (s) => s.pointHistoryAdminReset
    ),

    'pointHistoryOther': (
      (s) => s.pointHistoryOther,
      (s) => s.pointHistoryOther
    ),
    'yukcoinEarnTopup': (
      (s) => s.yukcoinEarnTopup,
      (s) => s.yukcoinEarnTopup
    ),
    'yukcoinPerMin': ((s) => s.yukcoinPerMin, (s) => s.yukcoinPerMin),
    'yukcoinPickPackage': (
      (s) => s.yukcoinPickPackage,
      (s) => s.yukcoinPickPackage
    ),
    'pointsOutOfCoinBody': (
      (s) => s.pointsOutOfCoinBody,
      (s) => s.pointsOutOfCoinBody
    ),
    'pointsOnboardCoinTitle': (
      (s) => s.pointsOnboardCoinTitle,
      (s) => s.pointsOnboardCoinTitle
    ),
    'pointsOnboardCoinBody': (
      (s) => s.pointsOnboardCoinBody,
      (s) => s.pointsOnboardCoinBody
    ),
    'pointsOnboardCallFree': (
      (s) => s.pointsOnboardCallFree,
      (s) => s.pointsOnboardCallFree
    ),
    'callCostPerMin(6)': (
      (s) => s.callCostPerMin(6),
      (s) => s.callCostPerMin(6)
    ),
    'callEndedNoCoin': (
      (s) => s.callEndedNoCoin,
      (s) => s.callEndedNoCoin
    ),
    'callNeedCoinTitle': (
      (s) => s.callNeedCoinTitle,
      (s) => s.callNeedCoinTitle
    ),
    'callNeedCoinBody(10)': (
      (s) => s.callNeedCoinBody(10),
      (s) => s.callNeedCoinBody(10)
    ),
    'wdAmountLabel': ((s) => s.wdAmountLabel, (s) => s.wdAmountLabel),
    'wdAmountHint(2000)': (
      (s) => s.wdAmountHint(2000),
      (s) => s.wdAmountHint(2000)
    ),
    'wdCalcGross': ((s) => s.wdCalcGross, (s) => s.wdCalcGross),
    'randomNeedCoinTitle': (
      (s) => s.randomNeedCoinTitle,
      (s) => s.randomNeedCoinTitle
    ),
    'randomNeedCoinBody(2)': (
      (s) => s.randomNeedCoinBody(2),
      (s) => s.randomNeedCoinBody(2)
    ),
    'callNoCoinTitle': ((s) => s.callNoCoinTitle, (s) => s.callNoCoinTitle),
    'callNoCoinBody(6)': (
      (s) => s.callNoCoinBody(6),
      (s) => s.callNoCoinBody(6)
    ),

    'callNoCoinStillEmpty': (
      (s) => s.callNoCoinStillEmpty,
      (s) => s.callNoCoinStillEmpty
    ),
    'previewCoin': ((s) => s.previewCoin, (s) => s.previewCoin),
    // Admin (masih string user-facing — panel admin bilingual juga).
    'adminCoinAmount(9)': (
      (s) => s.adminCoinAmount(9),
      (s) => s.adminCoinAmount(9)
    ),
    'adminPointTab': ((s) => s.adminPointTab, (s) => s.adminPointTab),
    'adminWithdrawCoins': (
      (s) => s.adminWithdrawCoins,
      (s) => s.adminWithdrawCoins
    ),
    'adminWithdrawSummaryCoins': (
      (s) => s.adminWithdrawSummaryCoins,
      (s) => s.adminWithdrawSummaryCoins
    ),
    'adminWithdrawRate': (
      (s) => s.adminWithdrawRate,
      (s) => s.adminWithdrawRate
    ),
    'adminWithdrawMinCoins': (
      (s) => s.adminWithdrawMinCoins,
      (s) => s.adminWithdrawMinCoins
    ),
    'adminPointFieldLabel(withdraw_min_coins)': (
      (s) => s.adminPointFieldLabel('withdraw_min_coins'),
      (s) => s.adminPointFieldLabel('withdraw_min_coins')
    ),
    'adminPointFieldLabel(call_audio_cost_per_min)': (
      (s) => s.adminPointFieldLabel('call_audio_cost_per_min'),
      (s) => s.adminPointFieldLabel('call_audio_cost_per_min')
    ),
  };

  // Getter yang labelnya AKSI (bukan nama mata uang) — EN boleh tak
  // menyebut 'YukCoin', tapi tetap DILARANG pakai 'Poin'/'Koin'.
  final allowedNoCoin = <String, (String Function(S), String Function(S))>{
    'callNoCoinTopup': ((s) => s.callNoCoinTopup, (s) => s.callNoCoinTopup),
    'pointHistoryTopup': (
      (s) => s.pointHistoryTopup,
      (s) => s.pointHistoryTopup
    ),
  };

  // Regex mata uang lama: kata utuh 'poin'/'koin' (kapital atau tidak).
  // \b melindungi 'YukCoin' (huru f 'C' di dalam kata tak dihitung batas).
  final banned = RegExp(r'\b[Pp]oin\b|\b[Kk]oin\b');

  final sId = S(isId: true);
  final sEn = S(isId: false);

  for (final entry in cases.entries) {
    test('${entry.key} → YukCoin (ID)', () {
      final text = entry.value.$1(sId);
      expect(text, contains('YukCoin'), reason: 'ID: "$text"');
      expect(banned.hasMatch(text), isFalse, reason: 'ID: "$text"');
    });
    test('${entry.key} → YukCoin (EN)', () {
      final text = entry.value.$2(sEn);
      expect(text, contains('YukCoin'), reason: 'EN: "$text"');
      expect(banned.hasMatch(text), isFalse, reason: 'EN: "$text"');
    });
  }

  for (final entry in allowedNoCoin.entries) {
    test('${entry.key} → tanpa istilah lama (ID+EN)', () {
      expect(banned.hasMatch(entry.value.$1(sId)), isFalse,
          reason: 'ID: "${entry.value.$1(sId)}"');
      expect(banned.hasMatch(entry.value.$2(sEn)), isFalse,
          reason: 'EN: "${entry.value.$2(sEn)}"');
    });
  }

  test('copy charge-on-match: fee dipotong saat dapat match (bukan klik)',
      () {
    // Regresi copy: setelah charge-on-match, body dialog tak boleh lagi
    // bilang koin dipotong "untuk mulai mencari".
    final id = sId.randomNeedCoinBody(2);
    final en = sEn.randomNeedCoinBody(2);
    expect(id, isNot(contains('untuk mulai mencari')));
    expect(id, contains('dapat pasangan'));
    expect(en.toLowerCase(), contains('when you get a match'));
  });
}
