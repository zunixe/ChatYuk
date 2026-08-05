import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../utils.dart';
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

      // Jika ada pending profile (baru daftar, baru verifikasi), register profile-nya
      if (widget.pendingNickname != null && auth.profile == null) {
        await auth.registerProfile(
          nickname: widget.pendingNickname!,
          gender: widget.pendingGender ?? 'male',
          age: widget.pendingAge ?? 18,
          country: widget.pendingCountry ?? 'Indonesia',
          city: widget.pendingCity ?? 'Jakarta',
          ipAddress: widget.pendingIp ?? '',
        );
      }

      // _AuthGate akan otomatis routing ke _MainNav karena profile sudah ada
    } on Exception catch (e) {
      if (!mounted) return;
      final s2 = context.read<LocaleProvider>().s;
      final msg = e.toString().toLowerCase();
      if (msg.contains('invalid') || msg.contains('wrong') || msg.contains('credentials')) {
        _snack(s2.errInvalidCredentials);
      } else if (msg.contains('verified') || msg.contains('confirm')) {
        _snack(s2.errEmailNotVerified);
      } else {
        _snack('${s2.errGeneric}$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final s = context.read<LocaleProvider>().s;
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(context.read<LocaleProvider>().s.btnCancel)),
          ElevatedButton(
            onPressed: () async {
              final email = ctrl.text.trim();
              if (email.isEmpty) return;
              Navigator.of(ctx).pop();
              try {
                await context.read<AuthProvider>().sendPasswordResetEmail(email);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(s.msgPasswordResetSent)));
                }
              } catch (_) {}
            },
            child: Text(s.btnSendReset),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
