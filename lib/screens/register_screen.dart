import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../utils.dart';
import '../providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/locale_provider.dart';
import '../services/auth_service.dart';
import '../services/geo_service.dart';
import 'login_screen.dart';
import 'donate_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _kota = getCitiesForCountry(_negara).first;
    _detectGeo();
  }

  Future<void> _detectGeo() async {
    final info = await _geo.detect();
    if (info == null || !mounted) return;
    final cities = getCitiesForCountry(info.country);
    if (cities.isEmpty) return;
    setState(() {
      _negara = info.country;
      _kota = cities.contains(info.city) ? info.city : cities.first;
      _ipAddress = info.ipAddress;
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _nicknameCtrl.dispose();
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
    if (_nicknameError != null) { _snack(_nicknameError!); return; }

    // Cek nickname sekali lagi sebelum submit
    final available = await context.read<AuthProvider>().isNicknameAvailable(nickname);
    if (!available) { _snack(s.errNicknameTaken); return; }

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
        // Profile selesai → pop ke halaman utama
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        });
        return;
      }

      // Mode full: sign up → simpan pending → dialog verifikasi
      await context.read<AuthProvider>().signUpWithEmail(
        email: email,
        password: password,
        nickname: nickname,
        gender: _gender,
        age: _age,
        country: _negara,
        city: _kota,
      );

      // 2. Simpan pending profile ke SharedPreferences
      //    supaya tidak hilang kalau app di-kill sebelum registerProfile selesai
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_email', email);
      await prefs.setString('pending_nickname', nickname);
      await prefs.setString('pending_gender', _gender);
      await prefs.setInt('pending_age', _age);
      await prefs.setString('pending_country', _negara);
      await prefs.setString('pending_city', _kota);
      await prefs.setString('pending_ip', _ipAddress);

      if (!mounted) return;
      // Tampilkan dialog verifikasi email
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Row(children: [
            const Icon(Icons.mark_email_read_outlined, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(s.titleLogin, style: const TextStyle(color: AppTheme.textPrimary)),
          ]),
          content: Text(s.msgVerifyEmail, style: const TextStyle(color: AppTheme.textSecondary)),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                // Navigasi ke login screen
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => LoginScreen(
                    prefillEmail: email,
                    pendingNickname: nickname,
                    pendingGender: _gender,
                    pendingAge: _age,
                    pendingCountry: _negara,
                    pendingCity: _kota,
                    pendingIp: _ipAddress,
                  )),
                );
              },
              child: Text(s.btnLogin),
            ),
          ],
        ),
      );
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
        if (msg.contains('already') || msg.contains('taken') || msg.contains('duplicate')) {
          _snack(s.errEmailAlreadyUsed);
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

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final profileOnly = widget.mode == RegisterMode.profileOnly;
    return Scaffold(
      appBar: AppBar(title: Text(profileOnly ? s.msgCompleteProfile : s.titleRegister)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Email & Password — hanya tampil di mode full
            if (!profileOnly) ...[
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: s.labelEmail,
                  hintText: s.hintEmail,
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscurePass,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: s.labelPassword,
                  hintText: s.hintPassword,
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Konfirmasi Password
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: s.labelConfirmPassword,
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
            ],

            // Nickname
            TextField(
              controller: _nicknameCtrl,
              onChanged: _onNicknameChanged,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: s.labelUsername,
                hintText: s.hintNickname,
                prefixIcon: const Icon(Icons.person_outline),
                errorText: _nicknameError,
                suffixIcon: _nicknameError == null && _nicknameCtrl.text.length >= 3
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
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
                  : Text(s.btnRegister, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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

            // Tombol Donasi
            Center(
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DonateScreen())),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite, size: 16, color: AppTheme.danger),
                    SizedBox(width: 4),
                    Text('Donasi', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  ],
                ),
              ),
            ),
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : AppTheme.divider, width: selected ? 2 : 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: selected ? color : AppTheme.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _ageDropdown(s) {
    return DropdownButtonFormField<int>(
      value: _age,
      decoration: InputDecoration(labelText: s.labelAge),
      isExpanded: true,
      menuMaxHeight: 300,
      items: [for (int i = 13; i <= 80; i++) DropdownMenuItem(value: i, child: Text('$i'))],
      onChanged: (v) { if (v != null) setState(() => _age = v); },
    );
  }

  Widget _countryDropdown(s) {
    return DropdownButtonFormField<String>(
      value: _negara,
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
      value: validKota,
      decoration: InputDecoration(labelText: s.labelCity),
      isExpanded: true,
      menuMaxHeight: 350,
      items: [for (final k in cities) DropdownMenuItem(value: k, child: Text(k, overflow: TextOverflow.ellipsis))],
      onChanged: (v) { if (v != null) setState(() => _kota = v); },
    );
  }
}
