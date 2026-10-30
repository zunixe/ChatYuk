import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/random_match.dart';

/// Kontrak model fitur Random Video Call (parsing payload server).
void main() {
  test('RandomRadarUser: label jarak < 1km, 1 desimal, fallback kota', () {
    RandomRadarUser u(double? d, {String city = 'Bandung'}) => RandomRadarUser(
      uid: 'u1',
      nickname: 'A',
      city: city,
      distanceKm: d,
    );
    expect(u(0.4).distanceLabel, '<1km');
    expect(u(3.44).distanceLabel, '3.4km');
    // Tanpa lokasi → jangan tampilkan angka palsu, pakai kota.
    expect(u(null).distanceLabel, 'Bandung');
    expect(u(null, city: '').distanceLabel, '');
  });

  test('RandomRadarUser.tryParse: uid kosong → null', () {
    expect(RandomRadarUser.tryParse({'nickname': 'x'}), isNull);
    expect(RandomRadarUser.tryParse(null), isNull);
    expect(RandomRadarUser.tryParse({'uid': 'u1'})?.nickname, 'User');
  });

  test('RandomPartner.tryParse: field opsional aman', () {
    final p = RandomPartner.tryParse({'uid': 'u2', 'nickname': 'Rina'});
    expect(p?.uid, 'u2');
    expect(p?.age, isNull);
    expect(p?.distanceKm, isNull);
    final q = RandomPartner.tryParse({
      'uid': 'u3',
      'age': 21,
      'distance_km': 2,
    });
    expect(q?.age, 21);
    expect(q?.distanceKm, 2.0);
  });

  test('RandomCallEntry.tryParse: durasi, status, online', () {
    final e = RandomCallEntry.tryParse({
      'call_id': 'c1',
      'partner_id': 'u2',
      'partner_name': 'Rina',
      'partner_gender': 'female',
      'partner_age': 22,
      'started_at': '2026-10-30T03:00:00Z',
      'ended_at': '2026-10-30T03:00:20Z',
      'duration_sec': 20,
      'online': true,
      'status': 'ended',
    });
    expect(e, isNotNull);
    expect(e!.durationSec, 20);
    expect(e.isMissed, isFalse);
    expect(e.online, isTrue);
    expect(e.partnerAge, 22);
    expect(e.startedAt.isUtc, isFalse, reason: 'diparse ke waktu lokal');
  });

  test('RandomCallEntry: durasi 0 = tidak tersambung', () {
    final e = RandomCallEntry.tryParse({
      'call_id': 'c2',
      'partner_id': 'u2',
      'partner_name': 'Rina',
      'duration_sec': 0,
      'status': 'ended',
    });
    expect(e!.isMissed, isTrue);
  });

  test('RandomCallEntry.tryParse: call_id kosong → null', () {
    expect(RandomCallEntry.tryParse({'partner_id': 'u2'}), isNull);
  });
}
