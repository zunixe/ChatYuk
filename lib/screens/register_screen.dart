import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../utils.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../services/auth_service.dart';
import '../services/geo_service.dart';
import '../services/location_service.dart';
import '../services/device_info_service.dart';
import '../main.dart';
import 'login_screen.dart';
import '../providers/theme_provider.dart';
import '../widgets/profile_form_card.dart';
import '../widgets/auth_header.dart';

enum RegisterMode { full, profileOnly }

class RegisterScreen extends StatefulWidget {
  final RegisterMode mode;
  final String? prefillEmail;

  const RegisterScreen({
    super.key,
    this.mode = RegisterMode.full,
    this.prefillEmail,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _geo = GeoService();

  String _gender = 'male';
  int _age = 18;
  String _negara = 'Indonesia';
  String _kota = 'Jakarta';
  String _ipAddress = '';
  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _nicknameError;
  Timer? _nicknameDebounce;
  final _nicknameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
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
    final cities = getCitiesForCountry(finalInfo.country);
    if (cities.isEmpty) return;
    // Kota: cocok nama -> terdekat dari koordinat -> kota pertama.
    final kota = matchCity(finalInfo.city, cities) ??
        ((finalInfo.lat != null && finalInfo.lon != null)
            ? nearestCity(
                finalInfo.lat!, finalInfo.lon!, finalInfo.country, cities)
            : null) ??
        cities.first;
    setState(() {
      _negara = finalInfo.country;
      _kota = kota;
      _ipAddress = finalInfo.ipAddress;
    });
    if (!mounted) return;
    await context.read<LocaleProvider>().setLangFromCountry(finalInfo.country);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
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

  Future<void> _register() async {
    final s = context.read<LocaleProvider>().s;
    final email = widget.prefillEmail ?? _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    final nickname = _nicknameCtrl.text.trim();
    final profileOnly = widget.mode == RegisterMode.profileOnly;

    // Validasi berbeda tergantung mode
    if (!profileOnly) {
      if (email.isEmpty) {
        _snack(s.errEmailEmpty);
        return;
      }
      if (!isValidEmail(email)) {
        _snack(s.errEmailInvalid);
        return;
      }
      if (password.length < 8) {
        _snack(s.errPasswordShort);
        return;
      }
      if (password != confirm) {
        _snack(s.errPasswordMismatch);
        return;
      }
    }
    if (nickname.isEmpty) {
      if (profileOnly) {
        _popupError(s.errNicknameEmpty);
      } else {
        _snack(s.errNicknameEmpty);
      }
      return;
    }
    if (nickname.length < 3) {
      if (profileOnly) {
        _popupError(s.errNicknameShort);
      } else {
        _snack(s.errNicknameShort);
      }
      return;
    }
    if (nickname.length > 20) {
      if (profileOnly) {
        _popupError(s.errNicknameLong);
      } else {
        _snack(s.errNicknameLong);
      }
      return;
    }
    if (_nicknameError != null) {
      _nicknameFocus.requestFocus();
      return;
    }

    // Cek nickname sekali lagi sebelum submit — set error di field, bukan snackbar
    setState(() {
      _nicknameError = null;
    });
    final available = await context.read<AuthProvider>().isNicknameAvailable(
      nickname,
    );
    if (!available) {
      setState(() => _nicknameError = s.errNicknameTaken);
      _nicknameFocus.requestFocus();
      return;
    }

    setState(() => _loading = true);
    try {
      if (profileOnly) {
        // E2: Mode profile only — user sudah login, langsung registerProfile
        await context.read<AuthProvider>().registerProfile(
          nickname: nickname,
          gender: _gender,
          age: _age,
          country: _negara,
          city: _kota,
          ipAddress: _ipAddress,
        );
        if (!mounted) return;
        // Profile selesai → kembali ke route root (AuthGate render _MainNav).
        _goToMain();
        return;
      }

      // Mode full: sign up → (bila perlu) verifikasi OTP → registerProfile
      final autoLogin = await context.read<AuthProvider>().signUpWithEmail(
        email: email,
        password: password,
        nickname: nickname,
        gender: _gender,
        age: _age,
        country: _negara,
        city: _kota,
      );
      if (!mounted) return;
      if (autoLogin) {
        // Email auto-confirm → langsung masuk.
        _goToMain();
        return;
      }
      // Perlu verifikasi OTP → tampilkan form kode.
      if (!mounted) return;
      final verified = await _showOtpDialog(
        email,
        nickname,
        _gender,
        _age,
        _negara,
        _kota,
      );
      if (!mounted) return;
      if (verified) {
        _goToMain();
      }
      return;
    } on Exception catch (e) {
      if (!mounted) return;
      if (e is EmailAlreadyRegisteredException) {
        // E1: email terdaftar tapi mungkin belum verified — kirim ulang verifikasi
        try {
          await context.read<AuthProvider>().resendVerificationEmail(email);
          if (mounted) _snack(s.msgEmailAlreadyRegisteredResend);
        } catch (_) {
          if (mounted) _snack(s.errEmailAlreadyUsed);
        }
      } else {
        final msg = e.toString().toLowerCase();
        if (msg.contains('no authenticated user')) {
          // Session hilang saat mode profileOnly — coba login anon lalu ulangi
          if (profileOnly) {
            try {
              await context.read<AuthProvider>().signInAnonymously();
              await context.read<AuthProvider>().registerProfile(
                nickname: nickname,
                gender: _gender,
                age: _age,
                country: _negara,
                city: _kota,
                ipAddress: _ipAddress,
              );
              if (!mounted) return;
              _goToMain();
              return;
            } catch (_) {
              if (mounted) {
                setState(() => _nicknameError = s.errNicknameTaken);
                _nicknameFocus.requestFocus();
              }
            }
          } else {
            _snack(s.errGeneric);
          }
        } else if (msg.contains('already') ||
            msg.contains('taken') ||
            msg.contains('duplicate')) {
          // Jika error mengandung "profiles_nickname_key" → nickname sudah dipakai
          if (msg.contains('nickname') || msg.contains('profiles_nickname')) {
            setState(() => _nicknameError = s.errNicknameTaken);
            _nicknameFocus.requestFocus();
          } else if (profileOnly) {
            _popupError(s.errEmailAlreadyUsed);
          } else {
            _snack(s.errEmailAlreadyUsed);
          }
        } else if (profileOnly) {
          _popupError(s.errGeneric);
        } else {
          _snack(s.errGeneric);
        }
      }
    } finally {
      // Catat identitas perangkat + install ID untuk pelacakan admin.
      unawaited(
        DeviceInfoService.instance.syncToServer(ipAddress: _ipAddress),
      );
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Mode popup: snackbar tertutup overlay _ProfileGate (blur) — error
  // ditampilkan inline di dalam kartu supaya selalu terlihat paling atas.
  void _popupError(String msg) {
    if (!mounted) return;
    setState(() => _nicknameError = msg);
    _nicknameFocus.requestFocus();
  }

  /// Dialog masukkan kode OTP + kirim ulang. Return true bila terverifikasi.
  Future<bool> _showOtpDialog(
    String email,
    String nickname,
    String gender,
    int age,
    String country,
    String city,
  ) async {
    final s = context.read<LocaleProvider>().s;
    final ctrl = TextEditingController();
    var resendCooldown = false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setInner) => AlertDialog(
              backgroundColor: AppTheme.bgCard,
              title: Text(s.titleVerifyEmail),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.msgVerifyCodeSent,
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: AppText.titleEmphasis.copyWith(letterSpacing: 8),
                    decoration: InputDecoration(
                      hintText: s.hintVerifyCode,
                      counterText: '',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: resendCooldown
                      ? null
                      : () async {
                          setInner(() => resendCooldown = true);
                          try {
                            await context.read<AuthProvider>().resendEmailOtp(
                              email,
                            );
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text(s.msgResendCodeSent)),
                              );
                            }
                          } catch (_) {}
                          Future.delayed(const Duration(seconds: 30), () {
                            if (ctx.mounted)
                              setInner(() => resendCooldown = false);
                          });
                        },
                  child: Text(s.btnResendCode),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                  ),
                  onPressed: () async {
                    final code = ctrl.text.trim();
                    if (code.length != 6) {
                      ScaffoldMessenger.of(
                        ctx,
                      ).showSnackBar(SnackBar(content: Text(s.errInvalidCode)));
                      return;
                    }
                    final ok = await context
                        .read<AuthProvider>()
                        .verifyEmailAndRegister(
                          email: email,
                          token: code,
                          nickname: nickname,
                          gender: gender,
                          age: age,
                          country: country,
                          city: city,
                        );
                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.pop(ctx, true);
                    } else {
                      ScaffoldMessenger.of(
                        ctx,
                      ).showSnackBar(SnackBar(content: Text(s.errInvalidCode)));
                    }
                  },
                  child: Text(
                    s.btnVerify,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  /// Kembali ke route root (AuthGate). Karena profile sudah terisi, AuthGate
  /// otomatis menampilkan halaman utama (_MainNav).
  void _goToMain() {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final profileOnly = widget.mode == RegisterMode.profileOnly;
    // Mode popup: padding nol — pembungkus _ProfileGate sudah memberi
    // jarak horizontal 24 + angkatan keyboard, supaya lebar kartu persis
    // sama dengan entry screen (layar − 48).
    final form = SingleChildScrollView(
        padding: profileOnly
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode popup: judul di LUAR kartu supaya kartu identik
            // dengan entry screen.
            if (profileOnly) AuthTitle(s.msgCompleteProfile),
            if (profileOnly) const SizedBox(height: 12),
            // Kartu form — widget yang SAMA dengan entry screen.
            ProfileFormCard(
              s: s,
              header: profileOnly
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            labelText: s.labelEmail,
                            hintText: s.hintEmail,
                            prefixIcon: Icon(
                              Icons.email_outlined,
                              size: 20,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePass,
                          style: TextStyle(color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            labelText: s.labelPassword,
                            hintText: s.hintPassword,
                            prefixIcon: Icon(
                              Icons.lock_outlined,
                              size: 20,
                              color: AppTheme.textSecondary,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePass
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                () => _obscurePass = !_obscurePass,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Konfirmasi Password
                        TextField(
                          controller: _confirmCtrl,
                          obscureText: _obscureConfirm,
                          style: TextStyle(color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            labelText: s.labelConfirmPassword,
                            prefixIcon: Icon(
                              Icons.lock_outlined,
                              size: 20,
                              color: AppTheme.textSecondary,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                      ],
                    ),
              nicknameCtrl: _nicknameCtrl,
              nicknameFocus: _nicknameFocus,
              nicknameError: _nicknameError,
              onNicknameChanged: _onNicknameChanged,
              onNicknameSubmitted: _register,
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
              submitLabel: profileOnly ? s.btnComplete : s.btnRegister,
              onSubmit: _register,
            ),
            const SizedBox(height: 8),

            // Link ke login — hanya mode full. Mode popup user SUDAH login
            // (Google), jadi link ini tidak relevan dan disembunyikan.
            if (!profileOnly) ...[
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: Text(
                    s.btnLoginEmail,
                    style: const TextStyle(color: AppTheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      );
    // Mode popup: tanpa Scaffold — Scaffold mengembang ke maxHeight
    // sehingga kartu tidak tepat di tengah; Material transparan cukup
    // (Material ancestor untuk TextField sudah ada dari _MainNav).
    if (profileOnly) {
      return Material(color: Colors.transparent, child: form);
    }
    // Mode full: komposisi sama dengan entry screen (bg + header + kartu).
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.2,
              child: Image.asset('assets/people_chat.jpg', fit: BoxFit.cover),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                AuthHeader(s: s),
                const SizedBox(height: 12),
                Expanded(child: form),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
