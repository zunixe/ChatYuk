import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../services/geo_service.dart';
import '../services/location_service.dart';
import '../services/device_info_service.dart';
import '../utils.dart';
import 'register_screen.dart';
import 'login_screen.dart';
import 'donate_screen.dart';
import 'legal_screen.dart';
import '../providers/theme_provider.dart';
import '../widgets/profile_form_card.dart';
import '../widgets/auth_header.dart';

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final _nicknameCtrl = TextEditingController();
  final _nicknameFocus = FocusNode();
  final _geo = GeoService();
  String _gender = 'male';
  int _age = 18;
  late String _negara;
  late String _kota;
  String _ipAddress = '';
  bool _loading = false;
  bool _googleLoading = false;
  bool _entered = false; // guard: cegah double submit
  String? _nicknameError;
  Timer? _nicknameDebounce;

  @override
  void initState() {
    super.initState();
    // Default Indonesia (bukan Afghanistan) — fallback jika geo detect gagal
    _negara = 'Indonesia';
    _kota = getCitiesForCountry(_negara).first;
    _detectGeo();
  }

  Future<void> _detectGeo() async {
    // 1. Coba GPS presisi (tanpa memicu dialog — hanya bila izin sudah ada).
    GeoInfo? info;
    try {
      final gps = await LocationService().tryDevicePositionForRegister();
      if (gps != null) {
        info = await _geo.detectByCoordinates(gps.$1, gps.$2);
      }
    } catch (_) {}
    // 2. Fallback: IP geolocation.
    info ??= await _geo.detect();
    if (info == null || !mounted) return;
    final finalInfo = info;
    // IP selalu dicatat, walau negara tidak ada di daftar kota
    _ipAddress = finalInfo.ipAddress;
    final kotaList = kotaByNegara[finalInfo.country];
    if (kotaList == null || kotaList.isEmpty) return;
    // Kota: cocok nama -> terdekat dari koordinat -> kota pertama.
    final kota = matchCity(finalInfo.city, kotaList) ??
        ((finalInfo.lat != null && finalInfo.lon != null)
            ? nearestCity(
                finalInfo.lat!, finalInfo.lon!, finalInfo.country, kotaList)
            : null) ??
        kotaList.first;
    setState(() {
      _negara = finalInfo.country;
      _kota = kota;
    });
    // Auto-set bahasa dari lokasi — hanya jika belum pernah disimpan
    if (mounted) {
      await context.read<LocaleProvider>().setLangFromCountry(
        finalInfo.country,
      );
    }
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _nicknameFocus.dispose();
    _nicknameDebounce?.cancel();
    super.dispose();
  }

  void _onNicknameChanged(String val) {
    _nicknameDebounce?.cancel();
    if (val.length < 3) {
      setState(() => _nicknameError = null);
      return;
    }
    _nicknameDebounce = Timer(const Duration(milliseconds: 600), () async {
      final available = await context.read<AuthProvider>().isNicknameAvailable(
        val,
      );
      if (mounted) {
        final s = context.read<LocaleProvider>().s;
        setState(() => _nicknameError = available ? null : s.errNicknameTaken);
      }
    });
  }

  Future<void> _signInWithGoogle() async {
    final s = context.read<LocaleProvider>().s;
    setState(() => _googleLoading = true);
    try {
      final result = await context.read<AuthProvider>().signInWithGoogle();
      if (!mounted) return;
      // User membatalkan dialog Google — kembali diam-diam.
      if (result == 'canceled') return;
      if (result == 'link_prompt') {
        // Email sudah ada di akun lain — tanya apakah mau link
        final auth = context.read<AuthProvider>();
        final nickname = auth.pendingLinkNickname ?? s.unknownUser;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(s.btnLinkAccount),
            content: Text(s.msgLinkPrompt(nickname)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(s.btnCreateNew),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(s.btnUseExisting),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (confirm == true) {
          await context.read<AuthProvider>().confirmLinkGoogle();
        } else {
          context.read<AuthProvider>().cancelLinkGoogle();
          // Gate profil di _AuthGate menampilkan popup isian otomatis.
        }
      } else if (result == 'new') {
        // Gate profil di _AuthGate menampilkan popup isian otomatis.
      } else if (result == 'exists') {
        // Profile sudah ada — _AuthGate sudah menampilkan halaman utama,
        // tidak perlu navigasi tambahan (EntryScreen adalah home).
      }
      // 'exists' — profile sudah ada, _AuthGate handle navigasi otomatis
    } catch (e, st) {
      dlog('[GOOGLE] signInWithGoogle error: $e');
      dlog('[GOOGLE] stack: $st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errGoogleSignIn)));
      }
    } finally {
      // Reset spinner di semua path (sukses, batal, error).
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _enter() async {
    if (_entered) return; // guard double submit
    final s = context.read<LocaleProvider>().s;
    final nick = _nicknameCtrl.text.trim();
    if (nick.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errNicknameEmpty)));
      return;
    }
    if (nick.length < 3) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errNicknameShort)));
      return;
    }
    if (nick.length > 20) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errNicknameLong)));
      return;
    }
    if (!isValidNickname(nick)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errNicknameInvalid)));
      return;
    }
    if (_nicknameError != null) {
      _nicknameFocus.requestFocus();
      return;
    }

    _entered = true;
    setState(() => _loading = true);
    dlog('[ENTRY] _enter start nick=$nick');
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await context.read<AuthProvider>().registerProfile(
          nickname: nick,
          gender: _gender,
          age: _age,
          country: _negara,
          city: _kota,
          ipAddress: _ipAddress,
        );
        lastError = null;
        break;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        // Nickname taken → coba ambil alih (akun stale >7 hari) tanpa delay
        if (msg.contains('duplicate') || msg.contains('taken') || msg.contains('nickname')) {
          try {
            final claimed = await context.read<AuthProvider>().claimNickname(nick);
            if (claimed) {
              await context.read<AuthProvider>().registerProfile(
                nickname: nick, gender: _gender, age: _age, country: _negara, city: _kota, ipAddress: _ipAddress);
              lastError = null; break;
            }
          } catch (_) {}
        }
        lastError = e;
        dlog('[ENTRY] registerProfile attempt $attempt ERROR: $e');
        if (attempt < 3) await Future.delayed(Duration(milliseconds: attempt == 1 ? 500 : 800));
      }
    }
    if (lastError != null) {
      _entered = false; // allow retry on error
      if (mounted) {
        setState(() => _loading = false);
        final msg = lastError.toString().toLowerCase();
        if (msg.contains('duplicate') ||
            msg.contains('nickname') ||
            msg.contains('taken')) {
          setState(() => _nicknameError = s.errNicknameTaken);
          _nicknameFocus.requestFocus();
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
        }
      }
      return;
    }
    dlog('[ENTRY] registerProfile returned OK');
    // Catat identitas perangkat + install ID untuk pelacakan admin.
    unawaited(
      DeviceInfoService.instance.syncToServer(ipAddress: _ipAddress),
    );
    if (mounted) setState(() => _loading = false);
    dlog('[ENTRY] _enter done, loading=false');
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final requireRegistration = context
        .watch<AuthProvider>()
        .requireRegistration;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Background gambar "people chat" — semi transparan (opacity 20%).
          Positioned.fill(
            child: Opacity(
              opacity: 0.2,
              child: Image.asset('assets/people_chat.jpg', fit: BoxFit.cover),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                // Scroll: keyboard terbuka (ketik nickname) tidak overflow.
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Spacer elastis atas (mode wajib daftar) — grup utama tepat di tengah layar
                    // (scroll view: spacer diganti jarak tetap, Column tak lagi flex)
                    const SizedBox(height: 4),

                    // Header — widget yang SAMA dengan layar daftar.
                    AuthHeader(s: s),
                    SizedBox(height: 6),

                    // Kartu form — widget yang SAMA dengan popup profil.
                    if (!requireRegistration)
                      ProfileFormCard(
                        s: s,
                        nicknameCtrl: _nicknameCtrl,
                        nicknameFocus: _nicknameFocus,
                        nicknameError: _nicknameError,
                        onNicknameChanged: _onNicknameChanged,
                        onNicknameSubmitted: _enter,
                        gender: _gender,
                        onGenderChanged: (v) => setState(() => _gender = v),
                        age: _age,
                        onAgeChanged: (v) => setState(() => _age = v),
                        country: _negara,
                        onCountryChanged: (v) {
                          final cities = getCitiesForCountry(v);
                          setState(() {
                            _negara = v;
                            _kota = cities.isNotEmpty ? cities.first : '';
                          });
                        },
                        city: _kota,
                        onCityChanged: (v) => setState(() => _kota = v),
                        loading: _loading,
                        submitLabel: s.btnStartChat,
                        onSubmit: _enter,
                      ),
                    // Jarak tetap (dulu Spacer/Expanded max 32px — tak boleh
                    // flex di dalam scroll view, meledak unbounded)
                    const SizedBox(height: 24),

                    // Divider
                    if (!requireRegistration)
                      Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              s.labelOr,
                              style: AppText.bodySmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                    SizedBox(height: 4),

                    // Login dengan Google
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _googleLoading ? null : _signInWithGoogle,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.divider, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: EdgeInsets.symmetric(vertical: 10),
                          backgroundColor: AppTheme.bgCard,
                        ),
                        child: _googleLoading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.network(
                                    'https://www.google.com/favicon.ico',
                                    width: 20,
                                    height: 20,
                                    errorBuilder: (_, __, ___) => Icon(
                                      Icons.g_mobiledata,
                                      size: 22,
                                      color: Colors.red,
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    s.btnContinueGoogle,
                                    style: AppText.bodyStrong.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    SizedBox(height: 6),

                    // Daftar dengan Email
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => RegisterScreen()),
                        ),
                        icon: Icon(Icons.email_outlined, size: 18),
                        label: Text(s.btnRegisterEmail),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: BorderSide(color: AppTheme.primary),
                          padding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    SizedBox(height: 6),

                    // Sudah punya akun
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => LoginScreen()),
                        ),
                        child: Text(
                          s.btnLoginEmail,
                          style: TextStyle(color: AppTheme.primary),
                        ),
                      ),
                    ),
                    // Jarak tetap sebelum donasi (dulu Spacer/Expanded — sama,
                    // tak boleh flex di dalam scroll view)
                    const SizedBox(height: 24),

                    // Donasi
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DonateScreen()),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.favorite,
                              size: 16,
                              color: AppTheme.danger,
                            ),
                            SizedBox(width: 4),
                            Text(
                              s.titleDonate,
                              style: AppText.body.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 4),

                    // Persetujuan kebijakan privasi & perjanjian layanan
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text.rich(
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        TextSpan(
                          children: [
                            TextSpan(text: s.legalAgreementPre),
                            TextSpan(
                              text: s.legalPrivacyPolicy,
                              style: TextStyle(
                                color: AppTheme.primary,
                                decoration: TextDecoration.underline,
                                decorationColor: AppTheme.primary,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LegalScreen(
                                      kind: LegalKind.privacy,
                                    ),
                                  ),
                                ),
                            ),
                            TextSpan(text: s.legalAgreementAnd),
                            TextSpan(
                              text: s.legalServiceAgreement,
                              style: TextStyle(
                                color: AppTheme.primary,
                                decoration: TextDecoration.underline,
                                decorationColor: AppTheme.primary,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LegalScreen(
                                      kind: LegalKind.terms,
                                    ),
                                  ),
                                ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 4),
                  ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
