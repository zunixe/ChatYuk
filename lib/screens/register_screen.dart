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
import '../main.dart';
import 'login_screen.dart';
import '../providers/theme_provider.dart';

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
    setState(() {
      _negara = finalInfo.country;
      _kota = cities.contains(finalInfo.city) ? finalInfo.city : cities.first;
      _ipAddress = finalInfo.ipAddress;
    });
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
      final available = await context.read<AuthProvider>().isNicknameAvailable(val);
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
      if (email.isEmpty) { _snack(s.errEmailEmpty); return; }
      if (!isValidEmail(email)) { _snack(s.errEmailInvalid); return; }
      if (password.length < 8) { _snack(s.errPasswordShort); return; }
      if (password != confirm) { _snack(s.errPasswordMismatch); return; }
    }
    if (nickname.isEmpty) { _snack(s.errNicknameEmpty); return; }
    if (nickname.length < 3) { _snack(s.errNicknameShort); return; }
    if (nickname.length > 20) { _snack(s.errNicknameLong); return; }
    if (_nicknameError != null) {
      _nicknameFocus.requestFocus();
      return;
    }

    // Cek nickname sekali lagi sebelum submit — set error di field, bukan snackbar
    setState(() { _nicknameError = null; });
    final available = await context.read<AuthProvider>().isNicknameAvailable(nickname);
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
      final verified = await _showOtpDialog(email, nickname, _gender, _age, _negara, _kota);
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
            _snack('${s.errGeneric}$e');
          }
        } else if (msg.contains('already') || msg.contains('taken') || msg.contains('duplicate')) {
          // Jika error mengandung "profiles_nickname_key" → nickname sudah dipakai
          if (msg.contains('nickname') || msg.contains('profiles_nickname')) {
            setState(() => _nicknameError = s.errNicknameTaken);
            _nicknameFocus.requestFocus();
          } else {
            _snack(s.errEmailAlreadyUsed);
          }
        } else {
          _snack('${s.errGeneric}$e');
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
                  Text(s.msgVerifyCodeSent, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
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
                            await context.read<AuthProvider>().resendEmailOtp(email);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text(s.msgResendCodeSent)),
                              );
                            }
                          } catch (_) {}
                          Future.delayed(const Duration(seconds: 30), () {
                            if (ctx.mounted) setInner(() => resendCooldown = false);
                          });
                        },
                  child: Text(s.btnResendCode),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  onPressed: () async {
                    final code = ctrl.text.trim();
                    if (code.length != 6) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(s.errInvalidCode)));
                      return;
                    }
                    final ok = await context.read<AuthProvider>().verifyEmailAndRegister(
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
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(s.errInvalidCode)));
                    }
                  },
                  child: Text(s.btnVerify, style: const TextStyle(color: Colors.white)),
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
    return Scaffold(
      appBar: AppBar(title: Text(profileOnly ? s.msgCompleteProfile : s.titleRegister)),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kartu form — satu grup utuh, komposisi sama dengan login
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            // Email & Password — hanya tampil di mode full
            if (!profileOnly) ...[
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: s.labelEmail,
                  hintText: s.hintEmail,
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscurePass,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: s.labelPassword,
                  hintText: s.hintPassword,
                  prefixIcon: Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),
              SizedBox(height: 12),
              // Konfirmasi Password
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: s.labelConfirmPassword,
                  prefixIcon: Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Divider(),
              SizedBox(height: 8),
            ],

            // Nickname
            TextField(
              controller: _nicknameCtrl,
              focusNode: _nicknameFocus,
              onChanged: _onNicknameChanged,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: s.labelUsername,
                hintText: s.hintNickname,
                prefixIcon: const Icon(Icons.person_outline),
                errorText: null,
                suffixIcon: _nicknameError != null
                    ? const Icon(Icons.cancel, color: AppTheme.danger)
                    : _nicknameCtrl.text.length >= 3
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                enabledBorder: _nicknameError != null
                    ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger, width: 1.5))
                    : null,
                focusedBorder: _nicknameError != null
                    ? const OutlineInputBorder(borderSide: BorderSide(color: AppTheme.danger, width: 2))
                    : null,
              ),
            ),
            if (_nicknameError != null)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppTheme.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _nicknameError!,
                        style: AppText.bodySmall.copyWith(color: AppTheme.danger),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Gender
            Row(children: [
              Expanded(child: _genderCard('female', '👩', AppTheme.female, s.labelGenderFemale)),
              const SizedBox(width: 12),
              Expanded(child: _genderCard('male', '👨', AppTheme.male, s.labelGenderMale)),
            ]),
            const SizedBox(height: 12),

            // Umur & Negara
            Row(children: [
              Expanded(child: _ageDropdown(s)),
              const SizedBox(width: 12),
              Expanded(child: _countryDropdown(s)),
            ]),
            const SizedBox(height: 12),

            // Kota
            _cityDropdown(s),
            const SizedBox(height: 20),

            // Tombol Daftar
            ElevatedButton(
              onPressed: _loading ? null : _register,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(s.btnRegister, style: AppText.button),
            ),
                  ],
                ),
              ),
            const SizedBox(height: 8),

            // Link ke login
            Center(
              child: TextButton(
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: Text(s.btnLoginEmail, style: const TextStyle(color: AppTheme.primary)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _genderCard(String value, String emoji, Color color, String label) {
    final selected = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : AppTheme.divider, width: selected ? 2 : 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: TextStyle(fontSize: AppGlyph.sm)),
            SizedBox(width: 6),
            Text(label, style: AppText.bodySmall.copyWith(
              color: selected ? color : AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
    );
  }

  Widget _ageDropdown(s) {
    return DropdownButtonFormField<int>(
      initialValue: _age,
      decoration: InputDecoration(labelText: s.labelAge),
      isExpanded: true,
      menuMaxHeight: 300,
      items: [for (int i = 18; i <= 80; i++) DropdownMenuItem(value: i, child: Text('$i'))],
      onChanged: (v) { if (v != null) setState(() => _age = v); },
    );
  }

  Widget _countryDropdown(s) {
    return DropdownButtonFormField<String>(
      // Key memaksa rebuild saat deteksi geo mengubah _negara — tanpa ini
      // initialValue (dibaca sekali) tidak ikut ter-update setelah _detectGeo.
      key: ValueKey('country-$_negara'),
      initialValue: _negara,
      decoration: InputDecoration(labelText: s.labelCountry),
      isExpanded: true,
      menuMaxHeight: 350,
      items: [
        for (final n in kotaByNegara.keys)
          DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        if (v == null) return;
        final cities = getCitiesForCountry(v);
        setState(() { _negara = v; _kota = cities.isNotEmpty ? cities.first : ''; });
      },
    );
  }

  Widget _cityDropdown(s) {
    final cities = getCitiesForCountry(_negara);
    if (cities.isEmpty) return const SizedBox.shrink();
    final validKota = cities.contains(_kota) ? _kota : cities.first;
    return DropdownButtonFormField<String>(
      key: ValueKey('city-$validKota'),
      initialValue: validKota,
      decoration: InputDecoration(labelText: s.labelCity),
      isExpanded: true,
      menuMaxHeight: 350,
      items: [for (final k in cities) DropdownMenuItem(value: k, child: Text(k, overflow: TextOverflow.ellipsis))],
      onChanged: (v) { if (v != null) setState(() => _kota = v); },
    );
  }
}
