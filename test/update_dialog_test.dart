import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/update_provider.dart';
import 'package:chatyuk/services/app_update_service.dart';
import 'package:chatyuk/widgets/update_dialog.dart';

/// Fake Play Core hermetic — plugin asli TIDAK boleh dipanggil di widget
/// test (channel `de.ffuf.in_app_update` tanpa mock menggantung test).
class _FakePlayClient implements AppUpdateClient {
  bool flexibleStarted = false;
  bool flexibleCompleted = false;
  final controller = StreamController<InstallStatus>.broadcast();

  @override
  Future<AppUpdateInfo> checkForUpdate() async => AppUpdateInfo(
        updateAvailability: UpdateAvailability.updateAvailable,
        immediateUpdateAllowed: true,
        immediateAllowedPreconditions: null,
        flexibleUpdateAllowed: true,
        flexibleAllowedPreconditions: null,
        availableVersionCode: 60,
        installStatus: InstallStatus.unknown,
        packageName: 'com.chatyuk.chatyuk',
        clientVersionStalenessDays: 1,
        updatePriority: 0,
      );

  @override
  Future<AppUpdateResult> startFlexibleUpdate() async {
    flexibleStarted = true;
    return AppUpdateResult.success;
  }

  @override
  Future<AppUpdateResult> performImmediateUpdate() async =>
      AppUpdateResult.success;

  @override
  Future<void> completeFlexibleUpdate() async {
    flexibleCompleted = true;
  }

  @override
  Stream<InstallStatus> get installStatusStream => controller.stream;
}

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

  /// Pengganti pumpAndSettle: maju 2 detik waktu virtual dalam langkah
  /// 100ms. Deterministik & cepat — tidak menunggu frame berhenti total
  /// (indikator progress animasi selamanya).
  Future<void> pumpSettled(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('fase available → judul + versi + notes + tombol Update/Nanti',
      (tester) async {
    final svc = AppUpdateService.forTest(client: _FakePlayClient())
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
    await pumpSettled(tester);

    expect(find.text(s.updateTitle), findsOneWidget);
    expect(find.textContaining('1.2.48'), findsWidgets);
    expect(find.text(s.updateNotesLabel), findsOneWidget);
    expect(find.text('Perbaikan bug'), findsOneWidget);
    expect(find.text(s.btnUpdateNow), findsOneWidget);
    expect(find.text(s.btnUpdateLater), findsOneWidget);
  });

  testWidgets('force → judul wajib + TANPA tombol Nanti', (tester) async {
    final svc = AppUpdateService.forTest(client: _FakePlayClient())
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
    await pumpSettled(tester);

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
    await pumpSettled(tester);

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
    await pumpSettled(tester);

    expect(find.text(s.btnUpdateRestart), findsOneWidget);
  });

  testWidgets('tap Update → popup langsung tertutup (download background)',
      (tester) async {
    // Jalur produksi: dialog dibuka lewat provider (check + navigatorKey),
    // bukan showUpdateDialog langsung.
    final key = GlobalKey<NavigatorState>();
    final client = _FakePlayClient();
    final svc = AppUpdateService.forTest(client: client)
      ..debugPolicyOverride = const UpdatePolicy(
        enabled: true,
        latestVersion: '1.2.48',
        minVersion: '',
        notes: '',
      )
      ..debugLocalVersionOverride = (version: '1.2.47', buildNumber: 47)
      ..debugPlayAvailabilityOverride = PlayAvailability.available;
    final p = UpdateProvider(service: svc);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleProvider>(
            create: (_) => LocaleProvider(),
          ),
        ],
        child: MaterialApp(
          navigatorKey: key,
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await p.check(navigatorKey: key);
    await pumpSettled(tester);
    expect(find.text(s.updateTitle), findsOneWidget);

    await tester.tap(find.text(s.btnUpdateNow));
    await pumpSettled(tester);

    expect(p.phase, UpdatePhase.downloading,
        reason: 'startUpdate harus jalan sampai downloading');
    expect(find.text(s.updateTitle), findsNothing);
    expect(find.text(s.btnUpdateNow), findsNothing);
  });

  testWidgets('presentIfNeeded: hanya fase available memunculkan popup',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    final p = makeProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleProvider>(
            create: (_) => LocaleProvider(),
          ),
        ],
        child: MaterialApp(
          navigatorKey: key,
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    Future<void> closeDialog() async {
      final ctx = key.currentContext;
      if (ctx == null) return;
      final nav = Navigator.of(ctx, rootNavigator: true);
      // Hanya pop bila ADA dialog di atas home (tanpa guard ini pop()
      // melempar Bad state saat tidak ada dialog terbuka).
      if (nav.canPop()) {
        nav.pop();
        await pumpSettled(tester);
      }
    }

    for (final phase in [
      UpdatePhase.idle,
      UpdatePhase.checking,
      UpdatePhase.downloading,
      UpdatePhase.readyToInstall,
      UpdatePhase.failed,
      UpdatePhase.openStore,
    ]) {
      debugResetUpdateDialogGuard();
      p.setPhaseForTest(phase);
      p.presentIfNeeded(key);
      // pump sekali saja (tanpa settle): aman walau ada progress animasi.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(s.updateTitle), findsNothing,
          reason: 'fase $phase tidak boleh memunculkan popup');
      await closeDialog();
    }
    debugResetUpdateDialogGuard();
    p.setPhaseForTest(UpdatePhase.available);
    p.presentIfNeeded(key);
    await pumpSettled(tester);
    expect(find.text(s.updateTitle), findsOneWidget);
    await closeDialog();
  });

  testWidgets('fase idle → dialog langsung menutup (SizedBox kosong)',
      (tester) async {
    final p = makeProvider();
    p.setPhaseForTest(UpdatePhase.idle);

    await tester.pumpWidget(wrap(p));
    await tester.tap(find.text('open'));
    await pumpSettled(tester);

    // Tidak ada elemen dialog yang tersisa.
    expect(find.text(s.updateTitle), findsNothing);
    expect(find.text(s.btnUpdateNow), findsNothing);
  });
}
