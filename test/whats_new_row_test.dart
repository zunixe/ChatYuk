import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/models/auth_data.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/screens/timeline/widgets/whats_new_row.dart';
import 'package:chatyuk/services/auth_service.dart';

import 'test_helper.dart';

class _MockAuthService extends Mock implements AuthService {}

class _TestAuth extends AuthNotifier {
  _TestAuth(AuthService svc) : super(authService: svc);
  @override
  AuthData build() => const AuthData(uid: 'me', loading: false);
}

/// Baris "Apa yang baru?" di atas Timeline (ala Threads) → tap buka composer.
void main() {
  setUpAll(() async {
    await initSupabaseForTest();
    await prewarmMediaForTest();
  });

  testWidgets('tampil placeholder & tap memanggil onTap', (t) async {
    var taps = 0;
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _TestAuth(_MockAuthService())),
      ],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: WhatsNewRow(onTap: () => taps++)),
        ),
      ),
    );
    await t.pump();
    final hint = find.text("What's new?").evaluate().isNotEmpty
        ? find.text("What's new?")
        : find.text('Apa yang baru?');
    expect(hint, findsOneWidget);
    await t.tap(hint);
    expect(taps, 1);
  });
}
