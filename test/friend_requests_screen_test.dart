import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/social_provider.dart';
import 'package:chatyuk/providers/theme_provider.dart';
import 'package:chatyuk/screens/friend_requests_screen.dart';
import 'package:chatyuk/services/social_service.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

class MockSocialService extends Mock implements SocialService {}

/// Regresi: Outbox memuat SEMUA riwayat (pending/accepted/rejected), tapi
/// backend `cancel_friend_request` menolak non-pending (`not_pending`).
/// Tombol Batal HANYA boleh tampil untuk baris pending — menampilkannya di
/// baris accepted/rejected = tombol yang pasti gagal (kasus SimpleMe:
/// outbox berisi accepted+rejected, 0 pending).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
    await prewarmMediaForTest();
  });

  Map<String, dynamic> row(int id, String status) => {
        'id': id,
        'uid': 'u-$id',
        'nickname': 'User $id',
        'is_registered': true,
        'status': status,
      };

  Future<void> pump(WidgetTester tester) async {
    final svc = MockSocialService();
    when(() => svc.friendRequestInbox()).thenAnswer((_) async => []);
    when(() => svc.friendRequestOutbox()).thenAnswer(
      (_) async => [row(1, 'pending'), row(2, 'accepted'), row(3, 'rejected')],
    );
    final sp = SocialProvider(
      service: svc,
      sb: fakeSupabaseClientNoTicker(),
      autoInit: false,
    );
    final locale = LocaleProvider();
    final theme = ThemeProvider();
    addTearDown(() {
      sp.dispose();
      locale.dispose();
      theme.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: locale),
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: sp),
        ],
        child: const MaterialApp(home: FriendRequestsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('Batal hanya tampil untuk baris pending', (tester) async {
    await pump(tester);
    final s = LocaleProvider().s;
    // Satu tombol Batal (baris pending) — baris accepted/rejected tidak ada.
    expect(find.widgetWithText(TextButton, s.btnCancel), findsOneWidget);
    // Label status untuk riwayat non-pending.
    expect(find.text(s.friendRequestStatusAccepted), findsOneWidget);
    expect(find.text(s.friendRequestStatusRejected), findsOneWidget);
    // Label "Terkirim" tetap ada untuk baris pending.
    expect(find.text(s.btnFriendRequested), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
