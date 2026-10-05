import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;

import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/riverpod/social_provider.dart';
import 'package:chatyuk/providers/theme_provider.dart';
import 'package:chatyuk/screens/friend_requests_screen.dart';
import 'package:chatyuk/services/social_service.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

class MockSocialService extends Mock implements SocialService {}

class TestSocial extends SocialNotifier {
  final List<Map<String, dynamic>> inbox;
  final List<Map<String, dynamic>> outbox;
  TestSocial({this.inbox = const [], this.outbox = const []});
  @override
  SocialState build() => const SocialState();
  @override
  Future<List<Map<String, dynamic>>> friendRequestInbox(
          {int limit = 50, int offset = 0}) async =>
      inbox;
  @override
  Future<List<Map<String, dynamic>>> friendRequestOutbox(
          {int limit = 50, int offset = 0}) async =>
      outbox;
}

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
    final outbox = [row(1, 'pending'), row(2, 'accepted'), row(3, 'rejected')];
    final container = ProviderContainer(
      overrides: [socialProvider.overrideWith(() => TestSocial(outbox: outbox))],
    );
    final locale = LocaleProvider();
    final theme = ThemeProvider();
    addTearDown(() {
      locale.dispose();
      theme.dispose();
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: locale),
            ChangeNotifierProvider.value(value: theme),
          ],
          child: const MaterialApp(home: FriendRequestsScreen()),
        ),
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
