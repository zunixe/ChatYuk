import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/services/call_service.dart';
import 'package:chatyuk/services/media_disk_cache.dart';
import 'package:chatyuk/widgets/chat_call_overlay.dart';

void main() {
  // CallService.instance → SupabaseConfig.client → Supabase.instance
  // melempar assertion kalau initialize() belum dipanggil.
  setUpAll(() async {
    // Supabase.initialize baca session via SharedPreferences — mock channel.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => null,
    );
    // MediaDiskCache.prewarm butuh directory — mock path_provider lalu
    // prewarm SEKARANG supaya ProfileAvatar.waitReady di widget test
    // tidak menjadwalkan Future.delayed (timer pending → invariant fail).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async =>
          Directory.systemTemp.createTempSync('chatyuk_test_media').path,
    );
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.test',
    );
    await MediaDiskCache.instance.prewarm();
  });

  testWidgets('ChatCallOverlay mounts (connecting)', (tester) async {
    final session = CallSession(
      callId: 'c1',
      remoteUid: 'u1',
      remoteName: 'Budi',
      callType: 'video',
      isCaller: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<LocaleProvider>.value(
          value: LocaleProvider(),
          child: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: ChatCallOverlay(
                    session: session,
                    onExpand: _noop,
                    onEnd: _noop,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // ProfileAvatar._load retry 10× dengan Future.delayed 300ms saat uid
    // tidak punya avatar — majukan clock melewati total retry (3.5s) supaya
    // tidak ada timer pending saat tree disposed.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  });
}

void _noop() {}
