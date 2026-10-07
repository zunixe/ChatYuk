import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../core/admin_gate.dart';
import '../core/cache/message_cache.dart';
import '../core/cache/photo_cache.dart';
import '../core/cache/post_photo_cache.dart';
import '../core/media/image_cache_hygiene.dart';
import '../core/photo_quality_pref.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/theme_provider.dart';
import 'account_screen.dart';
import 'notification_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'profile/widgets/profile_widgets.dart';
import 'settings/widgets/settings_menu_tile.dart';

/// Pengaturan (ala WhatsApp): Akun, Privasi, Notifikasi, Tampilan, Bantuan.
/// Isi dipindah dari Profil supaya Profil tinggal etalase (identitas,
/// galeri, sosial, poin) — perilaku tiap baris tidak berubah.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    // PERF (§26b): dulu `watch` penuh → SELURUH halaman
    // Settings rebuild tiap notify (avatar/location/heartbeat).
    final authSnap = ref.watch(
      authProvider.select(
        (a) => (
          isAnon: a.isAnonymous,
          dummyActive: a.dummySessionActive,
          isRealAdmin: a.isRealAdmin,
          notif: a.notificationsEnabled,
        ),
      ),
    );
    final locale = ref.watch(localeProvider);
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
                    onChanged: (v) => ProviderScope.containerOf(context, listen: false)
                        .read(authProvider.notifier)
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
                    onChanged: (v) => ProviderScope.containerOf(context, listen: false).read(localeProvider.notifier)
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
                    value: ref.watch(themeProvider.select((t) => t.isDark)),
                    onChanged: (v) =>
                        ref.read(themeProvider.notifier).setDark(v),
                    activeThumbColor: AppTheme.primary,
                  ),
                ),
                const Divider(height: 1, indent: 52),
                // Kualitas foto default (ala WhatsApp).
                const _PhotoQualityTile(),
                const Divider(height: 1, indent: 52),
                // Ukuran font chat — hanya berlaku di bubble chat.
                const ProfileChatFontTile(),
                const Divider(height: 1, indent: 52),
                // Bersihkan cache sementara (foto/pesan lama) — bantu app
                // tetap ringan tanpa hapus data user.
                const _ClearCacheTile(),
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
class _PhotoQualityTile extends ConsumerStatefulWidget {
  const _PhotoQualityTile();

  @override
  ConsumerState<_PhotoQualityTile> createState() => _PhotoQualityTileState();
}

class _PhotoQualityTileState extends ConsumerState<_PhotoQualityTile> {
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
    final s = ref.watch(localeProvider).s;
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

/// Tile "Bersihkan Cache" — kosongkan cache SEMENTARA (RAM pesan/foto +
/// bitmap + file foto lama) tanpa menghapus pesan/foto user.
///
/// Ini pelengkap dari auto-trim reaktif (memory pressure & background):
/// user bisa memaksa app ringan kapan saja, mis. saat terasa mulai ngelag.
/// Konfirmasi dulu karena ada efek "foto dimuat ulang" sesaat.
class _ClearCacheTile extends ConsumerStatefulWidget {
  const _ClearCacheTile();

  @override
  ConsumerState<_ClearCacheTile> createState() => _ClearCacheTileState();
}

class _ClearCacheTileState extends ConsumerState<_ClearCacheTile> {
  bool _busy = false;

  Future<void> _confirmAndClear() async {
    if (_busy) return;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.clearCacheConfirmTitle),
        content: Text(
          s.clearCacheConfirmBody,
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.btnClear),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    // RAM dulu (sinkron, instan) lalu disk lama (fire-and-forget tak menghambat).
    try {
      MessageCache.instance.trimMemCache();
    } catch (_) {}
    try {
      PhotoCache.instance.trimMemCache();
    } catch (_) {}
    try {
      PostPhotoCache.instance.trimMemCache();
    } catch (_) {}
    try {
      ImageCacheHygiene.clearAll();
    } catch (_) {}
    try {
      await PhotoCache.instance.cleanOldPhotos();
    } catch (_) {}
    try {
      await PostPhotoCache.instance.cleanOldPhotos();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(s.clearCacheDone)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    return SettingsMenuTile(
      icon: Icons.cleaning_services_outlined,
      iconColor: AppTheme.accent,
      title: s.clearCacheTitle,
      desc: s.clearCacheDesc,
      trailing: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _confirmAndClear,
    );
  }
}
