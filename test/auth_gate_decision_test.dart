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
    bool needsOnboarding = false,
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
        needsOnboarding: needsOnboarding,
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

  // ── needs_onboarding (regresi "login anon otomatis", 2026-10-04) ──
  // Trigger mencegah hantu membuat profil anon otomatis. Tanpa flag ini,
  // gate melihat hasProfile=true → anon langsung masuk app. Flag memaksa
  // anon tsb tetap ke EntryScreen sampai ia memilih nickname.
  test('anon + profil ada + needsOnboarding → entry (bukan langsung main)', () {
    expect(
      decide(isAnonymous: true, hasProfile: true, needsOnboarding: true),
      GateScreen.entry,
    );
  });

  test('anon + profil ada + tidak onboarding → main', () {
    expect(
      decide(isAnonymous: true, hasProfile: true, needsOnboarding: false),
      GateScreen.main,
    );
  });

  // REGRESI 2026-10-05: user REGISTERED (email/OTP) yang menutup app sebelum
  // memilih nickname tetap punya needs_onboarding=true + nickname 'AnonXXXX'.
  // Gate lama hanya menahan ANON → user registered berkeliaran 'AnonXXXX'
  // selamanya. Kini needs_onboarding menahan SEMUA (kecuali dummy).
  test('registered + needsOnboarding → entry (bukan main)', () {
    expect(
      decide(
        isAnonymous: false,
        isSignedIn: true,
        hasProfile: true,
        needsOnboarding: true,
      ),
      GateScreen.entry,
    );
  });

  test('registered + tidak onboarding → main', () {
    expect(
      decide(
        isAnonymous: false,
        isSignedIn: true,
        hasProfile: true,
        needsOnboarding: false,
      ),
      GateScreen.main,
    );
  });

  test('dummy (admin jadi anon) + onboarding → tetap main (bypass)', () {
    // needsProfile sudah mengecualikan dummy; needsOnboarding TIDAK boleh
    // memaksa dummy ke entry.
    expect(
      decide(
        isAnonymous: true,
        dummySessionActive: true,
        hasProfile: true,
        needsOnboarding: true,
      ),
      GateScreen.main,
    );
  });

  test('banned menang atas onboarding? tidak — onboarding (anon) dicek dulu', () {
    // Urutan: hasError/loading/signOut → needsProfile → anon(onboarding)
    // → banned. Anon dengan onboarding=true → entry (belum pilih nama).
    expect(
      decide(isAnonymous: true, hasProfile: true, needsOnboarding: true, banned: true),
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
