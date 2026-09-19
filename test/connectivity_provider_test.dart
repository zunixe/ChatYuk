import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:chatyuk/providers/connectivity_provider.dart';

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
    final p = ConnectivityProvider();
    expect(p.online, isTrue); // default optimistis sebelum check selesai
    await Future<void>.delayed(Duration.zero);
    expect(p.online, isTrue);
    p.dispose();
  });

  test('checkConnectivity = none → offline + notify', () async {
    fake.initial = [ConnectivityResult.none];
    final p = ConnectivityProvider();
    var notified = 0;
    p.addListener(() => notified++);
    await Future<void>.delayed(Duration.zero);
    expect(p.online, isFalse);
    expect(notified, greaterThanOrEqualTo(1));
    p.dispose();
  });

  test('event none → offline, lalu wifi → online', () async {
    fake.initial = [ConnectivityResult.wifi];
    final p = ConnectivityProvider();
    await Future<void>.delayed(Duration.zero);
    expect(p.online, isTrue);

    fake.emit([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    expect(p.online, isFalse);

    fake.emit([ConnectivityResult.mobile]);
    await Future<void>.delayed(Duration.zero);
    expect(p.online, isTrue);
    p.dispose();
  });

  test('event sama berulang → tidak notify dobel', () async {
    fake.initial = [ConnectivityResult.wifi];
    final p = ConnectivityProvider();
    await Future<void>.delayed(Duration.zero);
    var notified = 0;
    p.addListener(() => notified++);

    fake.emit([ConnectivityResult.wifi]);
    fake.emit([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 0);
    p.dispose();
  });

  test('dispose membatalkan subscription', () async {
    fake.initial = [ConnectivityResult.wifi];
    final p = ConnectivityProvider();
    await Future<void>.delayed(Duration.zero);
    p.dispose();
    // Emit setelah dispose tidak boleh melempar / notify.
    fake.emit([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
  });
}
