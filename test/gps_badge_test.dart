import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/screens/admin_devices/widgets/gps_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Badge status lokasi di daftar user admin "Per User".
void main() {
  Future<void> pumpBadge(
    WidgetTester tester,
    Map<String, dynamic> device,
  ) async {
    final s = S(isId: true);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GpsBadge(device: device, s: s))),
    );
  }

  testWidgets('Fake GPS tampil bila location_mocked', (tester) async {
    await pumpBadge(tester, {
      'location_mocked': true,
      'location_mock_reason': 'shared_coord',
      'lat_gps': -6.9,
    });
    expect(find.textContaining('Fake GPS'), findsOneWidget);
    expect(find.textContaining('shared_coord'), findsOneWidget);
  });

  testWidgets('GPS asli tampil bila ada lat_gps tanpa flag', (tester) async {
    await pumpBadge(tester, {'lat_gps': -6.2, 'loc_source': 'gps'});
    expect(find.text('GPS asli'), findsOneWidget);
  });

  testWidgets('Hanya IP bila tanpa GPS', (tester) async {
    await pumpBadge(tester, {'loc_source': 'ip'});
    expect(find.text('Hanya IP'), findsOneWidget);
  });

  testWidgets('tidak tampil bila tanpa data lokasi', (tester) async {
    await pumpBadge(tester, const {});
    expect(find.byType(GpsBadge), findsOneWidget);
    expect(find.text('GPS asli'), findsNothing);
    expect(find.textContaining('Fake GPS'), findsNothing);
    expect(find.text('Hanya IP'), findsNothing);
  });
}
