import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../config/strings.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../services/geo_service.dart';

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
    _entered = true;
    setState(() => _loading = true);
    print('[ENTRY] _enter start nick=$nick');
    try {
      await context.read<AuthProvider>().registerProfile(
            nickname: nick,
            gender: _gender,
            age: _age,
            country: _negara,
            city: _kota,
            ipAddress: _ipAddress,
          );
      print('[ENTRY] registerProfile returned OK');
    } catch (e) {
      print('[ENTRY] registerProfile ERROR: $e');
      _entered = false; // allow retry on error
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errGeneric}$e')));
      }
      return;
    }
    if (mounted) setState(() => _loading = false);
    print('[ENTRY] _enter done, loading=false');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),

              // Logo
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.primary, AppTheme.accent],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('💬', style: TextStyle(fontSize: 30)),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.accent],
                ).createShader(bounds),
                child: Text(
                  s.appTagline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.appSubtagline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),

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
              const SizedBox(height: 20),

              // Gender
              Row(
                children: [
                  Expanded(child: _genderCard('female', '👩', AppTheme.female, s.labelGenderFemale)),
                  const SizedBox(width: 12),
                  Expanded(child: _genderCard('male', '👨', AppTheme.male, s.labelGenderMale)),
                ],
              ),
              const SizedBox(height: 20),

              // Age & Country
              Row(
                children: [
                  Expanded(child: _ageDropdown(s)),
                  const SizedBox(width: 12),
                  Expanded(child: _countryDropdown(s)),
                ],
              ),
              const SizedBox(height: 20),

              // City
              _cityDropdown(s),
              const SizedBox(height: 28),

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
    final isId = s.isId;
    return DropdownButtonFormField<String>(
      value: _negara,
      decoration: InputDecoration(labelText: s.labelCountry),
      items: [
        for (final n in kotaByNegara.keys)
          DropdownMenuItem(value: n, child: Text(negaraLabel(n, isId))),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          _negara = v;
          _kota = kotaByNegara[v]!.first;
        });
      },
    );
  }

  Widget _cityDropdown(S s) {
    return DropdownButtonFormField<String>(
      value: _kota,
      decoration: InputDecoration(labelText: s.labelCity),
      items: [
        for (final k in kotaByNegara[_negara]!)
          DropdownMenuItem(value: k, child: Text(k)),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _kota = v);
      },
    );
  }
}
