import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:chatyuk/providers/riverpod/connectivity_provider.dart';

/// Fake platform connectivity: hasil `check` + stream event dikendalikan test.
class FakeConnectivityPlatform extends ConnectivityPlatform
    with MockPlatformInterfaceMixin {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> initial = [ConnectivityResult.wifi];

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => initial;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void emit(List<ConnectivityResult> r) => _controller.add(r);

  Future<void> close() => _controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeConnectivityPlatform fake;

  setUp(() {
    // Channel default di-stub supaya instansiasi plugin tidak melempar.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => <String>['wifi'],
    );
    // Default probe (dipakai saat OS bilang `none`) → false (benar-benar
    // offline) supaya test tidak menembak jaringan nyata.
    ConnectivityNotifier.reachableOverrideForTest = () async => false;
    fake = FakeConnectivityPlatform();
    ConnectivityPlatform.instance = fake;
  });

  tearDown(() async {
    ConnectivityNotifier.reachableOverrideForTest = null;
    await fake.close();
  });

  test('nilai awal online dari checkConnectivity', () async {
    fake.initial = [ConnectivityResult.wifi];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    var online = c.read(connectivityProvider);
    c.listen<bool>(connectivityProvider, (_, n) => online = n, fireImmediately: true);
    expect(online, isTrue); // default optimistis sebelum check selesai
    await Future<void>.delayed(Duration.zero);
    expect(c.read(connectivityProvider), isTrue);
  });

  test('OS none + probe gagal SEKALI → masih ONLINE (anti banner kedip)',
      () async {
    // Keluhan user: banner "tidak ada koneksi" tampil padahal online. Satu
    // probe gagal (timeout sesaat / cold start) TIDAK boleh memunculkan banner.
    ConnectivityNotifier.reachableOverrideForTest = () async => false;
    fake.initial = [ConnectivityResult.none];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(connectivityProvider, (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(connectivityProvider), isTrue);

    // Gagal kedua (berurutan) → baru offline.
    c.read(connectivityProvider.notifier).revalidate();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(connectivityProvider), isFalse);
  });

  test('OS bilang none TAPI probe OK → tetap ONLINE (fix banner nyangkut)',
      () async {
    // Regresi nyata: connectivity_plus keliru `none` walau internet lancar.
    ConnectivityNotifier.reachableOverrideForTest = () async => true;
    fake.initial = [ConnectivityResult.none];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(connectivityProvider, (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(connectivityProvider), isTrue);
  });

  test('event none → offline (probe gagal), lalu wifi → online', () async {
    ConnectivityNotifier.reachableOverrideForTest = () async => false;
    fake.initial = [ConnectivityResult.wifi];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(connectivityProvider, (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(connectivityProvider), isTrue);

    fake.emit([ConnectivityResult.none]); // gagal #1 → masih online
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(connectivityProvider), isTrue);
    // Probe berikutnya (revalidate) juga gagal → offline.
    fake.initial = [ConnectivityResult.none];
    c.read(connectivityProvider.notifier).revalidate();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(connectivityProvider), isFalse);

    fake.emit([ConnectivityResult.mobile]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(connectivityProvider), isTrue);
  });

  test('offline lalu probe BERHASIL → langsung online (banner hilang)', () async {
    var ok = false;
    ConnectivityNotifier.reachableOverrideForTest = () async => ok;
    fake.initial = [ConnectivityResult.none];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(connectivityProvider, (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    c.read(connectivityProvider.notifier).revalidate();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(connectivityProvider), isFalse);

    // Internet pulih: probe berikutnya sukses → ONLINE walau OS masih `none`.
    ok = true;
    c.read(connectivityProvider.notifier).revalidate();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(connectivityProvider), isTrue);
  });

  test('event sama berulang → tidak notify dobel', () async {
    fake.initial = [ConnectivityResult.wifi];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(connectivityProvider, (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    var notified = 0;
    c.listen<bool>(connectivityProvider, (_, _) => notified++);

    fake.emit([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 0);
  });

  test('dispose membatalkan subscription', () async {
    fake.initial = [ConnectivityResult.wifi];
    final c = ProviderContainer();
    c.listen(connectivityProvider, (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    // Emit setelah dispose tidak boleh melempar.
    fake.emit([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
  });

  test('stuck offline sembuh via revalidate (tanpa event)', () async {
    ConnectivityNotifier.reachableOverrideForTest = () async => false;
    // Regresi: cek awal menangkap `none` sesaat lalu tak ada event lagi →
    // banner offline nyangkut selamanya. revalidate() harus menyembuhkan.
    fake.initial = [ConnectivityResult.none];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(connectivityProvider, (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    c.read(connectivityProvider.notifier).revalidate(); // gagal #2 → offline
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(connectivityProvider), isFalse);

    // Jaringan pulih tapi TIDAK ada event perubahan — hanya revalidate.
    fake.initial = [ConnectivityResult.wifi];
    c.read(connectivityProvider.notifier).revalidate();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(connectivityProvider), isTrue);
  });

  test('revalidate nilai sama → tidak notify', () async {
    fake.initial = [ConnectivityResult.wifi];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(connectivityProvider, (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    var notified = 0;
    c.listen<bool>(connectivityProvider, (_, _) => notified++);

    c.read(connectivityProvider.notifier).revalidate();
    await Future<void>.delayed(Duration.zero);
    expect(notified, 0);
  });
}
