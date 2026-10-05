import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/riverpod/update_provider.dart';
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
/// string bilingual & mengikuti fase provider.
void main() {
  final s = S(isId: true);

  late ProviderContainer container;
  late UpdateNotifier notifier;

  ProviderContainer makeContainer([AppUpdateService? service]) {
    final c = ProviderContainer(
      overrides: [
        if (service != null)
          updateProvider.overrideWith(() => UpdateNotifier(service)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Widget wrap(UpdateNotifier n) => UncontrolledProviderScope(
        container: container,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => showUpdateDialog(ctx, n),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugResetUpdateDialogGuard();
  });

  Future<void> pumpSettled(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  UpdateNotifier makeProvider({bool fromPlay = true, bool force = false}) {
    container = makeContainer(AppUpdateService.forTest());
    notifier = container.read(updateProvider.notifier);
    notifier.setFromPlayForTest(fromPlay);
    notifier.setForceForTest(force);
    return notifier;
  }

  testWidgets('fase available → judul + versi + notes + tombol Update/Nanti',
      (tester) async {
    final svc = AppUpdateService.forTest(client: _FakePlayClient())
      ..debugPolicyOverride = UpdatePolicy(
        enabled: true,
        latestVersion: '1.2.48',
        minVersion: '',
        notes: 'Perbaikan bug',
        pushAt: DateTime.now().toUtc(),
      )
      ..debugLocalVersionOverride = (version: '1.2.47', buildNumber: 47)
      ..debugPlayAvailabilityOverride = PlayAvailability.available;
    container = makeContainer(svc);
    final p = container.read(updateProvider.notifier);
    await p.check();

    await tester.pumpWidget(wrap(p));
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
        minVersion: '1.2.47',
        notes: '',
      )
      ..debugLocalVersionOverride = (version: '1.2.40', buildNumber: 40)
      ..debugPlayAvailabilityOverride = PlayAvailability.available;
    container = makeContainer(svc);
    final p = container.read(updateProvider.notifier);
    await p.check();
    expect(container.read(updateProvider).force, isTrue);

    await tester.pumpWidget(wrap(p));
    await tester.tap(find.text('open'));
    await pumpSettled(tester);

    expect(find.text(s.updateRequiredTitle), findsOneWidget);
    expect(find.text(s.btnUpdateNow), findsOneWidget);
    expect(find.text(s.btnUpdateLater), findsNothing);
  });

  testWidgets('non-Play → tombol Buka Google Play', (tester) async {
    final svc = AppUpdateService.forTest()
      ..debugPolicyOverride = UpdatePolicy(
        enabled: true,
        latestVersion: '1.2.48',
        minVersion: '',
        notes: '',
        pushAt: DateTime.now().toUtc(),
      )
      ..debugLocalVersionOverride = (version: '1.2.47', buildNumber: 47)
      ..debugPlayAvailabilityOverride = PlayAvailability.notFromPlay;
    container = makeContainer(svc);
    final p = container.read(updateProvider.notifier);
    await p.check();
    expect(container.read(updateProvider).fromPlay, isFalse);

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
    final key = GlobalKey<NavigatorState>();
    final client = _FakePlayClient();
    final svc = AppUpdateService.forTest(client: client)
      ..debugPolicyOverride = UpdatePolicy(
        enabled: true,
        latestVersion: '1.2.48',
        minVersion: '',
        notes: '',
        pushAt: DateTime.now().toUtc(),
      )
      ..debugLocalVersionOverride = (version: '1.2.47', buildNumber: 47)
      ..debugPlayAvailabilityOverride = PlayAvailability.available;
    container = makeContainer(svc);
    final p = container.read(updateProvider.notifier);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MultiProvider(
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
      ),
    );
    await p.check(navigatorKey: key);
    await pumpSettled(tester);
    expect(find.text(s.updateTitle), findsOneWidget);

    await tester.tap(find.text(s.btnUpdateNow));
    await pumpSettled(tester);

    expect(container.read(updateProvider).phase, UpdatePhase.downloading,
        reason: 'startUpdate harus jalan sampai downloading');
    expect(find.text(s.updateTitle), findsNothing);
    expect(find.text(s.btnUpdateNow), findsNothing);
  });

  testWidgets('presentIfNeeded: hanya fase available memunculkan popup',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    final p = makeProvider();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MultiProvider(
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
      ),
    );
    Future<void> closeDialog() async {
      final ctx = key.currentContext;
      if (ctx == null) return;
      final nav = Navigator.of(ctx, rootNavigator: true);
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

    expect(find.text(s.updateTitle), findsNothing);
    expect(find.text(s.btnUpdateNow), findsNothing);
  });
}
