import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../config/strings.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../services/geo_service.dart';
import '../services/location_service.dart';
import '../utils.dart';
import 'register_screen.dart';
import 'login_screen.dart';
import 'donate_screen.dart';

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
    if (kotaList == null) return;
    setState(() {
      _negara = finalInfo.country;
      _kota = kotaList.contains(finalInfo.city) ? finalInfo.city : kotaList.first;
    });
    // Auto-set bahasa dari lokasi — hanya jika belum pernah disimpan
    if (mounted) {
      await context.read<LocaleProvider>().setLangFromCountry(finalInfo.country);
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
      final available = await context.read<AuthProvider>().isNicknameAvailable(val);
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
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RegisterScreen(mode: RegisterMode.profileOnly)),
          );
        }
      } else if (result == 'new') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RegisterScreen(mode: RegisterMode.profileOnly)),
        );
      } else if (result == 'exists') {
        // Profile sudah ada — _AuthGate sudah menampilkan halaman utama,
        // tidak perlu navigasi tambahan (EntryScreen adalah home).
      }
      // 'exists' — profile sudah ada, _AuthGate handle navigasi otomatis
    } catch (e) {
      debugPrint('[GOOGLE] signInWithGoogle error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.errGoogleSignIn}$e')),
        );
      }
    }
    if (mounted) setState(() => _googleLoading = false);
  }

  Future<void> _enter() async {
    if (_entered) return; // guard double submit
    final s = context.read<LocaleProvider>().s;
    final nick = _nicknameCtrl.text.trim();
    if (nick.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errNicknameEmpty)));
      return;
    }
    if (nick.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errNicknameShort)));
      return;
    }
    if (nick.length > 20) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errNicknameLong)));
      return;
    }
    if (!isValidNickname(nick)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errNicknameInvalid)));
      return;
    }
    if (_nicknameError != null) {
      _nicknameFocus.requestFocus();
      return;
    }

    // Cek duplicate sebelum submit
    final available = await context.read<AuthProvider>().isNicknameAvailable(nick);
    if (!available) {
      setState(() => _nicknameError = s.errNicknameTaken);
      _nicknameFocus.requestFocus();
      return;
    }

    _entered = true;
    setState(() => _loading = true);
    debugPrint('[ENTRY] _enter start nick=$nick');
    // Retry ringan: jaringan (DNS) kadang gagal sesaat saat ganti user.
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
        lastError = e;
        debugPrint('[ENTRY] registerProfile attempt $attempt ERROR: $e');
        if (attempt < 3) await Future.delayed(const Duration(seconds: 2));
      }
    }
    if (lastError != null) {
      _entered = false; // allow retry on error
      if (mounted) {
        setState(() => _loading = false);
        final msg = lastError.toString().toLowerCase();
        if (msg.contains('duplicate') || msg.contains('nickname') || msg.contains('taken')) {
          setState(() => _nicknameError = s.errNicknameTaken);
          _nicknameFocus.requestFocus();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errGeneric}$lastError')));
        }
      }
      return;
    }
    debugPrint('[ENTRY] registerProfile returned OK');
    if (mounted) setState(() => _loading = false);
    debugPrint('[ENTRY] _enter done, loading=false');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),

              // Logo — animasi halus dalam lingkaran transparan
              // (komposisi sama dengan halaman login).
              Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const _AnimatedLogo(),
                ),
              ),
              const SizedBox(height: 12),

              // Title
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.accent],
                ).createShader(bounds),
                child: Text(
                  s.appTagline,
                  textAlign: TextAlign.center,
                  style: AppText.display.copyWith(
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.appSubtagline,
                textAlign: TextAlign.center,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),

              // Kartu form — satu grup utuh, komposisi sama dengan login
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.divider, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
              // Nickname
              TextField(
                controller: _nicknameCtrl,
                focusNode: _nicknameFocus,
                onChanged: _onNicknameChanged,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: s.hintNickname,
                  labelText: s.labelUsername,
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
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _enter(),
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
              const SizedBox(height: 10),

              // Gender
              Row(
                children: [
                  Expanded(child: _genderCard('female', '👩', AppTheme.female, s.labelGenderFemale)),
                  const SizedBox(width: 12),
                  Expanded(child: _genderCard('male', '👨', AppTheme.male, s.labelGenderMale)),
                ],
              ),
              const SizedBox(height: 10),

              // Age & Country
              Row(
                children: [
                  Expanded(child: _ageDropdown(s)),
                  const SizedBox(width: 12),
                  Expanded(child: _countryDropdown(s)),
                ],
              ),
              const SizedBox(height: 10),

              // City
              _cityDropdown(s),
              const SizedBox(height: 12),

              // Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _enter,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          s.btnStartChat,
                          style: const TextStyle(letterSpacing: 1),
                        ),
                ),
              ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Divider
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(s.labelOr, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 12),

              // Login dengan Google
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _googleLoading ? null : _signInWithGoogle,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.divider, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.white,
                  ),
                  child: _googleLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.network(
                              'https://www.google.com/favicon.ico',
                              width: 20, height: 20,
                              errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 22, color: Colors.red),
                            ),
                            const SizedBox(width: 10),
                            Text(s.btnContinueGoogle, style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 8),

              // Daftar dengan Email
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterScreen())),
                  icon: const Icon(Icons.email_outlined, size: 18),
                  label: Text(s.btnRegisterEmail),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Sudah punya akun
              Center(
                child: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen())),
                  child: Text(s.btnLoginEmail, style: const TextStyle(color: AppTheme.primary)),
                ),
              ),
              const SizedBox(height: 8),

              // Donasi
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DonateScreen())),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite, size: 16, color: AppTheme.danger),
                      const SizedBox(width: 4),
                      Text(s.titleDonate, style: AppText.body.copyWith(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _genderCard(String value, String emoji, Color color, String label) {
    final selected = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : AppTheme.divider,
            width: selected ? 2 : 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? color : AppTheme.textSecondary,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: AppText.label.copyWith(
                  letterSpacing: 0,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: AppGlyph.sm)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ageDropdown(S s) {
    return DropdownButtonFormField<int>(
      initialValue: _age,
      decoration: InputDecoration(labelText: s.labelAge),
      items: [
        for (int i = 13; i <= 60; i++)
          DropdownMenuItem(value: i, child: Text('$i')),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _age = v);
      },
    );
  }

  Widget _countryDropdown(S s) {
    return DropdownButtonFormField<String>(
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
        setState(() {
          _negara = v;
          _kota = cities.isNotEmpty ? cities.first : '';
        });
      },
    );
  }

  Widget _cityDropdown(S s) {
    final cities = getCitiesForCountry(_negara);
    if (cities.isEmpty) return const SizedBox.shrink();
    // Ensure _kota is valid for current country
    final validKota = cities.contains(_kota) ? _kota : cities.first;
    return DropdownButtonFormField<String>(
      initialValue: validKota,
      decoration: InputDecoration(labelText: s.labelCity),
      isExpanded: true,
      menuMaxHeight: 350,
      items: [
        for (final k in cities)
          DropdownMenuItem(value: k, child: Text(k, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _kota = v);
      },
    );
  }
}

/// Logo app dengan animasi halus: ayun kiri-kanan, mengambang naik-turun,
/// dan denyut opacity seperti asap. Skala seragam → ikon tetap proporsional.
class _AnimatedLogo extends StatefulWidget {
  const _AnimatedLogo();

  @override
  State<_AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<_AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value * 2 * math.pi;
        return Transform.translate(
          offset: Offset(math.sin(t) * 8, math.sin(t * 2) * 5 - 2),
          child: Opacity(
            opacity: 0.85 + 0.15 * math.sin(t * 2 + math.pi / 2),
            child: Transform.scale(
              scale: 1.0 + 0.05 * math.sin(t),
              child: child,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          'assets/app_icon.png',
          width: 72,
          height: 72,
        ),
      ),
    );
  }
}
