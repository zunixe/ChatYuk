import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';

/// Merge event realtime profil dengan state lokal berdasarkan kolom yang
/// HADIR di payload (gejala yang dikunci: Tentang tampil lalu hilang lagi
/// karena payload realtime tidak memuat kolom about yang di-revoke).
UserModel _user({
  String nickname = 'SimpleMe',
  String about = '',
  String status = 'online',
  String avatar = '',
  int points = 50,
  bool needsOnboarding = false,
}) => UserModel(
  uid: 'u1',
  nickname: nickname,
  gender: 'male',
  age: 25,
  country: 'Indonesia',
  city: 'Jakarta',
  ipAddress: '',
  status: status,
  avatar: avatar,
  isRegistered: true,
  loginAt: DateTime.utc(2026, 9, 25),
  createdAt: DateTime.utc(2026, 9, 25),
  lastSeen: DateTime.utc(2026, 9, 25),
  about: about,
  points: points,
  needsOnboarding: needsOnboarding,
);

void main() {
  group('mergeProfileEvent', () {
    test('kolom hilang di payload → pertahankan lokal (about)', () {
      final out = mergeProfileEvent(
        current: _user(about: 'halo'),
        event: _user(about: ''),
        presentKeys: {'id', 'nickname', 'status'},
      );
      expect(out.about, 'halo');
      expect(out.nickname, 'SimpleMe');
    });

    test('kolom hadir di payload → pakai event', () {
      final out = mergeProfileEvent(
        current: _user(nickname: 'Lama', about: 'lama'),
        event: _user(nickname: 'Baru', about: 'baru'),
        presentKeys: {'id', 'nickname', 'about'},
      );
      expect(out.nickname, 'Baru');
      expect(out.about, 'baru');
    });

    test('status/avatar hilang → pertahankan lokal', () {
      final out = mergeProfileEvent(
        current: _user(status: 'online', avatar: 'b64foto'),
        event: _user(status: 'offline', avatar: ''),
        presentKeys: {'id', 'nickname'},
      );
      expect(out.status, 'online');
      expect(out.avatar, 'b64foto');
    });

    test('current null → pakai event mentah', () {
      final out = mergeProfileEvent(
        current: null,
        event: _user(about: 'x'),
        presentKeys: const {},
      );
      expect(out.about, 'x');
    });

    test('points hadir → ikut event (badge tetap hidup)', () {
      final out = mergeProfileEvent(
        current: _user(points: 50),
        event: _user(points: 60),
        presentKeys: {'id', 'points'},
      );
      expect(out.points, 60);
    });

    // Regresi 2026-10-01: payload realtime TIDAK memuat needs_onboarding
    // (kolom non-publik) → event default false. Tanpa mempertahankan nilai
    // lokal, flag berubah true→false saat status/points berubah → user anon
    // baru langsung lolos ke MainNav ("login anon otomatis").
    test('needsOnboarding TIDAK hilang saat event realtime lain', () {
      final out = mergeProfileEvent(
        current: _user(needsOnboarding: true),
        event: _user(needsOnboarding: false), // payload tanpa kolom ini
        presentKeys: {'id', 'status', 'points'},
      );
      expect(out.needsOnboarding, isTrue);
    });
  });
}
