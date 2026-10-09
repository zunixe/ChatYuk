import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/social_provider.dart';
import '../utils.dart';
import '../widgets/phone_edit_dialog.dart';
import '../widgets/phone_verify_dialog.dart';
import '../widgets/verified_badge.dart';
import '../providers/riverpod/phone_verify_provider.dart';
import '../providers/riverpod/verified_provider.dart';
import 'link_email_screen.dart';
import 'settings/widgets/settings_menu_tile.dart';
import '../providers/riverpod/locale_provider.dart';

/// Akun (ala WhatsApp: Pengaturan › Akun): keamanan, email, keluar.
/// Hapus akun SEMBUNYI di menu ⋮ (AppBar) seperti WhatsApp.
/// Isi dipindah dari Profil tanpa ubah perilaku.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _loggingOut = false;
  // Keluar/HAPUS sedang berjalan (sejak konfirmasi akhir, SEBELUM RPC).
  // Menekan kartu peringatan anon + tombol amankan-akun selama proses —
  // provider `signingOut` baru true saat signOut() dipanggil, padahal
  // clearAnonSocial + deleteMyAccount jalan duluan (detik-an): frame rebuild
  // apa pun di antaranya membuat kartu kuning berkedip. Reset saat gagal.
  bool _leaving = false;
  // Status "punya password" di-cache di state (dulu FutureBuilder di build
  // → RPC tiap rebuild = flicker + boros). Fetch sekali di initState.
  bool _hasPassword = false;

  @override
  void initState() {
    super.initState();
    _hasPassword = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).hasPassword;
    // Status verifikasi HP bisa berubah di luar app (user menyelesaikan di
    // Telegram) → tarik status terbaru saat layar dibuka supaya badge akurat.
    // Dulu hanya di-refresh saat DIALOG verify dibuka → user yang sudah
    // verified dari Telegram tetap melihat status "belum" lalu ditawari isi
    // nomor lagi.
    Future.microtask(() async {
      final v = await ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).fetchHasPassword();
      if (mounted) setState(() => _hasPassword = v);
    });
    Future.microtask(() {
      if (!mounted) return;
      ProviderScope.containerOf(context, listen: false)
          .read(phoneVerifyProvider.notifier)
          .refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    // Badge terverifikasi nomor HP (realtime dari provider).
    final verified = ref.watch(phoneVerifyProvider.select((p) => p.verified));
    // PERF (§26b): dulu `watch<AuthNotifier>()` → SELURUH halaman rebuild
    // tiap `notifyListeners` AuthNotifier (heartbeat presence berkala) →
    // lag saat masuk menu Akun. Sekarang: `read` untuk memanggil method
    // (setPassword/signOut), `select` snapshot utk field yang dirender —
    // rebuild hanya bila field itu berubah.
    final (
      :isAnonymous,
      :signingOut,
      :emailConfirmed,
      :userEmail,
      :hasPassword,
      :profile,
    ) = ref.watch(
      authProvider.select(
        (a) => (
          isAnonymous: a.isAnonymous,
          signingOut: a.signingOut,
          emailConfirmed: a.emailConfirmed,
          userEmail: a.userEmail,
          hasPassword: a.hasPassword,
          profile: a.profile,
        ),
      ),
    );
    // Jangan tampilkan banner anon saat proses keluar (signingOut/_leaving)
    // — sesi belum kosong & isAnonymous masih true sekejap → banner berkedip.
    // `_leaving` menutup celah alur HAPUS akun: provider `signingOut` baru
    // true saat signOut(), padahal RPC hapus sudah jalan sebelumnya.
    final isAnon = isAnonymous && !signingOut && !_leaving;

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
      body: _leaving
          // Sedang keluar/hapus akun: tampilkan skeleton netral (tanpa kartu
          // Keamanan Akun/Daftarkan Email) supaya tidak ada FLASH halaman
          // sebelum gate swap ke EntryScreen.
          ? const _LeavingSkeleton()
          : ListView(
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
                    icon: emailConfirmed
                        ? Icons.verified_user
                        : Icons.warning_amber_rounded,
                    iconColor: emailConfirmed
                        ? Colors.green
                        : Colors.orange,
                    title: emailConfirmed
                        ? s.labelEmailVerified
                        : s.labelEmailUnverified,
                    desc: userEmail ?? '-',
                  ),
                  const Divider(height: 1, indent: 52),
                  // Password: set (akun Google) / ganti (akun email).
                  SettingsMenuTile(
                    icon: hasPassword
                        ? Icons.password
                        : Icons.lock_outline,
                    title: _hasPassword
                        ? s.btnChangePassword
                        : s.btnSetPassword,
                    desc: _hasPassword
                        ? s.descChangePassword
                        : s.descSetPassword,
                    onTap: () async {
                      final hasPw = await ProviderScope.containerOf(context, listen: false)
                          .read(authProvider.notifier)
                          .fetchHasPassword();
                      if (context.mounted) {
                        setState(() => _hasPassword = hasPw);
                        _showPasswordDialog(context, isSet: !hasPw);
                      }
                    },
                  ),
                  const Divider(height: 1, indent: 52),
                  // Tanggal lahir (date picker).
                  SettingsMenuTile(
                    icon: Icons.cake_outlined,
                    title: s.labelBirthDate,
                    desc: profile?.birthDate != null
                        ? _formatDate(profile!.birthDate!, s.isId)
                        : s.hintBirthDateNotSet,
                    onTap: () => _pickBirthDate(context),
                  ),
                  const Divider(height: 1, indent: 52),
                  // Nomor HP + badge terverifikasi.
                  SettingsMenuTile(
                    icon: Icons.phone_iphone_rounded,
                    title: s.labelPhone,
                    titleTrailing: verified
                        ? VerifiedBadge(
                            verified: true,
                            size: 15,
                            tooltip: s.phoneVerifiedBadge,
                          )
                        : null,
                    desc: (profile?.phone ?? '').isNotEmpty
                        ? profile!.phone
                        : s.hintPhoneNotSet,
                    onTap: () => _editPhone(context),
                  ),
                  const Divider(height: 1, indent: 52),
                ],
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
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
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

  /// Format tanggal lahir ramah bahasa (mis. "17 Agustus 1998").
  String _formatDate(DateTime d, bool isId) {
    const idMonths = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
    ];
    const enMonths = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final months = isId ? idMonths : enMonths;
    final m = months[(d.month - 1).clamp(0, 11)];
    return isId ? '${d.day} $m ${d.year}' : '$m ${d.day}, ${d.year}';
  }

  /// Dialog pemilih tanggal lahir. Menyimpan via AuthNotifier.updateProfile.
  Future<void> _pickBirthDate(BuildContext context) async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    final now = DateTime.now();
    final current = auth.profile?.birthDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: s.titlePickBirthDate,
    );
    if (picked == null || !mounted) return;
    try {
      await ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).updateProfile(birthDate: picked);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.msgBirthDateSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.errGeneric)),
      );
    }
  }

  /// Dialog input nomor HP sedunia: pilihan kode negara (+62, +60, …)
  /// + nomor lokal. Hasil disimpan E.164 (mis. +62812…).
  ///
  /// Alur:
  ///  - Nomor BELUM ada → input nomor → simpan → tawarkan verifikasi.
  ///  - Nomor SUDAH ada & sudah verified → tampilkan status (tak minta apa-apa).
  ///  - Nomor SUDAH ada & belum verified → LANGSUNG tawarkan verifikasi
  ///    (tanpa input nomor ulang) + opsi ganti nomor.
  Future<void> _editPhone(BuildContext context) async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    final existingPhone = auth.profile?.phone ?? '';
    final alreadyVerified = ProviderScope.containerOf(context, listen: false)
        .read(phoneVerifyProvider)
        .verified;

    // Sudah punya nomor: jangan minta isi ulang. Status verified → info saja;
    // belum verified → langsung tawarkan verifikasi Telegram.
    if (existingPhone.isNotEmpty) {
      if (alreadyVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.phoneVerifySuccess)),
        );
        return;
      }
      final ok = await showPhoneVerifyDialog(context, s);
      if (ok == true && mounted) {
        _markOwnVerified();
      }
      return;
    }

    final full = await showPhoneEditDialog(
      context,
      s,
      currentPhone: existingPhone,
      countryName: auth.profile?.country,
    );
    if (full == null || !mounted) return;
    try {
      await ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).updateProfile(phone: full);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.msgPhoneSaved)),
      );
      // Tawarkan verifikasi (badge emas) via Telegram. Nomor baru = status
      // verified di-reset server-side, jadi selalu tawarkan.
      final ok = await showPhoneVerifyDialog(context, s);
      if (ok == true && mounted) {
        _markOwnVerified();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.errGeneric)),
      );
    }
  }

  /// Tandai status verified milik sendiri agar badge langsung tampil tanpa
  /// menunggu refresh berikutnya.
  void _markOwnVerified() {
    if (!mounted) return;
    final uid = ProviderScope.containerOf(context, listen: false)
            .read(authProvider.notifier)
            .uid ??
        '';
    if (uid.isEmpty) return;
    ProviderScope.containerOf(context, listen: false)
        .read(phoneVerifyProvider.notifier)
        .refresh();
    ProviderScope.containerOf(context, listen: false)
        .read(verifiedProvider.notifier)
        .markVerified(uid);
  }

  /// Hapus akun (Google Play account deletion requirement).
  /// Konfirmasi berlapis: dialog ringkasan → dialog ketik HAPUS/DELETE.
  Future<void> _confirmDeleteAccount() async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    final chat = ProviderScope.containerOf(context, listen: false).read(chatProvider.notifier);

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

    // Tandai keluar SEJAK AWAL (sebelum RPC apa pun) supaya kartu peringatan
    // anon tidak sempat render lagi di frame mana pun selama proses hapus.
    // (Sengaja TIDAK memakai _loggingOut: spinner-nya milik tile Keluar dan
    // animasinya membuat pumpAndSettle tak pernah settle di test.)
    setState(() => _leaving = true);
    try {
      if (auth.isAnonymous) {
        await ProviderScope.containerOf(context, listen: false).read(socialProvider.notifier).clearAnonSocial();
      }
      await ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).deleteMyAccount();
      // Sesi: setelah profil+auth user dihapus server-side, signOut() biasa
      // bisa gagal (token sudah mati). signOut provider tahan-error & paksa
      // buang sesi lokal, tapi tetap dibungkus timeout agar tak menggantung.
      try {
        await auth.signOut().timeout(const Duration(seconds: 8));
      } catch (e) {
        dlog('[ACCOUNT] signOut setelah hapus akun error: $e', tag: 'ACCOUNT');
      }
      try {
        chat.reset();
      } catch (_) {}
      if (!mounted) return;
      // Paksa kembali ke root — gate menampilkan EntryScreen. Tanpa ini,
      // route lama (Pengaturan/Akun) tetap di stack → user bisa "back" ke
      // Pengaturan walau sudah terhapus (BUG dilaporkan user).
      Navigator.of(context).popUntil((r) => r.isFirst);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.msgDeleteAccountSuccess)));
      }
    } catch (e) {
      dlog('[ACCOUNT] delete account error: $e', tag: 'ACCOUNT');
      if (mounted) {
        // Gagal → user tetap di layar: kembalikan state agar kartu peringatan
        // anon tampil lagi (bila masih anon).
        setState(() => _leaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errDeleteAccount)));
      }
    }
  }

  Future<void> _confirmLogout() async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    final chat = ProviderScope.containerOf(context, listen: false).read(chatProvider.notifier);
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
    setState(() {
      _loggingOut = true;
      _leaving = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    // Anon logout: hapus relasi sosialnya supaya followers/subscribers user
    // lain berkurang sesuai data sebenarnya. Dibatasi waktu + tidak boleh
    // MENGGAGALKAN logout.
    if (auth.isAnonymous) {
      try {
        await ProviderScope.containerOf(context, listen: false).read(socialProvider.notifier).clearAnonSocial().timeout(
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
      // reset chat apa pun hasilnya
      try {
        chat.reset();
      } catch (_) {}
    }
    if (!mounted) return;
    // JANGAN reset `_leaving` di sini. Bila di-reset, ada 1 frame di mana
    // `_leaving=false` + `isAnonymous` masih true → kartu kuning "Keamanan
    // Akun / Daftarkan Email" muncul sekejap (FLASH) sebelum gate swap ke
    // EntryScreen. Biarkan `_leaving=true` (konten diganti skeleton) sampai
    // layar ini benar-benar di-pop.
    setState(() => _loggingOut = false);
    // Verifikasi sesi benar-benar mati SEBELUM meninggalkan layar.
    // Tanpa ini, bila provider macet (state profil lama masih ada),
    // user tetap di tumpukan layar lama dan mengira logout gagal —
    // atau lebih buruk: mengira sudah keluar padahal sesi hidup.
    if (auth.isSignedIn || auth.profile != null) {
      // Logout GAGAL → kembalikan tampilan normal (boleh interaksi lagi).
      setState(() => _leaving = false);
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

/// Skeleton netral saat user keluar / menghapus akun.
///
/// Tujuan: tidak menampilkan konten asli (kartu Keamanan Akun, tombol
/// Daftarkan Email, dst) sedetik sebelum layar ditutup — mencegah "flash".
/// STATIS (tanpa animasi) agar tidak ada spinner yang berputar terus
/// (membuat `pumpAndSettle` test tak pernah settle) — hanya bg layar polos.
class _LeavingSkeleton extends StatelessWidget {
  const _LeavingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}

