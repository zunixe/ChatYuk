import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../core/admin_gate.dart';
import '../core/photo_quality_pref.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import 'account_screen.dart';
import 'notification_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'profile/widgets/profile_widgets.dart';
import 'settings/widgets/settings_menu_tile.dart';

/// Pengaturan (ala WhatsApp): Akun, Privasi, Notifikasi, Tampilan, Bantuan.
/// Isi dipindah dari Profil supaya Profil tinggal etalase (identitas,
/// galeri, sosial, poin) — perilaku tiap baris tidak berubah.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    // PERF (§26b): dulu `watch<AuthProvider>()` penuh → SELURUH halaman
    // Settings rebuild tiap AuthProvider notify (avatar/location/heartbeat).
    // `select` snapshot field yang dirender (value-type) saja.
    final authSnap = context.select<AuthProvider,
        ({bool isAnon, bool dummyActive, bool isRealAdmin, bool notif})>(
      (a) => (
        isAnon: a.isAnonymous,
        dummyActive: a.dummySessionActive,
        isRealAdmin: a.isRealAdmin,
        notif: a.notificationsEnabled,
      ),
    );
    final locale = context.watch<LocaleProvider>();
    final isAnon = authSnap.isAnon;
    final dummyActive = authSnap.dummyActive;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(title: Text(s.titleSettings)),
      body: ListView(
        // Insets & kartu seragam dengan halaman Notifikasi.
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          // Admin: tile buka panel — hanya ada di build admin
          // (di-inject lewat AdminGate oleh entry lib/main_admin.dart).
          if (!dummyActive && authSnap.isRealAdmin)
            ...?AdminGate.profileSettingsHeader?.call(context),
          Material(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Akun: keamanan, email, keluar & hapus akun.
                SettingsMenuTile(
                  icon: Icons.person_outline,
                  title: s.titleAccount,
                  desc: s.descAccount,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AccountScreen()),
                  ),
                ),
                const Divider(height: 1, indent: 52),
                // Notifikasi.
                SettingsMenuTile(
                  icon: Icons.notifications_outlined,
                  title: s.labelNotifications,
                  desc: s.notifEnabledDesc,
                  trailing: Switch(
                    value: authSnap.notif,
                    onChanged: (v) => context
                        .read<AuthProvider>()
                        .setNotificationsEnabled(v),
                    activeThumbColor: AppTheme.primary,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationSettingsScreen(),
                    ),
                  ),
                ),
                if (!isAnon) ...[
                  const Divider(height: 1, indent: 52),
                  // Privasi.
                  SettingsMenuTile(
                    icon: Icons.lock_outline,
                    title: s.privacyTitle,
                    desc: s.privacyHint,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacySettingsScreen(),
                      ),
                    ),
                  ),
                ],
                const Divider(height: 1, indent: 52),
                // Bahasa.
                SettingsMenuTile(
                  icon: Icons.language_outlined,
                  iconColor: AppTheme.accent,
                  title: s.labelLanguage,
                  desc: locale.isId ? '🇮🇩 Indonesia' : '🇬🇧 English',
                  trailing: Switch(
                    value: locale.isId,
                    onChanged: (v) => context
                        .read<LocaleProvider>()
                        .setLang(v ? 'id' : 'en'),
                    activeThumbColor: AppTheme.primary,
                  ),
                ),
                const Divider(height: 1, indent: 52),
                // Tema gelap/terang.
                SettingsMenuTile(
                  icon: Icons.dark_mode_outlined,
                  iconColor: AppTheme.accent,
                  title: s.labelTheme,
                  desc: s.descTheme,
                  trailing: Switch(
                    value: context.watch<ThemeProvider>().isDark,
                    onChanged: (v) =>
                        context.read<ThemeProvider>().setDark(v),
                    activeThumbColor: AppTheme.primary,
                  ),
                ),
                const Divider(height: 1, indent: 52),
                // Kualitas foto default (ala WhatsApp).
                const _PhotoQualityTile(),
                const Divider(height: 1, indent: 52),
                // Ukuran font chat — hanya berlaku di bubble chat.
                const ProfileChatFontTile(),
              ],
            ),
          ),
          // Admin: toggle khusus build admin (via AdminGate).
          if (!dummyActive && authSnap.isRealAdmin)
            ...?AdminGate.profileSettingsTail?.call(context),
        ],
      ),
    );
  }
}

/// Tile default kualitas foto kiriman (Standard/HD).
/// Mempengaruhi nilai awal toggle HD di preview composer.
class _PhotoQualityTile extends StatefulWidget {
  const _PhotoQualityTile();

  @override
  State<_PhotoQualityTile> createState() => _PhotoQualityTileState();
}

class _PhotoQualityTileState extends State<_PhotoQualityTile> {
  bool _hd = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    PhotoQualityPref.defaultHd.then((v) {
      if (mounted) {
        setState(() {
          _hd = v;
          _loaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return SettingsMenuTile(
      icon: Icons.hd_outlined,
      iconColor: AppTheme.accent,
      title: s.photoQualityTitle,
      desc: !_loaded
          ? null
          : (_hd ? s.photoQualityHdDesc : s.photoQualityStandardDesc),
      trailing: Switch(
        value: _hd,
        onChanged: (v) {
          setState(() => _hd = v);
          PhotoQualityPref.setDefaultHd(v);
        },
        activeThumbColor: AppTheme.primary,
      ),
    );
  }
}
