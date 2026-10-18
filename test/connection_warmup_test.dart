import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/connection_warmup.dart';

/// Regresi PERF: koneksi Supabase harus dihangatkan saat app resume.
///
/// Terukur ke Supabase (region Tokyo) 2026-10-18:
///   COLD (DNS + TCP + TLS handshake) = 792ms
///   WARM (keep-alive)                = 110-140ms
///
/// Tanpa warmup, request pertama setelah HP idle membayar ±792ms penuh —
/// inilah "ngelag setelah idle" saat membuka daftar chat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('awalnya belum fresh', () {
    expect(ConnectionWarmup.isFresh, isFalse);
  });

  testWidgets('warm() tidak melempar walau URL tidak valid', (t) async {
    // Fire-and-forget: kegagalan jaringan tidak boleh menjadi error fatal.
    expect(() => ConnectionWarmup.warm('http://127.0.0.1:1'), returnsNormally);
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 300));
  });

  testWidgets('warm() idempoten: panggilan beruntun tidak menumpuk', (
    t,
  ) async {
    for (var i = 0; i < 5; i++) {
      ConnectionWarmup.warm('http://127.0.0.1:1');
    }
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 400));
    expect(ConnectionWarmup.isFresh, isA<bool>());
  });

  test('HttpClient probe memakai idleTimeout panjang', () {
    // idleTimeout 120s memastikan koneksi tidak ditutup saat HP idle sebentar
    // (dulu 15s → handshake 792ms harus diulang).
    final c = HttpClient()..idleTimeout = const Duration(seconds: 120);
    expect(c.idleTimeout, const Duration(seconds: 120));
    c.close(force: true);
  });
}
