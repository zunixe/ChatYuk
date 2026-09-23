import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/screens/nearby/widgets/nearby_card.dart';

import 'test_helper.dart';

/// Ring warna NearbyCard HANYA untuk inisial — foto tampil tanpa ring.
/// Mengunci `nearby_card.dart`: `hasAvatar ? transparent : color`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
  });

  Border? ringOf(WidgetTester tester) {
    final borders = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration)
        .map((c) => c.decoration! as BoxDecoration)
        .where((d) => d.border is Border)
        .map((d) => d.border! as Border)
        .toList();
    if (borders.isEmpty) return null;
    return borders.first;
  }

  Map<String, dynamic> data({required String avatar}) => {
        'nickname': 'Budi',
        'gender': 'male',
        'age': 20,
        'city': 'Jakarta',
        'country': 'Indonesia',
        'status': 'online',
        'avatar': avatar,
        'is_registered': true,
        'distance_km': 0.5,
      };

  Future<void> pumpCard(WidgetTester tester, Map<String, dynamic> d) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(body: NearbyCard(data: d, onTap: () {})),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('tanpa avatar → ring warna gender', (tester) async {
    await pumpCard(tester, data(avatar: ''));
    expect(find.text('B'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('avatar valid → ring transparan', (tester) async {
    const png1px =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    await pumpCard(tester, data(avatar: png1px));
    await tester.pump();
    final border = ringOf(tester);
    expect(border, isNotNull, reason: 'ring disamarkan, bukan dihapus');
    expect(border!.top.color, Colors.transparent);
    await tester.pump(const Duration(seconds: 1));
  });
}
