import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/providers/call_provider.dart';
import 'package:chatyuk/services/call/call_ui.dart';
import 'package:chatyuk/services/call/call_ui_channel.dart';

class _FakeCallUi implements CallUi {
  final List<String> calls = [];
  FutureOr<void> Function(String)? _accept;
  FutureOr<void> Function(String)? _decline;
  FutureOr<void> Function(String)? _end;

  @override
  Future<void> showIncoming({
    required String callId,
    required String callerName,
    required String callType,
  }) async {
    calls.add('show:$callId:$callerName:$callType');
  }

  @override
  Future<void> setConnected(String callId) async => calls.add('connected:$callId');

  @override
  Future<void> dismiss(String callId) async => calls.add('dismiss:$callId');

  @override
  set onAccept(FutureOr<void> Function(String)? cb) => _accept = cb;

  @override
  set onDecline(FutureOr<void> Function(String)? cb) => _decline = cb;

  @override
  set onEnd(FutureOr<void> Function(String)? cb) => _end = cb;

  @override
  Future<void> dispose() async {}

  // Dipakai test untuk mensimulasikan tombol UI sistem.
  Future<void> fireAccept(String callId) async => _accept?.call(callId);
  Future<void> fireDecline(String callId) async => _decline?.call(callId);
  Future<void> fireEnd(String callId) async => _end?.call(callId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallUi wiring (message channels)', () {
    test('native onAccept/onDecline/onEnd diteruskan ke callback', () async {
      final ui = CallUiChannel.instance;
      final seen = <String>[];
      ui.onAccept = (id) => seen.add('accept:$id');
      ui.onDecline = (id) => seen.add('decline:$id');
      ui.onEnd = (id) => seen.add('end:$id');

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('com.chatyuk.chatyuk/call_ui');

      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('onAccept', 'call-1')),
        (_) {},
      );
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('onDecline', 'call-1')),
        (_) {},
      );
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('onEnd', 'call-1')),
        (_) {},
      );

      expect(seen, ['accept:call-1', 'decline:call-1', 'end:call-1']);
      await ui.dispose();
    });
  });

  group('CallProvider integrasi CallUi', () {
    late _FakeCallUi ui;
    late CallProvider provider;

    setUp(() {
      ui = _FakeCallUi();
      provider = CallProvider.newForTest(ui);
    });

    tearDown(() => provider.dispose());

    test('bindIncomingScreen: accept sistem memanggil handler layar', () async {
      var accepted = 0;
      provider.bindIncomingScreen(
        callId: 'c1',
        onAccept: () async => accepted++,
        onDecline: () async {},
      );

      await ui.fireAccept('c1');
      expect(accepted, 1);
    });

    test('accept sistem untuk callId lain TIDAK memicu handler layar', () async {
      var accepted = 0;
      provider.bindIncomingScreen(
        callId: 'c1',
        onAccept: () async => accepted++,
        onDecline: () async {},
      );

      await ui.fireAccept('c2');
      expect(accepted, 0);
    });

    test('unbindIncomingScreen melepas handler', () async {
      var accepted = 0;
      provider.bindIncomingScreen(
        callId: 'c1',
        onAccept: () async => accepted++,
        onDecline: () async {},
      );
      provider.unbindIncomingScreen('c1');

      await ui.fireAccept('c1');
      expect(accepted, 0);
    });

    test('end sistem saat tidak ada sesi → dismiss + unregister', () async {
      provider.registerCall('c9');
      expect(provider.inCall, isTrue);

      await ui.fireEnd('c9');

      expect(ui.calls, contains('dismiss:c9'));
      expect(provider.inCall, isFalse);
    });

    test('Stub default: semua operasi no-op tanpa error', () async {
      final stub = CallUiStub();
      await stub.showIncoming(
        callId: 'x',
        callerName: 'A',
        callType: 'audio',
      );
      await stub.setConnected('x');
      await stub.dismiss('x');
      await stub.dispose();
    });
  });
}
