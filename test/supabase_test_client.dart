import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Helper bersama untuk test DI: membangun `SupabaseClient` asli (bukan mock
/// class) tetapi dengan `httpClient` palsu — jadi semua `.from()`, `.rpc()`,
/// `.auth.*` berjalan tanpa jaringan, dan `_sb` service bisa diuji nyata.
///
/// Realtime (`.channel()`) memakai WebSocket & tidak disimulasikan di sini;
/// test yang memicunya harus mengandalkan guard/timeout, bukan channel palsu.

/// Request yang masuk ke client palsu (untuk verifikasi).
final List<http.Request> testCaptured = [];

/// Handler sederhana: map path→response. Path dicocokkan dengan `contains`.
class FakeSupabaseHandler {
  final Map<String, Object Function(http.Request req)> routes = {};
  final List<http.Request> captured = [];

  FakeSupabaseHandler();

  /// `pattern` dicek dengan `path.contains(pattern)`.
  void on(String pattern, Object Function(http.Request req) reply) {
    routes[pattern] = reply;
  }

  http.Response _responseFor(http.Request req) {
    for (final entry in routes.entries) {
      if (req.url.path.contains(entry.key)) {
        final res = entry.value(req);
        if (res is http.Response) return res;
        return http.Response(
          jsonEncode(res),
          200,
          request: req,
          headers: {'content-type': 'application/json'},
        );
      }
    }
    // Default: PostgREST mengembalikan array kosong / null.
    // `request: req` WAJIB — PostgREST `_parseResponse` membaca
    // `response.request!.method` (null → crash "Null check operator").
    return http.Response(
      '[]',
      200,
      request: req,
      headers: {'content-type': 'application/json'},
    );
  }

  MockClient client() => MockClient((req) async {
        captured.add(req);
        return _responseFor(req);
      });
}

/// Bangun `SupabaseClient` dengan HTTP palsu. `handler` opsional; default
/// menjawab semua permintaan dengan `[]` (200).
SupabaseClient fakeSupabaseClient({FakeSupabaseHandler? handler}) {
  final h = handler ?? FakeSupabaseHandler();
  return SupabaseClient(
    'https://test.supabase.co',
    'test-anon-key',
    httpClient: h.client(),
  );
}
