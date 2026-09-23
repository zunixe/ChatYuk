import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/services/auth_service.dart';

/// Test SERVICE-LEVEL (bukan provider) — mengunci perilaku GoTrue yang
/// pernah jadi bug nyata "kode tidak valid":
///   1. signUp email yang sudah ada & belum diverifikasi → GoTrue balas
///      user palsu (identities kosong) & TIDAK kirim OTP; service harus
///      mendeteksi & memanggil resend.
///   2. verifyEmailOtp memakai type otp yang benar + menyimpan pesan
///      error asli (bukan ditelan).
///   3. signup dengan identities berisi → TIDAK resend (email baru asli).
///
/// File ini PUNYA ISOLATE SENDIRI (flutter test menjalankan per-file) →
/// aman init Supabase dengan httpClient mock; file test lain tetap pakai
/// client global dummy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => null,
    );
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      // ignore: deprecated_member_use
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.test',
      httpClient: buildMockServer(),
    );
  });

  setUp(() async {
    captured.clear();
    // Pastikan tidak ada sesi tersisa antar-test (verify di test sebelumnya
    // membuat sesi; signInAnonymously early-return bila sudah login).
    await SafeAuth.signOutQuiet();
  });

  group('signUpWithEmail (regresi GoTrue)', () {
    test('email sudah ada & belum diverifikasi → kirim ulang OTP', () async {
      final id = await SafeAuth.instance.signUpWithEmail('baru@b.c', 'pw123456');

      expect(id, 'dup-1');
      // HARUS ada panggilan /resend — inilah perbaikannya.
      expect(
        captured.any((r) => r.url.path.endsWith('/resend')),
        isTrue,
        reason: 'signUp harus resend OTP saat identities kosong',
      );
    });

    test('email baru asli (identities berisi) → TIDAK kirim ulang OTP',
        () async {
      final id =
          await SafeAuth.instance.signUpWithEmail('fresh@b.c', 'pw123456');

      expect(id, 'new-1');
      expect(
        captured.any((r) => r.url.path.endsWith('/resend')),
        isFalse,
        reason: 'email baru asli sudah dapat OTP dari signup — jangan resend',
      );
    });

    test('kode OTP valid → verifyEmailOtp true, lastOtpError null', () async {
      final ok = await SafeAuth.instance.verifyEmailOtp('baru@b.c', '123456');

      expect(ok, isTrue);
      expect(SafeAuth.instance.lastOtpError, isNull);
      // Type OTP harus 'signup' (bukan email) — salah type = kode valid
      // ditolak server.
      final verifyReq =
          captured.lastWhere((r) => r.url.path.endsWith('/verify'));
      expect(verifyReq.body, contains('"type":"signup"'));
    });

    test('kode OTP salah/kedaluwarsa → false + pesan asli tersimpan',
        () async {
      final ok = await SafeAuth.instance.verifyEmailOtp('baru@b.c', '000000');

      expect(ok, isFalse);
      // Pesan asli GoTrue HARUS tersimpan agar UI bisa bedakan
      // kedaluwarsa vs salah (dulu ditelan → selalu generik).
      expect(SafeAuth.instance.lastOtpError, isNotNull);
      expect(
        SafeAuth.instance.lastOtpError!.toLowerCase(),
        contains('expired'),
      );
    });

    test('resend OTP mengarah ke endpoint /resend', () async {
      await SafeAuth.instance.resendEmailOtp('baru@b.c');
      expect(captured.any((r) => r.url.path.endsWith('/resend')), isTrue);
    });
  });

  group('login anonim (service)', () {
    test('signInAnonymously membuat sesi', () async {
      await SafeAuth.instance.signInAnonymously();
      expect(SafeAuth.instance.isSignedIn, isTrue);
      expect(SafeAuth.instance.isAnonymous, isTrue);
    });
  });
}

/// Wrapper tipis supaya test tidak bergantung pada global state yang
/// menahan sesi antar-test (sign out diam-diam tanpa network).
class SafeAuth {
  static final AuthService instance = AuthService();
  static Future<void> signOutQuiet() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }
}

/// Kumpulan request yang masuk ke mock server (untuk verifikasi).
/// Digabung ke file ini (dulu `auth_service_mock_server.dart`) supaya
/// satu sumber GoTrue palsu — pola `FakeSupabaseHandler` belum mencakup
/// `/auth/v1/*` (hanya PostgREST).
final List<http.Request> captured = [];

/// Mock HTTP server GoTrue minimal: cukup untuk mengunci perilaku
/// signup/OTP/resend yang pernah jadi bug ("kode tidak valid").
MockClient buildMockServer() {
  return MockClient((req) async {
    captured.add(req);
    final path = req.url.path;
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
    if (path.endsWith('/signup')) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final email = body['email'] as String?;
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
    if (path.endsWith('/resend')) {
      return http.Response('{}', 200,
          headers: {'content-type': 'application/json'});
    }
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
    if (path.contains('/rest/v1/rpc/check_email_registered')) {
      return http.Response('false', 200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response('{}', 200,
        headers: {'content-type': 'application/json'});
  });
}
