import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../utils.dart';
import '../services/auth_service.dart';
import '../services/geo_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? prefillEmail;
  // Data profile untuk di-register setelah login pertama kali (dari RegisterScreen)
  final String? pendingNickname;
  final String? pendingGender;
  final int? pendingAge;
  final String? pendingCountry;
  final String? pendingCity;
  final String? pendingIp;

  const LoginScreen({
    super.key,
    this.prefillEmail,
    this.pendingNickname,
    this.pendingGender,
    this.pendingAge,
    this.pendingCountry,
    this.pendingCity,
    this.pendingIp,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _emailCtrl;
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.prefillEmail ?? '');
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final s = context.read<LocaleProvider>().s;
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty) { _snack(s.errEmailEmpty); return; }
    if (!isValidEmail(email)) { _snack(s.errEmailInvalid); return; }
    if (password.isEmpty) { _snack(s.errPasswordShort); return; }

    setState(() => _loading = true);
    try {
      final auth = context.read<AuthProvider>();
      await auth.signInWithEmail(email, password);

      if (!mounted) return;

      // Catat IP di server (fire-and-forget, tidak block UI).
      // IP hanya disimpan di server, tidak disimpan di aplikasi.
      _recordIpToServer();

      // B1: Cek pending profile dari widget param ATAU SharedPreferences
      // (fallback jika app di-kill setelah signup sebelum registerProfile)
      // IP TIDAK disimpan di aplikasi — hanya dari widget param (memori)
      String? nickname = widget.pendingNickname;
      String? gender   = widget.pendingGender;
      int?    age      = widget.pendingAge;
      String? country  = widget.pendingCountry;
      String? city     = widget.pendingCity;
      String? ip       = widget.pendingIp;

      if (nickname == null && auth.profile == null) {
        final prefs = await SharedPreferences.getInstance();
        final savedEmail = prefs.getString('pending_email');
        if (savedEmail == email) {
          nickname = prefs.getString('pending_nickname');
          gender   = prefs.getString('pending_gender');
          age      = prefs.getInt('pending_age');
          country  = prefs.getString('pending_country');
          city     = prefs.getString('pending_city');
        }
      }

      // Register profile jika ada data pending dan profile belum ada
      if (nickname != null && auth.profile == null) {
        await auth.registerProfile(
          nickname: nickname,
          gender: gender ?? 'male',
          age: age ?? 18,
          country: country ?? 'Indonesia',
          city: city ?? 'Jakarta',
          ipAddress: ip ?? '',
        );
        // Hapus pending setelah berhasil
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pending_email');
        await prefs.remove('pending_nickname');
        await prefs.remove('pending_gender');
        await prefs.remove('pending_age');
        await prefs.remove('pending_country');
        await prefs.remove('pending_city');
      }

      if (!mounted) return;

      // E2: Login sukses tapi masih belum ada profile → arahkan ke form profil
      if (auth.profile == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => RegisterScreen(
            prefillEmail: email,
            mode: RegisterMode.profileOnly,
          )),
        );
        return;
      }

      // B2: postFrameCallback untuk hindari race condition _AuthGate rebuild
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    } on AuthException catch (e) {
      // B6: Gunakan AuthException bukan string matching
      if (!mounted) return;
      final s2 = context.read<LocaleProvider>().s;
      final code = e.code ?? e.message.toLowerCase();
      if (code.contains('invalid') || code.contains('credentials') || code.contains('wrong')) {
        _snack(s2.errInvalidCredentials);
      } else if (code.contains('verified') || code.contains('confirm')) {
        _snack(s2.errEmailNotVerified);
      } else {
        _snack('${s2.errGeneric}${e.message}');
      }
    } on Exception catch (e) {
      if (!mounted) return;
      final s2 = context.read<LocaleProvider>().s;
      _snack('${s2.errGeneric}$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final s = context.read<LocaleProvider>().s;
    String? submittedEmail;

    // Ctrl sengaja tidak di-dispose secara eksplisit — biarkan GC mengambil.
    // Disposal eksplisit berisiko memicu error "TextEditingController used
    // after being disposed" jika dialog animasi belum selesai saat dispose
    // dipanggil (terutama saat passwordRecovery event push route lain).
    final ctrl = TextEditingController(text: _emailCtrl.text);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.titleForgotPassword, style: const TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(labelText: s.labelEmail, hintText: s.hintEmail),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(s.btnCancel)),
          ElevatedButton(
            onPressed: () {
              final email = ctrl.text.trim();
              if (email.isEmpty) return;
              submittedEmail = email;
              Navigator.of(ctx).pop();
            },
            child: Text(s.btnSendReset),
          ),
        ],
      ),
    );

    if (submittedEmail != null && mounted) {
      try {
        await context.read<AuthProvider>().sendPasswordResetEmail(submittedEmail!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.msgPasswordResetSent)));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              e is EmailNotRegisteredException
                  ? s.msgEmailNotRegistered
                  : s.msgPasswordResetFailed)));
        }
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _signInWithGoogle() async {
    final s = context.read<LocaleProvider>().s;
    setState(() => _googleLoading = true);
    try {
      final result = await context.read<AuthProvider>().signInWithGoogle();
      if (!mounted) return;
      if (result == 'link_prompt') {
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
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const RegisterScreen()),
          );
        }
      } else if (result == 'new') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RegisterScreen()),
        );
      } else if (result == 'exists') {
        // Profile sudah ada — pop LoginScreen yang di-push di atas _AuthGate
        // supaya halaman utama (dari _AuthGate) terlihat.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      debugPrint('[GOOGLE] login signInWithGoogle error: $e');
      _snack('${s.errGoogleSignIn}$e');
    }
    if (mounted) setState(() => _googleLoading = false);
  }

  // Catat IP + lokasi (country/city) ke server saat login.
  // IP tidak disimpan di aplikasi — hanya dikirim ke DB.
  // Country/city ikut di-update agar sesuai lokasi login saat ini
  // (misal default Afghanistan saat daftar, dikoreksi ke lokasi asli).
  Future<void> _recordIpToServer() async {
    try {
      final geo = GeoService();
      final info = await geo.detect();
      if (info == null || info.ipAddress.isEmpty) return;
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      await auth.updateIpAddress(info.ipAddress);
      // Update country/city jika deteksi valid dan berbeda dari profile
      final profile = auth.profile;
      if (profile != null &&
          (profile.country != info.country || profile.city != info.city)) {
        await auth.updateProfile(country: info.country, city: info.city);
      }
    } catch (_) {
      // gagal mendeteksi IP — abaikan, jangan ganggu alur login
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      appBar: AppBar(title: Text(s.titleLogin)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset('assets/app_icon.png', width: 64, height: 64),
              ),
            ),
            const SizedBox(height: 20),

            // Email
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

            // Password
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: s.labelPassword,
                prefixIcon: const Icon(Icons.lock_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 6),

            // Lupa Password
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _forgotPassword,
                child: Text(s.btnForgotPassword, style: const TextStyle(color: AppTheme.primary, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 8),

            // Tombol Login
            ElevatedButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(s.btnLogin, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 16),

            // Divider
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(s.labelOr, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 12),

            // Login dengan Google
            OutlinedButton(
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
                        Text(s.btnContinueGoogle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      ],
                    ),
            ),
            const SizedBox(height: 12),

            // Link ke register
            Center(
              child: TextButton(
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                child: Text(s.btnRegisterEmail, style: const TextStyle(color: AppTheme.primary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
