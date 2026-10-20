import 'dart:async';
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

  /// Pola path yang digantung selamanya (simulasi koneksi stall) —
  /// dipakai dengan `fakeAsync` + `elapse` untuk membuktikan timeout.
  final Set<String> hangs = {};

  FakeSupabaseHandler();

  /// `pattern` dicek dengan `path.contains(pattern)`.
  void on(String pattern, Object Function(http.Request req) reply) {
    routes[pattern] = reply;
  }

  /// Request yang path-nya mengandung `pattern` tidak pernah dijawab.
  void onHang(String pattern) {
    hangs.add(pattern);
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
        for (final pattern in hangs) {
          if (req.url.path.contains(pattern)) {
            await Completer<void>().future;
          }
        }
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

/// Varian tanpa ticker auto-refresh GoTrue — untuk widget test, supaya
/// tidak ada Timer menggantung saat teardown invariant (flutter_test
/// gagal "Timer is still pending"). Perilaku HTTP palsu identik.
SupabaseClient fakeSupabaseClientNoTicker({FakeSupabaseHandler? handler}) {
  final h = handler ?? FakeSupabaseHandler();
  return SupabaseClient(
    'https://test.supabase.co',
    'test-anon-key',
    httpClient: h.client(),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

bool _isRpc(http.Request r, String fn) =>
    r.method == 'POST' && r.url.path.endsWith('/rest/v1/rpc/$fn');

http.Request? _rpcRequest(FakeSupabaseHandler handler, String fn) {
  for (final r in handler.captured) {
    if (_isRpc(r, fn)) return r;
  }
  return null;
}

int _rpcCount(FakeSupabaseHandler handler, String fn) =>
    handler.captured.where((r) => _isRpc(r, fn)).length;

/// Tunggu sampai RPC [fn] benar-benar terkirim (maks [timeout]).
///
/// Dipakai jalur fire-and-forget seperti `markAsRead`: RPC sengaja TIDAK
/// di-await pemanggil (supaya buka chat tidak menunggu jaringan), jadi test
/// tidak boleh langsung membaca [FakeSupabaseHandler.captured] setelah
/// `await markAsRead(...)`.
Future<http.Request> waitRpc(
  FakeSupabaseHandler handler,
  String fn, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final req = _rpcRequest(handler, fn);
    if (req != null) return req;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(
        'RPC "$fn" tidak terkirim sampai ${timeout.inMilliseconds}ms. '
        'Request tercatat: '
        '${handler.captured.map((r) => '${r.method} ${r.url.path}').toList()}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Tunggu sampai jumlah request RPC [fn] mencapai [count].
Future<void> waitRpcCount(
  FakeSupabaseHandler handler,
  String fn,
  int count, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (_rpcCount(handler, fn) < count) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(
        'RPC "$fn" baru ${_rpcCount(handler, fn)}× dari $count× dalam '
        '${timeout.inMilliseconds}ms. Request tercatat: '
        '${handler.captured.map((r) => '${r.method} ${r.url.path}').toList()}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Ambil request POST ke `/rest/v1/rpc/<fn>` — untuk test semi-integrasi yang
/// memverifikasi nama RPC + params yang benar-benar dikirim ke PostgREST.
http.Request rpcRequestOf(FakeSupabaseHandler handler, String fn) =>
    _rpcRequest(handler, fn) ??
    (throw StateError(
      'RPC "$fn" tidak terkirim. Request tercatat: '
      '${handler.captured.map((r) => '${r.method} ${r.url.path}').toList()}',
    ));

/// Params body dari RPC [fn] (sudah di-decode). RPC tanpa params mengirim
/// body kosong/`null` → kembalikan map kosong, bukan error.
Map<String, dynamic> rpcParamsOf(FakeSupabaseHandler handler, String fn) {
  final body = rpcRequestOf(handler, fn).body;
  if (body.isEmpty) return {};
  final decoded = jsonDecode(body);
  if (decoded is! Map) return {};
  return decoded.cast<String, dynamic>();
}
