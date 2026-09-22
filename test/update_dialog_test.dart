import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/update_provider.dart';
import 'package:chatyuk/services/app_update_service.dart';
import 'package:chatyuk/widgets/update_dialog.dart';

/// Widget hermetic `UpdateDialog`: memastikan judul/isi/tombol memakai
/// string bilingual & mengikuti fase provider (available/downloading/
/// readyToInstall/non-Play/force).
void main() {
  final s = S(isId: true);

  Widget wrap(UpdateProvider provider) => MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleProvider>(
            create: (_) => LocaleProvider(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showUpdateDialog(ctx, provider),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  UpdateProvider makeProvider({bool fromPlay = true, bool force = false}) {
    final p = UpdateProvider(service: AppUpdateService.forTest())
      ..setFromPlayForTest(fromPlay)
      ..setForceForTest(force);
    return p;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugResetUpdateDialogGuard();
  });

  testWidgets('fase available → judul + versi + notes + tombol Update/Nanti',
      (tester) async {
    final svc = AppUpdateService.forTest()
      ..debugPolicyOverride = const UpdatePolicy(
        enabled: true,
        latestVersion: '1.2.48',
        minVersion: '',
        notes: 'Perbaikan bug',
      )
      ..debugLocalVersionOverride = (version: '1.2.47', buildNumber: 47)
      ..debugPlayAvailabilityOverride = PlayAvailability.available;
    final p2 = UpdateProvider(service: svc);
    await p2.check();

    await tester.pumpWidget(wrap(p2));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(s.updateTitle), findsOneWidget);
    expect(find.textContaining('1.2.48'), findsWidgets);
    expect(find.text(s.updateNotesLabel), findsOneWidget);
    expect(find.text('Perbaikan bug'), findsOneWidget);
    expect(find.text(s.btnUpdateNow), findsOneWidget);
    expect(find.text(s.btnUpdateLater), findsOneWidget);
  });

  testWidgets('force → judul wajib + TANPA tombol Nanti', (tester) async {
    final svc = AppUpdateService.forTest()
      ..debugPolicyOverride = const UpdatePolicy(
        enabled: true,
        latestVersion: '1.2.48',
        minVersion: '1.2.47', // local 1.2.40 < min → force
        notes: '',
      )
      ..debugLocalVersionOverride = (version: '1.2.40', buildNumber: 40)
      ..debugPlayAvailabilityOverride = PlayAvailability.available;
    final p = UpdateProvider(service: svc);
    await p.check();
    expect(p.force, isTrue);

    await tester.pumpWidget(wrap(p));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(s.updateRequiredTitle), findsOneWidget);
    expect(find.text(s.btnUpdateNow), findsOneWidget);
    expect(find.text(s.btnUpdateLater), findsNothing);
  });

  testWidgets('non-Play → tombol Buka Google Play', (tester) async {
    final svc = AppUpdateService.forTest()
      ..debugPolicyOverride = const UpdatePolicy(
        enabled: true,
        latestVersion: '1.2.48',
        minVersion: '',
        notes: '',
      )
      ..debugLocalVersionOverride = (version: '1.2.47', buildNumber: 47)
      ..debugPlayAvailabilityOverride = PlayAvailability.notFromPlay;
    final p = UpdateProvider(service: svc);
    await p.check();
    expect(p.fromPlay, isFalse);

    await tester.pumpWidget(wrap(p));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(s.btnOpenStore), findsOneWidget);
    expect(find.text(s.updateOpenStoreMsg), findsOneWidget);
  });

  testWidgets('fase downloading → progress indicator + teks unduh',
      (tester) async {
    final p = makeProvider();
    p.setPhaseForTest(UpdatePhase.downloading);

    await tester.pumpWidget(wrap(p));
    await tester.tap(find.text('open'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(s.updatePreparing), findsOneWidget);
  });

  testWidgets('fase readyToInstall → tombol restart', (tester) async {
    final p = makeProvider();
    p.setPhaseForTest(UpdatePhase.readyToInstall);

    await tester.pumpWidget(wrap(p));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(s.btnUpdateRestart), findsOneWidget);
  });

  testWidgets('fase idle → dialog langsung menutup (SizedBox kosong)',
      (tester) async {
    final p = makeProvider();
    p.setPhaseForTest(UpdatePhase.idle);

    await tester.pumpWidget(wrap(p));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tidak ada elemen dialog yang tersisa.
    expect(find.text(s.updateTitle), findsNothing);
    expect(find.text(s.btnUpdateNow), findsNothing);
  });
}
