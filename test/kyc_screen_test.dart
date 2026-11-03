import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/providers/riverpod/kyc_provider.dart';
import 'package:chatyuk/screens/kyc_screen.dart';

/// Notifier KYC palsu — `build` mengembalikan status yang diinginkan test
/// tanpa menyentuh Supabase (Supabase.instance tak di-init di test).
class _FakeKyc extends KycNotifier {
  _FakeKyc(this._status, {this.reason});
  final String _status;
  final String? reason;

  @override
  KycState build() => KycState(
        loading: false,
        status: _status,
        rejectReason: reason,
      );
}

void main() {
  // Locale default di test = Indonesia.
  final s = S(isId: true);

  /// Lepas tree sebelum test selesai — timer/sub di layar dibersihkan.
  void disposeAfterTest(WidgetTester tester) {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  }

  Future<void> pump(WidgetTester tester, _FakeKyc fake) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [kycProvider.overrideWith(() => fake)],
        child: const MaterialApp(home: KycScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('status none → tampil form lengkap (intro, doc, foto, submit)',
      (t) async {
    disposeAfterTest(t);
    await pump(t, _FakeKyc('none'));

    expect(find.text(s.kycTitle), findsOneWidget);
    expect(find.text(s.kycDocType), findsOneWidget);
    expect(find.text(s.kycPhotoId), findsOneWidget);
    expect(find.text(s.kycPhotoSelfie), findsOneWidget);
    // Tombol submit jauh di bawah — ListView hanya me-render viewport;
    // scroll dulu sampai terlihat (scrollable eksplisit: ada TextField
    // yang juga scrollable → ambigu tanpa `scrollable:`).
    await t.scrollUntilVisible(
      find.text(s.kycSubmit),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(s.kycSubmit), findsOneWidget);
  });

  testWidgets('status pending → view "Sedang Ditinjau", form disembunyikan',
      (t) async {
    disposeAfterTest(t);
    await pump(t, _FakeKyc('pending'));

    expect(find.text(s.kycPendingTitle), findsOneWidget);
    expect(find.text(s.kycSubmit), findsNothing);
  });

  testWidgets('status approved → view "Terverifikasi"', (t) async {
    disposeAfterTest(t);
    await pump(t, _FakeKyc('approved'));

    expect(find.text(s.kycApprovedTitle), findsOneWidget);
    expect(find.text(s.kycSubmit), findsNothing);
  });

  testWidgets('status rejected → alasan tampil + form resubmit', (t) async {
    disposeAfterTest(t);
    await pump(t, _FakeKyc('rejected', reason: 'foto buram'));

    expect(find.text(s.kycRejectedTitle), findsWidgets);
    expect(find.textContaining('foto buram'), findsOneWidget);
    // Form tetap terlihat untuk kirim ulang — scroll sampai tombolnya.
    await t.scrollUntilVisible(
      find.text(s.kycSubmit),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(s.kycSubmit), findsOneWidget);
  });
}
