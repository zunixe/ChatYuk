import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../models/privacy_settings.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/riverpod/privacy_provider.dart';
import 'privacy_settings/widgets/privacy_exclusions_sheet.dart';

/// Pengaturan Privasi — struktur & gaya sama dengan halaman Notifikasi
/// (kartu bgCard, ikon lingkaran 36, divider indent 52).
///
/// 6 pilihan per bagian:
///   Semua orang / Semua orang kecuali... / Teman saya /
///   Teman saya kecuali... / Hanya orang tertentu / Tidak ada
/// Opsi pemilih orang ("kecuali..." & "hanya orang tertentu") memakai satu
/// picker yang sama; "Teman kecuali..." dibatasi ke teman saja.
class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  ConsumerState<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends ConsumerState<PrivacySettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = ref.read(privacyProvider.notifier);
      p.load();
      // Daftar excludable dimuat awal juga supaya jumlah "(n)" akurat.
      p.ensureExcludable();
    });
  }

  /// Ikon spesifik per opsi visibilitas — biar sekali lihat langsung paham.
  IconData _icon(PrivacyVisibility value) {
    return switch (value) {
      PrivacyVisibility.everyone => Icons.public,
      PrivacyVisibility.everyoneExcept => Icons.person_remove_alt_1,
      PrivacyVisibility.friends => Icons.people_alt,
      PrivacyVisibility.friendsExcept => Icons.group_remove,
      PrivacyVisibility.only => Icons.verified_user,
      PrivacyVisibility.nobody => Icons.lock,
    };
  }

  /// Deskripsi singkat tiap opsi (sub-judul).
  String _desc(S s, PrivacyVisibility value) {
    return switch (value) {
      PrivacyVisibility.everyone => s.privacyEveryoneDesc,
      PrivacyVisibility.everyoneExcept => s.privacyEveryoneExceptDesc,
      PrivacyVisibility.friends => s.privacyFriendsDesc,
      PrivacyVisibility.friendsExcept => s.privacyFriendsExceptDesc,
      PrivacyVisibility.only => s.privacyOnlyDesc,
      PrivacyVisibility.nobody => s.privacyNobodyDesc,
    };
  }

  String _label(S s, PrivacyVisibility value) {
    return switch (value) {
      PrivacyVisibility.everyone => s.privacyEveryone,
      PrivacyVisibility.everyoneExcept => s.privacyEveryoneExcept,
      PrivacyVisibility.friends => s.privacyFriends,
      PrivacyVisibility.friendsExcept => s.privacyFriendsExcept,
      PrivacyVisibility.only => s.privacyOnly,
      PrivacyVisibility.nobody => s.privacyNobody,
    };
  }

  PrivacyVisibility _valueOf(String field, PrivacySettings p) {
    return switch (field) {
      'presence' => p.presence,
      'last_seen' => p.lastSeen,
      'profile_photo' => p.profilePhoto,
      'about' => p.about,
      'story' => p.story,
      'leaderboard' => p.leaderboard,
      _ => PrivacyVisibility.everyone,
    };
  }

  String _titleForField(S s, String field) {
    return switch (field) {
      'presence' => s.privacyPresence,
      'last_seen' => s.privacyLastSeen,
      'profile_photo' => s.privacyProfilePhoto,
      'about' => s.privacyAbout,
      'story' => s.privacyStory,
      'leaderboard' => s.privacyLeaderboard,
      _ => s.privacyTitle,
    };
  }

  /// Nilai tile: untuk opsi bercabang (kecuali.../hanya orang tertentu)
  /// sekaligus tampil jumlah orangnya.
  String _valueLabel(S s, String field, PrivacySettings p) {
    final value = _valueOf(field, p);
    final n = (p.exclusions[field] ?? const {}).length;
    if (value == PrivacyVisibility.everyoneExcept) {
      return s.privacyEveryoneExceptCount(n);
    }
    if (value == PrivacyVisibility.friendsExcept) {
      return s.privacyFriendsExceptCount(n);
    }
    if (value == PrivacyVisibility.only) {
      return s.privacyOnlyCount(n);
    }
    return _label(s, value);
  }

  Future<void> _applyField(String field, PrivacyVisibility value) async {
    final provider = ref.read(privacyProvider.notifier);
    switch (field) {
      case 'presence':
        await provider.update(presence: value);
      case 'last_seen':
        await provider.update(lastSeen: value);
      case 'profile_photo':
        await provider.update(profilePhoto: value);
      case 'about':
        await provider.update(about: value);
      case 'story':
        await provider.update(story: value);
      case 'leaderboard':
        await provider.update(leaderboard: value);
    }
  }

  Future<void> _choose(String field, PrivacySettings p) async {
    final s = context.read<LocaleProvider>().s;
    final current = _valueOf(field, p);
    final selected = await showModalBottomSheet<PrivacyVisibility>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_titleForField(s, field), style: AppText.title),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  children: [
                    for (final value in PrivacyVisibility.values)
                      _VisibilityOptionTile(
                        icon: _icon(value),
                        title: _label(s, value),
                        subtitle: _desc(s, value),
                        selected: value == current,
                        onTap: () => Navigator.pop(ctx, value),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;

    // Daftar putih ('Hanya orang tertentu'): pilih orangnya DULU, baru simpan
    // nilai — server menolak 'only' bila daftar masih kosong.
    if (selected.usesExclusions && !selected.isExcept) {
      final picked = await _editExclusions(field, mode: selected);
      if (picked == null || picked.isEmpty || !mounted) return;
      await _applyField(field, selected);
      return;
    }

    await _applyField(field, selected);
    if (!mounted) return;
    // Opsi "kecuali..." → pilih siapa yang dikecualikan.
    if (selected.usesExclusions) {
      await _editExclusions(field, mode: selected);
    }
  }

  Future<Set<String>?> _editExclusions(
    String field, {
    required PrivacyVisibility mode,
  }) async {
    final s = context.read<LocaleProvider>().s;
    final provider = ref.read(privacyProvider.notifier);
    await provider.ensureExcludable();
    if (!mounted) return null;

    final all = ref.read(privacyProvider).excludable;
    // 'Teman kecuali' hanya menampilkan teman; 'Semua kecuali' & 'Hanya orang
    // tertentu' menampilkan semua kandidat (teman + anon yang pernah chat).
    final list = mode.friendsOnly
        ? all.where((e) => e['is_friend'] == true).toList()
        : all;
    final isWhitelist = !mode.isExcept;
    if (isWhitelist && list.isEmpty) {
      // Tak ada kandidat → tak mungkin daftar putih; batalkan.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.privacyNoFriends)),
        );
      }
      return null;
    }

    final selected = Set<String>.of(
      ref.read(privacyProvider).settings.exclusions[field] ?? const {},
    );

    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // Sheet punya controller pencarian SENDIRI (dibuang di dispose-nya,
      // waktu yang benar dari framework). Dulu controller dibuat di sini &
      // di-dispose tepat setelah await → "used after being disposed" +
      // assertion `_dependents.isEmpty` (2026-09-29).
      builder: (_) => PrivacyExclusionsSheet(
        candidates: list,
        initialSelected: selected,
        isWhitelist: isWhitelist,
        title: isWhitelist ? s.privacyOnlyPickerTitle : s.privacyExceptTitle,
        desc: isWhitelist ? s.privacyOnlyPickerDesc : s.privacyExceptDesc,
        s: s,
      ),
    );
    if (result != null && mounted) {
      await provider.updateExclusions(field, result);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final p = ref.watch(privacyProvider).settings;
    // PERF (§26b): dulu 3× `watch<PointsProvider>()` → SELURUH halaman
    // privasi rebuild tiap PointsProvider notify (refresh beberapa kali saat
    // buka: get_points_enabled/get_wallet/yukcoin_v2_status) → lag saat masuk.
    // Sekarang `select` field yang dirender saja.
    final (:yukcoinV2Active, :ghostMode) = context.select<PointsProvider,
        ({bool yukcoinV2Active, bool ghostMode})>((pp) => (
      yukcoinV2Active: pp.yukcoinV2Active,
      ghostMode: pp.ghostMode,
    ));
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(title: Text(s.privacyTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          Text(
            s.privacyHint,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          _PrivacyCard(
            children: [
              _PrivacyTile(
                icon: Icons.circle_outlined,
                title: s.privacyPresence,
                value: _valueLabel(s, 'presence', p),
                onTap: () => _choose('presence', p),
              ),
              _PrivacyTile(
                icon: Icons.access_time,
                title: s.privacyLastSeen,
                value: _valueLabel(s, 'last_seen', p),
                onTap: () => _choose('last_seen', p),
              ),
              _PrivacyTile(
                icon: Icons.account_circle_outlined,
                title: s.privacyProfilePhoto,
                value: _valueLabel(s, 'profile_photo', p),
                onTap: () => _choose('profile_photo', p),
              ),
              _PrivacyTile(
                icon: Icons.info_outline,
                title: s.privacyAbout,
                value: _valueLabel(s, 'about', p),
                onTap: () => _choose('about', p),
              ),
              _PrivacyTile(
                icon: Icons.auto_stories_outlined,
                title: s.privacyStory,
                value: _valueLabel(s, 'story', p),
                onTap: () => _choose('story', p),
              ),
              _PrivacyTile(
                icon: Icons.emoji_events_outlined,
                title: s.privacyLeaderboard,
                value: _valueLabel(s, 'leaderboard', p),
                onTap: () => _choose('leaderboard', p),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PrivacyCard(
            children: [
              _PrivacySwitchTile(
                icon: Icons.done_all,
                title: s.privacyReadReceiptsTitle,
                subtitle: s.privacyReadReceiptsDesc,
                value: p.readReceipts,
                onChanged: (v) =>
                    ref.read(privacyProvider.notifier).update(readReceipts: v),
              ),
            ],
          ),
          // Ghost mode (YukCoin v2) — beli sehari untuk sembunyikan presence.
          if (yukcoinV2Active) ...[
            const SizedBox(height: 12),
            _PrivacyCard(
              children: [
                _PrivacySwitchTile(
                  icon: Icons.visibility_off_outlined,
                  title: s.yukcoinFeatureGhost,
                  subtitle: ghostMode
                      ? s.ghostModeActive
                      : '${s.ghostModeDesc} (${context.read<PointsProvider>().costGhostModeDaily})',
                  value: ghostMode,
                  onChanged: (v) => _buyGhost(v),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Beli ghost mode 1 hari (YukCoin). Bila sudah aktif, tombol = perpanjang.
  Future<void> _buyGhost(bool want) async {
    if (!want) return; // tidak bisa mematikan lebih awal (habis sendiri)
    final pp = context.read<PointsProvider>();
    final s = context.read<LocaleProvider>().s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.ghostModeBuy),
        content: Text(s.yukcoinUseConfirmBody(pp.costGhostModeDaily)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.yukcoinCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.yukcoinConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await pp.buyGhostMode(days: 1);
      await pp.refreshYukcoinV2();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.ghostModeActive)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.yukcoinNotEnough)));
    }
  }
}

/// Kartu yang sama dengan halaman Notifikasi (bgCard + radius 14).
class _PrivacyCard extends StatelessWidget {
  final List<Widget> children;
  const _PrivacyCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(height: 1, indent: 52, color: AppTheme.divider),
          ],
        ],
      ),
    );
  }
}

class _PrivacyTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _PrivacyTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _PrivacyIcon(icon: icon),
      title: Text(title, style: AppText.bodyStrong),
      subtitle: Text(
        value,
        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
      ),
      trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
      onTap: onTap,
    );
  }
}

class _PrivacySwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrivacySwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _PrivacyIcon(icon: icon),
      title: Text(title, style: AppText.bodyStrong),
      subtitle: Text(
        subtitle,
        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppTheme.primary,
      ),
      onTap: () => onChanged(!value),
    );
  }
}

/// Baris opsi di sheet pemilih visibilitas — ikon lingkaran berwarna,
/// judul + deskripsi singkat, dan centang pada opsi terpilih.
class _VisibilityOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _VisibilityOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = selected ? AppTheme.primary : AppTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? AppTheme.primary.withValues(alpha: 0.10)
            : AppTheme.bgScreen.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: selected ? 0.16 : 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppText.bodyStrong.copyWith(
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ikon lingkaran 36 — identik dengan tile Notifikasi.
class _PrivacyIcon extends StatelessWidget {
  final IconData icon;
  const _PrivacyIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: AppTheme.primary, size: 18),
    );
  }
}
