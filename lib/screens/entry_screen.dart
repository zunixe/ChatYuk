import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../config/strings.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../services/geo_service.dart';
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
  final _geo = GeoService();
  String _gender = 'male';
  int _age = 18;
  late String _negara;
  late String _kota;
  String _ipAddress = '';
  bool _loading = false;
  bool _entered = false; // guard: cegah double submit

  @override
  void initState() {
    super.initState();
    _negara = kotaByNegara.keys.first;
    _kota = kotaByNegara[_negara]!.first;
    _detectGeo();
  }

  Future<void> _detectGeo() async {
    final info = await _geo.detect();
    if (info == null || !mounted) return;
    final kotaList = kotaByNegara[info.country];
    if (kotaList == null) return;
    setState(() {
      _negara = info.country;
      _kota = kotaList.contains(info.city) ? info.city : kotaList.first;
      _ipAddress = info.ipAddress;
    });
    // Auto-set bahasa dari IP — hanya jika belum pernah disimpan
    if (mounted) {
      await context.read<LocaleProvider>().setLangFromCountry(info.country);
    }
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
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
    _entered = true;
    setState(() => _loading = true);
    debugPrint('[ENTRY] _enter start nick=$nick');
    try {
      await context.read<AuthProvider>().registerProfile(
            nickname: nick,
            gender: _gender,
            age: _age,
            country: _negara,
            city: _kota,
            ipAddress: _ipAddress,
          );
      debugPrint('[ENTRY] registerProfile returned OK');
    } catch (e) {
      debugPrint('[ENTRY] registerProfile ERROR: $e');
      _entered = false; // allow retry on error
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errGeneric}$e')));
      }
      return;
    }
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

              // Logo — sama dengan icon aplikasi
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/app_icon.png',
                  width: 72,
                  height: 72,
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
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.appSubtagline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),

              // Nickname
              TextField(
                controller: _nicknameCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: s.hintNickname,
                  labelText: s.labelUsername,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _enter(),
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
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Divider
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('atau', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 12),

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
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: AppTheme.textPrimary,
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
                child: Text(emoji, style: const TextStyle(fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ageDropdown(S s) {
    return DropdownButtonFormField<int>(
      value: _age,
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
      value: validKota,
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
