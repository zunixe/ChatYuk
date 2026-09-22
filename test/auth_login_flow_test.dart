import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/providers/auth_provider.dart';
import 'package:chatyuk/services/auth_service.dart';

import 'test_helper.dart';

class MockAuthService extends Mock implements AuthService {}

/// User GoTrue palsu untuk mengisi `currentUser` / AuthResponse.
User _user({
  String id = 'uid-1',
  String? email,
  bool anon = true,
  bool confirmed = false,
}) =>
    User.fromJson({
      'id': id,
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00.000Z',
      'is_anonymous': anon,
      if (email != null) 'email': email,
      if (confirmed) 'email_confirmed_at': '2026-01-01T00:00:00.000Z',
      'identities': [],
    })!;

UserModel _profile(String uid) => UserModel(
      uid: uid,
      nickname: 'Tester',
      gender: 'male',
      age: 20,
      country: 'Indonesia',
      city: 'Jakarta',
      ipAddress: '',
      status: 'online',
      avatar: '',
      isRegistered: false,
      loginAt: DateTime.utc(2026, 1, 1),
      createdAt: DateTime.utc(2026, 1, 1),
      lastSeen: DateTime.utc(2026, 1, 1),
    );

void main() {
  setUpAll(() async {
    await initSupabaseForTest();
  });

  late MockAuthService auth;
  late AuthProvider provider;

  /// Provider tanpa autoInit + notifikasi OFF supaya `updateFcmToken()`
  /// tidak menunggu Firebase (plugin tidak ada di test) — ini punya efek
  /// samping: test lebih cepat & tanpa timer menggantung.
  Future<AuthProvider> build() async {
    SharedPreferences.setMockInitialValues({'notif_enabled': false});
    final p = AuthProvider(authService: auth, autoInit: false);
    await p.loadNotificationPref();
    return p;
  }

  setUp(() {
    auth = MockAuthService();
    // Getter dasar yang sering disentuh jalur login.
    when(() => auth.dummySessionActive).thenReturn(false);
    when(() => auth.isSignedIn).thenReturn(true);
    when(() => auth.isAnonymous).thenReturn(true);
    when(() => auth.uid).thenReturn('uid-1');
    when(() => auth.userEmail).thenReturn(null);
    when(() => auth.emailConfirmed).thenReturn(false);
    when(() => auth.currentUser).thenReturn(null);
    when(() => auth.onMyProfileUpdates())
        .thenAnswer((_) => const Stream<UserModel>.empty());
  });

  tearDown(() => provider.dispose());

  group('login anonim', () {
    test('panggil service + simpan profile', () async {
      when(() => auth.signInAnonymously()).thenAnswer((_) async {});
      when(() => auth.getProfile()).thenAnswer((_) async => _profile('uid-1'));

      provider = await build();
      await provider.signInAnonymously();

      verify(() => auth.signInAnonymously()).called(1);
      verify(() => auth.getProfile()).called(1);
      expect(provider.profile?.uid, 'uid-1');
    });

    test('tetap aman saat profil belum ada (null)', () async {
      when(() => auth.signInAnonymously()).thenAnswer((_) async {});
      when(() => auth.getProfile()).thenAnswer((_) async => null);

      provider = await build();
      await provider.signInAnonymously();

      expect(provider.profile, isNull);
    });
  });

  group('login email + password', () {
    test('panggil service + ambil profil', () async {
      when(() => auth.signInWithEmail(any(), any())).thenAnswer((_) async {});
      when(() => auth.getProfile()).thenAnswer((_) async => _profile('uid-1'));

      provider = await build();
      await provider.signInWithEmail('a@b.c', 'rahasia123');

      verify(() => auth.signInWithEmail('a@b.c', 'rahasia123')).called(1);
      expect(provider.profile?.uid, 'uid-1');
    });

    test('error password salah diteruskan ke pemanggil', () async {
      when(() => auth.signInWithEmail(any(), any()))
          .thenThrow(const AuthException('Invalid login credentials'));

      provider = await build();
      expect(
        () => provider.signInWithEmail('a@b.c', 'salah'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('daftar email (signup + OTP)', () {
    test('signup tanpa auto-confirm → butuh OTP (return false)', () async {
      when(() => auth.signUpWithEmail(any(), any()))
          .thenAnswer((_) async => 'uid-1');
      when(() => auth.currentUser).thenReturn(_user(confirmed: false));

      provider = await build();
      final activated = await provider.signUpWithEmail(
        email: 'a@b.c',
        password: 'rahasia123',
        nickname: 'Tester',
        gender: 'male',
        age: 20,
        country: 'Indonesia',
        city: 'Jakarta',
      );

      expect(activated, isFalse);
      verify(() => auth.signUpWithEmail('a@b.c', 'rahasia123')).called(1);
    });

    test('signup dengan auto-confirm → langsung register profil', () async {
      when(() => auth.signUpWithEmail(any(), any()))
          .thenAnswer((_) async => 'uid-1');
      when(() => auth.currentUser).thenReturn(_user(confirmed: true));
      when(() => auth.registerProfile(
            nickname: any(named: 'nickname'),
            gender: any(named: 'gender'),
            age: any(named: 'age'),
            country: any(named: 'country'),
            city: any(named: 'city'),
            ipAddress: any(named: 'ipAddress'),
          )).thenAnswer((_) async => _profile('uid-1'));

      provider = await build();
      final activated = await provider.signUpWithEmail(
        email: 'a@b.c',
        password: 'rahasia123',
        nickname: 'Tester',
        gender: 'male',
        age: 20,
        country: 'Indonesia',
        city: 'Jakarta',
      );

      expect(activated, isTrue);
      expect(provider.profile?.uid, 'uid-1');
      verify(() => auth.registerProfile(
            nickname: 'Tester',
            gender: 'male',
            age: 20,
            country: 'Indonesia',
            city: 'Jakarta',
            ipAddress: any(named: 'ipAddress'),
          )).called(1);
    });

    test('email sudah terdaftar → lempar EmailAlreadyRegisteredException',
        () async {
      when(() => auth.signUpWithEmail(any(), any()))
          .thenThrow(EmailAlreadyRegisteredException());

      provider = await build();
      expect(
        () => provider.signUpWithEmail(
          email: 'a@b.c',
          password: 'rahasia123',
          nickname: 'Tester',
          gender: 'male',
          age: 20,
          country: 'Indonesia',
          city: 'Jakarta',
        ),
        throwsA(isA<EmailAlreadyRegisteredException>()),
      );
    });

    test('OTP benar → verifikasi lalu register profil', () async {
      when(() => auth.verifyEmailOtp(any(), any()))
          .thenAnswer((_) async => true);
      when(() => auth.lastOtpError).thenReturn(null);
      when(() => auth.registerProfile(
            nickname: any(named: 'nickname'),
            gender: any(named: 'gender'),
            age: any(named: 'age'),
            country: any(named: 'country'),
            city: any(named: 'city'),
            ipAddress: any(named: 'ipAddress'),
          )).thenAnswer((_) async => _profile('uid-1'));

      provider = await build();
      final ok = await provider.verifyEmailAndRegister(
        email: 'a@b.c',
        token: '123456',
        nickname: 'Tester',
        gender: 'male',
        age: 20,
        country: 'Indonesia',
        city: 'Jakarta',
      );

      expect(ok, isTrue);
      expect(provider.profile?.uid, 'uid-1');
    });

    test('OTP salah → return false + lastOtpError diteruskan (regresi)', () async {
      when(() => auth.verifyEmailOtp(any(), any()))
          .thenAnswer((_) async => false);
      when(() => auth.lastOtpError)
          .thenReturn('Token has expired or is invalid');

      provider = await build();
      final ok = await provider.verifyEmailAndRegister(
        email: 'a@b.c',
        token: '000000',
        nickname: 'Tester',
        gender: 'male',
        age: 20,
        country: 'Indonesia',
        city: 'Jakarta',
      );

      expect(ok, isFalse);
      // Pesan asli HARUS sampai ke UI — dulu ditelan dan selalu generik.
      expect(provider.lastOtpError, contains('expired'));
      verifyNever(() => auth.registerProfile(
            nickname: any(named: 'nickname'),
            gender: any(named: 'gender'),
            age: any(named: 'age'),
            country: any(named: 'country'),
            city: any(named: 'city'),
            ipAddress: any(named: 'ipAddress'),
          ));
    });

    test('kirim ulang OTP diteruskan ke service', () async {
      when(() => auth.resendEmailOtp(any())).thenAnswer((_) async {});

      provider = await build();
      await provider.resendEmailOtp('a@b.c');

      verify(() => auth.resendEmailOtp('a@b.c')).called(1);
    });
  });

  group('login Google', () {
    AuthResponse okResponse() => AuthResponse(user: _user(anon: false, email: 'g@gmail.com'));

    test('user baru tanpa profil lama → new', () async {
      when(() => auth.signInWithGoogle()).thenAnswer(
        (_) async =>
            (response: okResponse(), googleEmail: 'g@gmail.com'),
      );
      when(() => auth.checkEmailExists(any())).thenAnswer((_) async => null);
      when(() => auth.getProfile()).thenAnswer((_) async => null);

      provider = await build();
      final result = await provider.signInWithGoogle();

      expect(result, 'new');
      verify(() => auth.checkEmailExists('g@gmail.com')).called(1);
    });

    test('profil sudah ada → exists', () async {
      when(() => auth.signInWithGoogle()).thenAnswer(
        (_) async =>
            (response: okResponse(), googleEmail: 'g@gmail.com'),
      );
      when(() => auth.checkEmailExists(any())).thenAnswer((_) async => null);
      when(() => auth.getProfile())
          .thenAnswer((_) async => _profile('uid-1'));

      provider = await build();
      final result = await provider.signInWithGoogle();

      expect(result, 'exists');
    });

    test('email sudah dipakai akun lain → link_prompt', () async {
      when(() => auth.signInWithGoogle()).thenAnswer(
        (_) async =>
            (response: okResponse(), googleEmail: 'g@gmail.com'),
      );
      when(() => auth.checkEmailExists(any())).thenAnswer(
        (_) async => {'profile_id': 'old-uid', 'nickname': 'Lama'},
      );
      when(() => auth.getProfile()).thenAnswer((_) async => _profile('uid-1'));

      provider = await build();
      final result = await provider.signInWithGoogle();

      expect(result, 'link_prompt');
      expect(provider.pendingLinkNickname, 'Lama');
    });

    test('user batal pilih akun → canceled', () async {
      when(() => auth.signInWithGoogle()).thenAnswer((_) async => null);

      provider = await build();
      final result = await provider.signInWithGoogle();

      expect(result, 'canceled');
      verifyNever(() => auth.checkEmailExists(any()));
    });
  });

  // ── LOGOUT CLEAN (anti-flash halaman lain) ──
  // Gate root membaca `signingOut` untuk langsung merender EntryScreen.
  // Tanpa flag ini, `profile=null` sementara sesi bukan anon (mis. dummy
  // punya email) membuat gate menampilkan MainNav + popup form profil
  // sekejap sebelum EntryScreen.
  group('logout bersih', () {
    test('signingOut true selama logout, false setelah selesai', () async {
      when(() => auth.isSignedIn).thenReturn(true);
      when(() => auth.goOffline()).thenAnswer((_) async {});
      when(() => auth.signOut()).thenAnswer((_) async {});
      when(() => auth.dummySessionActive).thenReturn(true);

      provider = await build();
      expect(provider.signingOut, isFalse, reason: 'awal: tidak sedang keluar');

      // Rekam nilai signingOut saat proses berjalan (setelah flag diset,
      // sebelum finally mengembalikannya).
      bool? duringFlag;
      bool? duringLoading;
      when(() => auth.signOut()).thenAnswer((_) async {
        duringFlag = provider.signingOut;
        duringLoading = provider.loading;
      });

      await provider.signOut();

      expect(duringFlag, isTrue, reason: 'flag aktif selama proses keluar');
      expect(duringLoading, isTrue, reason: 'loading aktif (transisi keluar)');
      expect(provider.signingOut, isFalse, reason: 'flag dibersihkan di akhir');
      expect(provider.profile, isNull, reason: 'profil dibuang');
    });

    test('signingOut false setelah _init (login/restore baru)', () async {
      when(() => auth.isSignedIn).thenReturn(false);
      when(() => auth.signInAnonymously()).thenAnswer((_) async {});
      when(() => auth.getProfile()).thenAnswer((_) async => _profile('uid-1'));
      when(() => auth.dummySessionActive).thenReturn(false);

      provider = await build();
      // _init dipanggil saat bootstrap; pastikan flag tidak nyangkut true.
      await provider.retry();

      expect(provider.signingOut, isFalse);
    });
  });
}
