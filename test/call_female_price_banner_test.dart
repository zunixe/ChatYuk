import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/services/call/call_session.dart';
import 'test_helper.dart';

/// Female penelepon private = GRATIS (server call_billing_tick) → banner
/// tarif "N YukCoin/menit" tidak boleh muncul; male tetap muncul.
void main() {
  setUpAll(() async => initSupabaseForTest());

  CallSession mk(String gender) => CallSession(
    callId: 'c1',
    remoteUid: 'u1',
    remoteName: 'Budi',
    callType: 'video',
    isCaller: true,
    myGender: gender,
  );

  test('female: tarif per menit diabaikan (0)', () {
    final s = mk('female')..setBillingPerMinute(20);
    expect(s.isBillingPayer, isTrue);
    expect(s.billingPerMinute, 0);
  });

  test('male: tarif per menit tampil', () {
    final s = mk('male')..setBillingPerMinute(20);
    expect(s.billingPerMinute, 20);
  });

  test('popup koin habis female: tanpa ajakan top-up', () {
    for (final isId in [true, false]) {
      final s = S(isId: isId);
      final body = s.pointsOutOfCoinBodyFemale.toLowerCase();
      expect(body.contains('top-up sekarang'), isFalse);
      expect(body.contains('top up now'), isFalse);
      expect(s.pointsOutOfCoinBody.toLowerCase().contains('top'), isTrue);
    }
  });
}
