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
    fake = FakeConnectivityPlatform();
    ConnectivityPlatform.instance = fake;
  });

  tearDown(() async {
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

  test('checkConnectivity = none → offline', () async {
    fake.initial = [ConnectivityResult.none];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(connectivityProvider, (_, __) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(connectivityProvider), isFalse);
  });

  test('event none → offline, lalu wifi → online', () async {
    fake.initial = [ConnectivityResult.wifi];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(connectivityProvider, (_, __) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(connectivityProvider), isTrue);

    fake.emit([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(connectivityProvider), isFalse);

    fake.emit([ConnectivityResult.mobile]);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(connectivityProvider), isTrue);
  });

  test('event sama berulang → tidak notify dobel', () async {
    fake.initial = [ConnectivityResult.wifi];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(connectivityProvider, (_, __) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    var notified = 0;
    c.listen<bool>(connectivityProvider, (_, __) => notified++);

    fake.emit([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 0);
  });

  test('dispose membatalkan subscription', () async {
    fake.initial = [ConnectivityResult.wifi];
    final c = ProviderContainer();
    c.listen(connectivityProvider, (_, __) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    // Emit setelah dispose tidak boleh melempar.
    fake.emit([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
  });

  test('stuck offline sembuh via revalidate (tanpa event)', () async {
    // Regresi: cek awal menangkap `none` sesaat lalu tak ada event lagi →
    // banner offline nyangkut selamanya. revalidate() harus menyembuhkan.
    fake.initial = [ConnectivityResult.none];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(connectivityProvider, (_, __) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(connectivityProvider), isFalse);

    // Jaringan pulih tapi TIDAK ada event perubahan — hanya revalidate.
    fake.initial = [ConnectivityResult.wifi];
    c.read(connectivityProvider.notifier).revalidate();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(connectivityProvider), isTrue);
  });

  test('revalidate nilai sama → tidak notify', () async {
    fake.initial = [ConnectivityResult.wifi];
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(connectivityProvider, (_, __) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    var notified = 0;
    c.listen<bool>(connectivityProvider, (_, __) => notified++);

    c.read(connectivityProvider.notifier).revalidate();
    await Future<void>.delayed(Duration.zero);
    expect(notified, 0);
  });
}
