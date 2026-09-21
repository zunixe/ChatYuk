import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../models/privacy_settings.dart';
import '../providers/locale_provider.dart';
import '../providers/privacy_provider.dart';

/// Pengaturan Privasi — struktur & gaya sama dengan halaman Notifikasi
/// (kartu bgCard, ikon lingkaran 36, divider indent 52).
///
/// 5 pilihan per bagian:
///   Semua orang / Semua orang kecuali... / Teman saya /
///   Teman saya kecuali... / Tidak ada
/// Opsi "kecuali..." bisa memilih TEMAN maupun ANON (yang pernah chat).
class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<PrivacyProvider>();
      p.load();
      // Daftar excludable dimuat awal juga supaya jumlah "(n)" akurat.
      p.ensureExcludable();
    });
  }

  String _label(S s, PrivacyVisibility value) {
    return switch (value) {
      PrivacyVisibility.everyone => s.privacyEveryone,
      PrivacyVisibility.everyoneExcept => s.privacyEveryoneExcept,
      PrivacyVisibility.friends => s.privacyFriends,
      PrivacyVisibility.friendsExcept => s.privacyFriendsExcept,
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
      _ => s.privacyTitle,
    };
  }

  /// Nilai tile: untuk opsi "kecuali..." sekaligus tampil jumlahnya.
  String _valueLabel(S s, String field, PrivacySettings p) {
    final value = _valueOf(field, p);
    final n = (p.exclusions[field] ?? const {}).length;
    if (value == PrivacyVisibility.everyoneExcept) {
      return s.privacyEveryoneExceptCount(n);
    }
    if (value == PrivacyVisibility.friendsExcept) {
      return s.privacyFriendsExceptCount(n);
    }
    return _label(s, value);
  }

  Future<void> _applyField(String field, PrivacyVisibility value) async {
    final provider = context.read<PrivacyProvider>();
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
            for (final value in PrivacyVisibility.values)
              ListTile(
                leading: Icon(
                  value == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: value == current
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                  size: 20,
                ),
                title: Text(
                  _label(s, value),
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: value == current
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, value),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;

    await _applyField(field, selected);
    if (!mounted) return;
    // Opsi "kecuali..." → langsung pilih siapa yang dikecualikan.
    if (selected.usesExclusions) {
      await _editExclusions(field, friendsOnly: selected.friendsOnly);
    }
  }

  Future<void> _editExclusions(
    String field, {
    required bool friendsOnly,
  }) async {
    final s = context.read<LocaleProvider>().s;
    final provider = context.read<PrivacyProvider>();
    await provider.ensureExcludable();
    if (!mounted) return;

    final all = provider.excludable;
    // 'Teman kecuali' hanya menampilkan teman; 'Semua kecuali' menampilkan
    // semua kandidat (teman + anon yang pernah chat).
    final list = friendsOnly
        ? all.where((e) => e['is_friend'] == true).toList()
        : all;

    final selected = Set<String>.of(
      provider.settings.exclusions[field] ?? const {},
    );
    if (!mounted) return;

    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.privacyExceptTitle, style: AppText.title),
                              const SizedBox(height: 2),
                              Text(
                                s.privacyExceptDesc,
                                style: AppText.bodySmall.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, selected),
                          child: Text(s.btnSave),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: AppTheme.divider),
                  Expanded(
                    child: list.isEmpty
                        ? _EmptyExcludable(s: s)
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final e = list[i];
                              final uid = '${e['uid'] ?? ''}';
                              final name = '${e['nickname'] ?? uid}';
                              final isFriend = e['is_friend'] == true;
                              final checked = selected.contains(uid);
                              return CheckboxListTile(
                                value: checked,
                                activeColor: AppTheme.primary,
                                secondary: _PersonAvatar(name: name),
                                title: Text(name, style: AppText.bodyStrong),
                                subtitle: Text(
                                  isFriend
                                      ? s.privacyBadgeFriend
                                      : s.privacyBadgeAnon,
                                  style: AppText.caption.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                onChanged: (v) => setSheetState(() {
                                  if (v == true) {
                                    selected.add(uid);
                                  } else {
                                    selected.remove(uid);
                                  }
                                }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (result != null && mounted) {
      await provider.updateExclusions(field, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final privacy = context.watch<PrivacyProvider>();
    final p = privacy.settings;
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
                    context.read<PrivacyProvider>().update(readReceipts: v),
              ),
            ],
          ),
        ],
      ),
    );
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

class _PersonAvatar extends StatelessWidget {
  final String name;
  const _PersonAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: AppText.label.copyWith(color: AppTheme.primary),
      ),
    );
  }
}

class _EmptyExcludable extends StatelessWidget {
  final S s;
  const _EmptyExcludable({required this.s});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_outlined,
              size: 40,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(s.privacyNoFriends, style: AppText.bodyStrong),
            const SizedBox(height: 4),
            Text(
              s.privacyNoFriendsHint,
              textAlign: TextAlign.center,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
