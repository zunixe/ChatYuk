import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Kumpulan request yang masuk ke mock server (untuk verifikasi).
final List<http.Request> captured = [];

/// Mock HTTP server GoTrue minimal: cukup untuk mengunci perilaku
/// signup/OTP/resend yang pernah jadi bug ("kode tidak valid").
/// Dipakai di isolate terpisah supaya bisa memakai `MockClient`
/// (test default tidak boleh override http client Supabase).
MockClient buildMockServer() {
  return MockClient((req) async {
    captured.add(req);
    final path = req.url.path;

    // POST /auth/v1/token?grant_type=... (login anon / password)
    if (path.endsWith('/token')) {
      final grant = req.url.queryParameters['grant_type'];
      if (grant == 'anonymous') {
        return http.Response(
          jsonEncode({
            'access_token': 'anon-access',
            'refresh_token': 'anon-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'anon-1',
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00.000Z',
              'is_anonymous': true,
              'identities': [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'error': 'unsupported_grant', 'error_description': grant}),
        400,
        headers: {'content-type': 'application/json'},
      );
    }

    // POST /auth/v1/signup
    if (path.endsWith('/signup')) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final email = body['email'] as String?;
      // Tanpa email = sign-in anonymous → balas dengan SESSION.
      if (email == null || email.isEmpty) {
        return http.Response(
          jsonEncode({
            'access_token': 'anon-access',
            'refresh_token': 'anon-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'anon-1',
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00.000Z',
              'is_anonymous': true,
              'identities': [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // Email "fresh@" = user BARU asli → identities berisi (tidak resend).
      // Email lain = sudah ada & belum diverifikasi → GoTrue balas user
      // PALSU (identities kosong) & TIDAK kirim OTP (harus resend).
      final fresh = email.startsWith('fresh@');
      return http.Response(
        jsonEncode({
          'id': fresh ? 'new-1' : 'dup-1',
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00.000Z',
          'email': email,
          'identities': fresh
              ? [
                  {
                    'id': 'ident-1',
                    'user_id': 'new-1',
                    'provider': 'email',
                    'identity_data': {'email': email},
                  }
                ]
              : [],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    // POST /auth/v1/resend
    if (path.endsWith('/resend')) {
      return http.Response('{}', 200,
          headers: {'content-type': 'application/json'});
    }

    // POST /auth/v1/verify → kode valid hanya "123456"
    if (path.endsWith('/verify')) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final token = body['token'] as String?;
      if (token == '123456') {
        return http.Response(
          jsonEncode({
            'access_token': 'verified-access',
            'refresh_token': 'verified-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'uid-1',
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00.000Z',
              'email': body['email'],
              'email_confirmed_at': '2026-01-01T00:00:00.000Z',
              'identities': [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'error': 'invalid_grant',
          'error_description': 'Token has expired or is invalid',
          'code': 'otp_expired',
        }),
        403,
        headers: {'content-type': 'application/json'},
      );
    }

    // RPC check_email_registered (PostgREST) → selalu false (email baru).
    if (path.contains('/rest/v1/rpc/check_email_registered')) {
      return http.Response('false', 200,
          headers: {'content-type': 'application/json'});
    }

    return http.Response('{}', 200,
        headers: {'content-type': 'application/json'});
  });
}
