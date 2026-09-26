import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/app.dart' show decideGateScreen, GateScreen;

/// Urutan keputusan layar root — regresi "logout berkedip": signOut()
/// men-set `signingOut` DAN `loading`; kalau `loading` dicek lebih dulu,
/// gate menampilkan splash sekejap (satu halaman berkedip) sebelum
/// EntryScreen.
void main() {
  GateScreen decide({
    bool loading = false,
    bool hasError = false,
    bool signingOut = false,
    bool isAnonymous = false,
    bool dummySessionActive = false,
    bool isSignedIn = true,
    bool hasProfile = true,
    bool needsProfile = false,
    bool banned = false,
  }) =>
      decideGateScreen(
        loading: loading,
        hasError: hasError,
        signingOut: signingOut,
        isAnonymous: isAnonymous,
        dummySessionActive: dummySessionActive,
        isSignedIn: isSignedIn,
        hasProfile: hasProfile,
        needsProfile: needsProfile,
        banned: banned,
      );

  test('signingOut menang atas loading → entry (tanpa kedip splash)', () {
    expect(
      decide(signingOut: true, loading: true),
      GateScreen.entry,
      reason: 'logout tidak boleh menampilkan splash sekejap',
    );
  });

  test('signingOut sendirian → entry', () {
    expect(decide(signingOut: true), GateScreen.entry);
  });

  test('loading tanpa signingOut → splash', () {
    expect(decide(loading: true), GateScreen.splash);
  });

  test('error tanpa loading → layar error', () {
    expect(decide(hasError: true), GateScreen.error);
  });

  test('perlu profil + sesi ada → profileGate', () {
    expect(
      decide(needsProfile: true, isSignedIn: true),
      GateScreen.profileGate,
    );
  });

  test('perlu profil tapi sesi kosong → entry', () {
    expect(
      decide(needsProfile: true, isSignedIn: false),
      GateScreen.entry,
    );
  });

  test('anon tanpa profil → entry', () {
    expect(
      decide(isAnonymous: true, hasProfile: false),
      GateScreen.entry,
    );
  });

  test('nickname terlarang → banned', () {
    expect(decide(banned: true), GateScreen.banned);
  });

  test('normal → main', () {
    expect(decide(), GateScreen.main);
  });
}
