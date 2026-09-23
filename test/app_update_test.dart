import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/services/app_update_service.dart';
import 'package:chatyuk/providers/update_provider.dart';

import 'supabase_test_client.dart';

/// Fitur popup update — logika murni (semver, keputusan update, snooze,
/// branch provider). Play Core dan Supabase di-mock lewat abstraksi
/// [AppUpdateClient]; plugin asli tidak pernah dipanggil di test.
class _FakeClient implements AppUpdateClient {
  AppUpdateInfo? info = AppUpdateInfo(
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
  bool flexibleStarted = false;
  bool immediateStarted = false;
  bool flexibleCompleted = false;

  /// Status yang dipancarkan ke stream saat startFlexibleUpdate dipanggil.
  List<InstallStatus> emitOnStart = const [];

  final _controller = StreamController<InstallStatus>.broadcast();

  @override
  Future<AppUpdateInfo> checkForUpdate() async => info!;

  @override
  Future<AppUpdateResult> startFlexibleUpdate() async {
    flexibleStarted = true;
    for (final s in emitOnStart) {
      _controller.add(s);
    }
    return AppUpdateResult.success;
  }

  @override
  Future<AppUpdateResult> performImmediateUpdate() async {
    immediateStarted = true;
    return AppUpdateResult.success;
  }

  @override
  Future<void> completeFlexibleUpdate() async {
    flexibleCompleted = true;
  }

  @override
  Stream<InstallStatus> get installStatusStream => _controller.stream;
}

/// Fake yang selalu menolak flexible update (Play tidak kenal versi ini).
class _RejectClient implements AppUpdateClient {
  @override
  Future<AppUpdateInfo> checkForUpdate() async => AppUpdateInfo(
        updateAvailability: UpdateAvailability.updateNotAvailable,
        immediateUpdateAllowed: false,
        immediateAllowedPreconditions: null,
        flexibleUpdateAllowed: false,
        flexibleAllowedPreconditions: null,
        availableVersionCode: null,
        installStatus: InstallStatus.unknown,
        packageName: 'com.chatyuk.chatyuk',
        clientVersionStalenessDays: null,
        updatePriority: 0,
      );

  @override
  Future<AppUpdateResult> startFlexibleUpdate() async =>
      AppUpdateResult.inAppUpdateFailed;

  @override
  Future<AppUpdateResult> performImmediateUpdate() async =>
      AppUpdateResult.inAppUpdateFailed;

  @override
  Future<void> completeFlexibleUpdate() async {}

  @override
  Stream<InstallStatus> get installStatusStream =>
      const Stream<InstallStatus>.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppUpdateService.compareSemver', () {
    test('versi lebih baru → positif', () {
      expect(AppUpdateService.compareSemver('1.2.5', '1.2.4'), greaterThan(0));
      expect(AppUpdateService.compareSemver('1.3.0', '1.2.9'), greaterThan(0));
      expect(AppUpdateService.compareSemver('2.0.0', '1.9.9'), greaterThan(0));
    });

    test('versi lebih lama → negatif', () {
      expect(AppUpdateService.compareSemver('1.2.4', '1.2.5'), lessThan(0));
      expect(AppUpdateService.compareSemver('1.2.9', '1.2.10'), lessThan(0));
    });

    test('sama → nol', () {
      expect(AppUpdateService.compareSemver('1.2.47', '1.2.47'), 0);
      expect(AppUpdateService.compareSemver('1.2.47+59', '1.2.47'), 0);
    });

    test('tahan panjang beda (1.2 vs 1.2.0)', () {
      expect(AppUpdateService.compareSemver('1.2', '1.2.0'), 0);
      expect(AppUpdateService.compareSemver('1.2.1', '1.2'), greaterThan(0));
    });
  });

  group('keputusan update', () {
    test('isUpdateAvailable true bila latest > local', () {
      expect(
        AppUpdateService.isUpdateAvailable(local: '1.2.47', latest: '1.2.48'),
        isTrue,
      );
      expect(
        AppUpdateService.isUpdateAvailable(local: '1.2.47', latest: '1.2.47'),
        isFalse,
      );
      expect(
        AppUpdateService.isUpdateAvailable(local: '', latest: '1.2.48'),
        isFalse,
      );
    });

    test('isForceRequired true bila local < min', () {
      expect(
        AppUpdateService.isForceRequired(local: '1.2.40', minVersion: '1.2.47'),
        isTrue,
      );
      expect(
        AppUpdateService.isForceRequired(local: '1.2.47', minVersion: '1.2.47'),
        isFalse,
      );
      expect(
        AppUpdateService.isForceRequired(local: '1.2.47', minVersion: ''),
        isFalse,
      );
    });
  });

  group('UpdatePolicy', () {
    test('isEmpty saat disabled / latest kosong', () {
      expect(
        const UpdatePolicy(
          enabled: false,
          latestVersion: '1.2.48',
          minVersion: '',
          notes: '',
        ).isEmpty,
        isTrue,
      );
      expect(
        const UpdatePolicy(
          enabled: true,
          latestVersion: '',
          minVersion: '',
          notes: '',
        ).isEmpty,
        isTrue,
      );
      expect(
        const UpdatePolicy(
          enabled: true,
          latestVersion: '1.2.48',
          minVersion: '',
          notes: '',
        ).isEmpty,
        isFalse,
      );
    });
  });

  group('UpdateProvider snooze', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('snooze menyimpan versi lalu check tidak popup lagi', () async {
      final p = UpdateProvider(service: AppUpdateService.forTest());
      await p.snoozeForTest(version: '1.2.48');
      expect(await p.isSnoozedForTest('1.2.48'), isTrue);
      expect(await p.isSnoozedForTest('1.2.99'), isFalse);
    });

    test('snooze kedaluwarsa setelah 24 jam', () async {
      final p = UpdateProvider(service: AppUpdateService.forTest());
      // Simulasi timestamp lama (2 hari lalu).
      await p.writeSnoozeForTest(
        version: '1.2.48',
        ts: DateTime.now()
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch,
      );
      expect(await p.isSnoozedForTest('1.2.48'), isFalse);
    });
  });

  group('provider startUpdate branch', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('non-Play → fase openStore (buka listing Play)', () async {
      final svc = AppUpdateService.forTest(client: _FakeClient());
      final p = UpdateProvider(service: svc)
        ..setFromPlayForTest(false)
        ..setForceForTest(false);
      await p.startUpdate();
      expect(p.phase, UpdatePhase.openStore);
    });

    test('Play + force → immediate update dipanggil', () async {
      final client = _FakeClient();
      final svc = AppUpdateService.forTest(client: client);
      final p = UpdateProvider(service: svc)
        ..setFromPlayForTest(true)
        ..setForceForTest(true);
      await p.startUpdate();
      expect(client.immediateStarted, isTrue);
      expect(client.flexibleStarted, isFalse);
    });

    test('Play + tidak force → flexible lalu auto-install saat downloaded',
        () async {
      final client = _FakeClient()
        ..emitOnStart = [InstallStatus.downloading, InstallStatus.downloaded];
      final svc = AppUpdateService.forTest(client: client);
      final p = UpdateProvider(service: svc)
        ..setFromPlayForTest(true)
        ..setForceForTest(false);
      await p.startUpdate();
      expect(client.flexibleStarted, isTrue);
      // Status stream dipancarkan asinkron → tunggu mikro-task selesai.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // downloaded → completeFlexible otomatis, fase kembali idle.
      expect(client.flexibleCompleted, isTrue);
      expect(p.phase, UpdatePhase.idle);
    });

    test('tap Update menandai versi → tidak popup lagi', () async {
      final client = _FakeClient();
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
      await p.check();
      expect(p.phase, UpdatePhase.available);
      await p.startUpdate();
      expect(client.flexibleStarted, isTrue);
      // Download lanjut diam-diam di background (fase downloading, tanpa
      // dialog) dan versi ditandai.
      expect(p.phase, UpdatePhase.downloading);
      expect(await p.isSnoozedForTest('1.2.48'), isTrue);
      // Simulasi restart app (provider baru, prefs sama) → tetap diam.
      final p2 = UpdateProvider(service: svc);
      await p2.check();
      expect(p2.phase, UpdatePhase.idle);
    });

    test('Play menolak flexible (result gagal) → fase failed', () async {
      final client = _RejectClient();
      final svc = AppUpdateService.forTest(client: client);
      final p = UpdateProvider(service: svc)
        ..setFromPlayForTest(true)
        ..setForceForTest(false);
      await p.startUpdate();
      expect(p.phase, UpdatePhase.failed);
    });

    test('Play + force → applyAndRestart memanggil completeFlexible', () async {
      final client = _FakeClient();
      final p = UpdateProvider(service: AppUpdateService.forTest(client: client))
        ..setPhaseForTest(UpdatePhase.readyToInstall);
      await p.applyAndRestart();
      expect(client.flexibleCompleted, isTrue);
    });
  });

  group('detectPlayAvailability (mock MethodChannel)', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.chatyuk.chatyuk/update'),
        null,
      );
    });

    void mockInstaller(String? installer) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.chatyuk.chatyuk/update'),
        (call) async {
          if (call.method == 'getInstallerPackage') return installer;
          return null;
        },
      );
    }

    test('installer com.android.vending → available', () async {
      mockInstaller('com.android.vending');
      final svc = AppUpdateService.forTest();
      expect(
        await svc.detectPlayAvailability(),
        PlayAvailability.available,
      );
    });

    test('installer sideload (null) → notFromPlay', () async {
      mockInstaller(null);
      final svc = AppUpdateService.forTest();
      expect(
        await svc.detectPlayAvailability(),
        PlayAvailability.notFromPlay,
      );
    });

    test('installer lain → notFromPlay', () async {
      mockInstaller('com.android.packageinstaller');
      final svc = AppUpdateService.forTest();
      expect(
        await svc.detectPlayAvailability(),
        PlayAvailability.notFromPlay,
      );
    });
  });

  group('fetchPolicy (mock Supabase / app_settings)', () {
    test('row lengkap → UpdatePolicy terisi', () async {
      final handler = FakeSupabaseHandler();
      handler.on('app_settings', (_) => {
            'update_enabled': true,
            'latest_version': '1.3.0',
            'min_version': '1.2.40',
            'update_notes': 'Catatan rilis',
          });
      final svc = AppUpdateService.forTest(sb: fakeSupabaseClient(handler: handler));
      final p = await svc.fetchPolicy();
      expect(p, isNotNull);
      expect(p!.enabled, isTrue);
      expect(p.latestVersion, '1.3.0');
      expect(p.minVersion, '1.2.40');
      expect(p.notes, 'Catatan rilis');
      expect(p.isEmpty, isFalse);
    });

    test('row disabled → isEmpty true', () async {
      final handler = FakeSupabaseHandler();
      handler.on('app_settings', (_) => {
            'update_enabled': false,
            'latest_version': '1.3.0',
            'min_version': '',
            'update_notes': '',
          });
      final svc = AppUpdateService.forTest(sb: fakeSupabaseClient(handler: handler));
      final p = await svc.fetchPolicy();
      expect(p!.enabled, isFalse);
      expect(p.isEmpty, isTrue);
    });

    test('error jaringan → null (tidak throw)', () async {
      final handler = FakeSupabaseHandler();
      handler.on('app_settings', (_) => {'x': 1});
      // Client gagal di semua request → fetchPolicy menelan error.
      final svc = AppUpdateService.forTest(sb: fakeSupabaseClient());
      // Default handler mengembalikan [] → maybeSingle null → fetchPolicy null.
      expect(await svc.fetchPolicy(), isNull);
    });
  });

  group('check() end-to-end (override hasil)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    UpdateProvider providerWith({
      required String local,
      required UpdatePolicy policy,
      PlayAvailability play = PlayAvailability.notFromPlay,
    }) {
      final svc = AppUpdateService.forTest()
        ..debugPolicyOverride = policy
        ..debugLocalVersionOverride = (version: local, buildNumber: 47)
        ..debugPlayAvailabilityOverride = play;
      return UpdateProvider(service: svc);
    }

    test('versi terbaru → fase available', () async {
      final p = providerWith(
        local: '1.2.47',
        policy: const UpdatePolicy(
          enabled: true,
          latestVersion: '1.2.48',
          minVersion: '',
          notes: 'n',
        ),
      );
      await p.check();
      expect(p.phase, UpdatePhase.available);
      expect(p.latestVersion, '1.2.48');
      expect(p.force, isFalse);
    });

    test('versi sama → tetap idle', () async {
      final p = providerWith(
        local: '1.2.47',
        policy: const UpdatePolicy(
          enabled: true,
          latestVersion: '1.2.47',
          minVersion: '',
          notes: '',
        ),
      );
      await p.check();
      expect(p.phase, UpdatePhase.idle);
    });

    test('fitur disabled → idle', () async {
      final p = providerWith(
        local: '1.2.40',
        policy: const UpdatePolicy(
          enabled: false,
          latestVersion: '1.2.48',
          minVersion: '',
          notes: '',
        ),
      );
      await p.check();
      expect(p.phase, UpdatePhase.idle);
    });

    test('di bawah min_version → force true', () async {
      final p = providerWith(
        local: '1.2.40',
        policy: const UpdatePolicy(
          enabled: true,
          latestVersion: '1.2.48',
          minVersion: '1.2.47',
          notes: '',
        ),
      );
      await p.check();
      expect(p.phase, UpdatePhase.available);
      expect(p.force, isTrue);
    });

    test('check kedua tidak double-popup (fase bukan idle)', () async {
      final p = providerWith(
        local: '1.2.47',
        policy: const UpdatePolicy(
          enabled: true,
          latestVersion: '1.2.48',
          minVersion: '',
          notes: '',
        ),
      );
      await p.check();
      expect(p.phase, UpdatePhase.available);
      // Panggil lagi → early-return karena fase != idle.
      await p.check();
      expect(p.phase, UpdatePhase.available);
    });

    test('snooze versi ini → check berikutnya idle', () async {
      final p = providerWith(
        local: '1.2.47',
        policy: const UpdatePolicy(
          enabled: true,
          latestVersion: '1.2.48',
          minVersion: '',
          notes: '',
        ),
      );
      await p.check();
      expect(p.phase, UpdatePhase.available);
      await p.snooze();
      expect(p.phase, UpdatePhase.idle);
      // Fase kini idle → check boleh jalan lagi, tapi versi ter-snooze → idle.
      await p.check();
      expect(p.phase, UpdatePhase.idle);
    });

    test('versi lokal lebih baru dari latest → idle', () async {
      final p = providerWith(
        local: '1.2.50',
        policy: const UpdatePolicy(
          enabled: true,
          latestVersion: '1.2.49',
          minVersion: '',
          notes: '',
        ),
      );
      await p.check();
      expect(p.phase, UpdatePhase.idle);
    });

    test('unduhan Play tertunda → auto-complete tanpa popup', () async {
      final client = _FakeClient()
        ..info = AppUpdateInfo(
          updateAvailability: UpdateAvailability.updateAvailable,
          immediateUpdateAllowed: true,
          immediateAllowedPreconditions: null,
          flexibleUpdateAllowed: true,
          flexibleAllowedPreconditions: null,
          availableVersionCode: 60,
          installStatus: InstallStatus.downloaded,
          packageName: 'com.chatyuk.chatyuk',
          clientVersionStalenessDays: 1,
          updatePriority: 0,
        );
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
      await p.check();
      expect(client.flexibleCompleted, isTrue);
      expect(p.phase, UpdatePhase.idle);
    });
  });

  group('presentIfNeeded guard', () {
    test('hanya tampil pada fase relevan', () {
      // Tidak ada navigatorKey valid → _presentDialog no-op, tapi kita uji
      // apel fase yang dianggap relevan lewat perilaku tidak throw.
      final key = GlobalKey<NavigatorState>();
      final p = UpdateProvider(service: AppUpdateService.forTest());

      for (final phase in [
        UpdatePhase.idle,
        UpdatePhase.checking,
        UpdatePhase.available,
        UpdatePhase.downloading,
        UpdatePhase.readyToInstall,
        UpdatePhase.failed,
        UpdatePhase.openStore,
      ]) {
        p.setPhaseForTest(phase);
        // Tidak boleh throw untuk fase apa pun (navigatorKey tanpa context).
        expect(() => p.presentIfNeeded(key), returnsNormally);
      }
    });
  });
}
