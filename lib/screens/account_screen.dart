import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/social_provider.dart';
import '../utils.dart';
import 'link_email_screen.dart';
import 'settings/widgets/settings_menu_tile.dart';

/// Akun (ala WhatsApp: Pengaturan › Akun): keamanan, email, keluar.
/// Hapus akun SEMBUNYI di menu ⋮ (AppBar) seperti WhatsApp.
/// Isi dipindah dari Profil tanpa ubah perilaku.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _loggingOut = false;
  // Status "punya password" di-cache di state (dulu FutureBuilder di build
  // → RPC tiap rebuild = flicker + boros). Fetch sekali di initState.
  bool _hasPassword = false;

  @override
  void initState() {
    super.initState();
    _hasPassword = context.read<AuthProvider>().hasPassword;
    Future.microtask(() async {
      final v = await context.read<AuthProvider>().fetchHasPassword();
      if (mounted) setState(() => _hasPassword = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final auth = context.watch<AuthProvider>();
    final isAnon = auth.isAnonymous;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(s.titleAccount),
        actions: [
          // Hapus akun tersembunyi di ⋮ (ala WhatsApp).
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            color: AppTheme.bgCard,
            onSelected: (v) {
              if (v == 'delete') _confirmDeleteAccount();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_forever_outlined,
                      size: 20,
                      color: AppTheme.danger,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      s.btnDeleteAccount,
                      style: AppText.bodyStrong.copyWith(
                        color: AppTheme.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        // Insets & kartu seragam dengan halaman Notifikasi.
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          if (isAnon) ...[
            // Peringatan anon + tombol amankan akun.
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.titleAccountSecurity,
                          style: AppText.bodySmall.copyWith(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.msgAnonymousWarning,
                          style: AppText.bodySmall.copyWith(
                            color: Colors.orange.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.msgAnonRetention7d,
                          style: AppText.bodySmall.copyWith(
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LinkEmailScreen()),
                ),
                icon: const Icon(Icons.security, size: 18),
                label: Text(s.btnSecureAccount),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Material(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                if (!isAnon) ...[
                  // Email + status verifikasi.
                  SettingsMenuTile(
                    icon: auth.emailConfirmed
                        ? Icons.verified_user
                        : Icons.warning_amber_rounded,
                    iconColor: auth.emailConfirmed
                        ? Colors.green
                        : Colors.orange,
                    title: auth.emailConfirmed
                        ? s.labelEmailVerified
                        : s.labelEmailUnverified,
                    desc: auth.userEmail ?? '-',
                  ),
                  const Divider(height: 1, indent: 52),
                  // Password: set (akun Google) / ganti (akun email).
                  SettingsMenuTile(
                    icon: auth.hasPassword
                        ? Icons.password
                        : Icons.lock_outline,
                    title: _hasPassword
                        ? s.btnChangePassword
                        : s.btnSetPassword,
                    desc: _hasPassword
                        ? s.descChangePassword
                        : s.descSetPassword,
                    onTap: () async {
                      final hasPw = await context
                          .read<AuthProvider>()
                          .fetchHasPassword();
                      if (context.mounted) {
                        setState(() => _hasPassword = hasPw);
                        _showPasswordDialog(context, isSet: !hasPw);
                      }
                    },
                  ),
                  const Divider(height: 1, indent: 52),
                ],
                // Keluar.
                SettingsMenuTile(
                  icon: Icons.power_settings_new,
                  iconColor: AppTheme.danger,
                  title: s.btnLogout,
                  titleColor: AppTheme.danger,
                  trailing: _loggingOut
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _loggingOut ? null : _confirmLogout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Dialog set password (akun Google) / ganti password (akun email).
  Future<void> _showPasswordDialog(
    BuildContext context, {
    required bool isSet,
  }) async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var loading = false;
    String? errorText;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: !loading,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text(isSet ? s.btnSetPassword : s.btnChangePassword),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isSet ? s.descSetPassword : s.descChangePassword,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              if (!isSet) ...[
                TextField(
                  controller: currentCtrl,
                  obscureText: true,
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: s.labelCurrentPassword,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: newCtrl,
                obscureText: true,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(labelText: s.labelPassword),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(labelText: s.labelConfirmPassword),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorText!,
                  style: AppText.caption.copyWith(color: AppTheme.danger),
                ),
              ],
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 10),
                side: BorderSide(color: AppTheme.divider),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                minimumSize: const Size(100, 36),
              ),
              onPressed: loading ? null : () => Navigator.pop(ctx, false),
              child: Text(
                s.btnCancel,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                minimumSize: const Size(100, 36),
              ),
              onPressed: loading
                  ? null
                  : () async {
                      final newPw = newCtrl.text;
                      final confirm = confirmCtrl.text;
                      if (newPw.length < 8) {
                        setState(() => errorText = s.errPasswordShort);
                        return;
                      }
                      if (newPw != confirm) {
                        setState(() => errorText = s.errPasswordMismatch);
                        return;
                      }
                      setState(() {
                        loading = true;
                        errorText = null;
                      });
                      try {
                        if (isSet) {
                          await auth.setPassword(newPw);
                        } else {
                          await auth.changePassword(currentCtrl.text, newPw);
                        }
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        final msg = e.toString();
                        setState(() {
                          loading = false;
                          errorText = msg.contains('Invalid login credentials')
                              ? s.errCurrentPasswordWrong
                              : '${s.errChangePassword}$msg';
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      s.btnSave,
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(isSet ? s.msgPasswordSet : s.msgPasswordChanged),
          ),
        );
    }
  }

  /// Hapus akun (Google Play account deletion requirement).
  /// Konfirmasi berlapis: dialog ringkasan → dialog ketik HAPUS/DELETE.
  Future<void> _confirmDeleteAccount() async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();

    // Admin dilarang self-delete di sisi server — tidak tampilkan menu.
    if (auth.isRealAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errDeleteAccountForbidden)));
      return;
    }

    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.delete_forever, color: AppTheme.danger, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text(s.btnDeleteAccount, style: AppText.title)),
          ],
        ),
        content: Text(
          s.confirmDeleteAccountBody,
          style: AppText.body.copyWith(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              s.btnCancel,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: Text(
              s.btnDeleteAccount,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    // Step 2: ketik HAPUS / DELETE — terima KEDUANYA di semua bahasa.
    final ctrl = TextEditingController();
    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(s.btnDeleteAccount, style: AppText.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.labelDeleteAccountConfirm,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              style: AppText.body.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: s.deleteAccountConfirmHint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              s.btnCancel,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ListenableBuilder(
            listenable: ctrl,
            builder: (ctx, _) => FilledButton(
              onPressed: isDeleteAccountConfirmValid(ctrl.text)
                  ? () => Navigator.of(ctx).pop(true)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.danger,
                disabledBackgroundColor: AppTheme.danger.withValues(alpha: 0.4),
              ),
              child: Text(
                s.btnDeleteAccount,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
    if (step2 != true || !mounted) return;

    try {
      if (auth.isAnonymous) {
        await context.read<SocialProvider>().clearAnonSocial();
      }
      await context.read<AuthProvider>().deleteMyAccount();
      await auth.signOut();
      chat.reset();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgDeleteAccountSuccess)));
      }
    } catch (e) {
      dlog('[ACCOUNT] delete account error: $e', tag: 'ACCOUNT');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errDeleteAccount)));
      }
    }
  }

  Future<void> _confirmLogout() async {
    final s = context.read<LocaleProvider>().s;
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.power_settings_new, color: AppTheme.danger, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text(s.btnLogout, style: AppText.title)),
          ],
        ),
        content: Text(
          s.confirmLogoutBody,
          style: AppText.body.copyWith(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              s.btnCancel,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: Text(
              s.btnLogout,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Kunci DULU (tile mati + spinner langsung) — baru jeda ±200ms supaya
    // fade-out dialog selesai SEBELUM root swap MainNav→EntryScreen.
    // Urutan balik (jeda dulu, kunci belakangan) bikin tombol hidup 200ms:
    // user mengira tap tak masuk → tap 2x → flow logout balapan → nyangkut
    // tidak ke halaman utama. Jeda ini anti-blink kartu anon (orange).
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    // Anon logout: hapus relasi sosialnya supaya followers/subscribers user
    // lain berkurang sesuai data sebenarnya. Dibatasi waktu + tidak boleh
    // MENGGAGALKAN logout.
    if (auth.isAnonymous) {
      try {
        await context.read<SocialProvider>().clearAnonSocial().timeout(
          const Duration(seconds: 5),
        );
      } catch (e) {
        dlog(
          '[ACCOUNT] clearAnonSocial saat logout dilewati: $e',
          tag: 'ACCOUNT',
        );
      }
    }
    // Logout TIDAK boleh menggantung karena jaringan: signOut punya timeout
    // sendiri, dan apa pun hasilnya user keluar (sesi lokal dibuang).
    try {
      await auth.signOut().timeout(const Duration(seconds: 8));
    } catch (e) {
      dlog(
        '[ACCOUNT] signOut timeout/error, lanjut paksa keluar: $e',
        tag: 'ACCOUNT',
      );
    } finally {
      try {
        chat.reset();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _loggingOut = false);
      // Verifikasi sesi benar-benar mati SEBELUM meninggalkan layar.
      // Tanpa ini, bila provider macet (state profil lama masih ada),
      // user tetap di tumpukan layar lama dan mengira logout gagal —
      // atau lebih buruk: mengira sudah keluar padahal sesi hidup.
      if (auth.isSignedIn || auth.profile != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errLogoutFailed)));
        return;
      }
      // Paksa kembali ke root: gate menampilkan EntryScreen (sesi kosong).
      // Ini jaring pengaman bila rebuild gate terlewat — route lama
      // (Pengaturan/Akun) tidak boleh tersisa setelah keluar.
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }
}

