import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../models/privacy_settings.dart';
import '../../../providers/riverpod/privacy_provider.dart';
import '../../../widgets/person_avatar.dart';
import '../../../widgets/sheet_drag_handle.dart';
import '../../privacy_settings_screen.dart';

/// Pemetaan visibilitas privacy → (label chip, subbaris opsional).
///
/// Publik + murni supaya bisa diuji tanpa widget. Subbaris WAJIB ada saat
/// ada daftar pengecualian ("kecuali N orang") supaya "Semua orang" tidak
/// menyesatkan (kasus: status online tapi sebagian orang melihat Offline).
(String, String?) myStatusVisibilityChip(
  S s,
  PrivacyVisibility v,
  int exclusionCount,
) {
  switch (v) {
    case PrivacyVisibility.everyone:
      return (s.myStatusVisibleEveryone, null);
    case PrivacyVisibility.everyoneExcept:
      return (
        s.myStatusVisibleEveryone,
        exclusionCount > 0 ? s.myStatusExceptNAndOffline(exclusionCount) : null,
      );
    case PrivacyVisibility.friends:
      return (s.myStatusVisibleFriends, null);
    case PrivacyVisibility.friendsExcept:
      return (
        s.myStatusVisibleFriends,
        exclusionCount > 0 ? s.myStatusExceptN(exclusionCount) : null,
      );
    case PrivacyVisibility.only:
      return (s.myStatusVisibleOnly(exclusionCount), null);
    case PrivacyVisibility.nobody:
      return (s.myStatusVisibleNobody, s.myStatusTheySeeOffline);
  }
}

/// Sheet informasi status + visibilitas DIRI SENDIRI (display-only).
///
/// UI: chip ringkas + subbaris (agar "kecuali N orang" tidak menyesatkan).
/// Status & visibilitas adalah 2 dimensi terpisah — lihat catatan di
/// `_showMyStatusSheet`.
class MyStatusSheet extends ConsumerWidget {
  final S s;
  final String uid;
  final String nickname;
  final String avatar;
  final String gender;
  final String status;
  final bool invisible;

  /// Tap avatar di header → zoom foto. null = avatar tidak bisa diketuk.
  final VoidCallback? onAvatarTap;
  const MyStatusSheet({
    super.key,
    required this.s,
    required this.uid,
    required this.nickname,
    required this.avatar,
    required this.gender,
    required this.status,
    required this.invisible,
    this.onAvatarTap,
  });

  String _statusLabel() {
    switch (status) {
      case 'idle':
        return s.statusIdle;
      case 'online':
        return s.statusOnline;
      default:
        return s.statusOffline;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacy = ref.watch(privacyProvider).settings;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetDragHandle(),
            const SizedBox(height: 6),
            // Header: avatar + nama. Pakai UserAvatar MODULAR (menangani
            // base64 ATAU path storage + cap + anti-kedip) supaya foto
            // benar-benar tampil; warna+ring ikut GENDER sama seperti kartu
            // user lain (male=biru / female=pink / lain=accent).
            Row(
              children: [
                // PersonAvatar — SAMA seperti kartu Online & header chat
                // (tint + ring WARNA GENDER, foto bila ada, inisial bila tidak).
                // Tap → zoom besar (dialog foto).
                GestureDetector(
                  onTap: onAvatarTap,
                  child: PersonAvatar(
                    uid: uid,
                    name: nickname,
                    gender: gender,
                    avatarB64: avatar,
                    size: 44,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.myStatusTitle,
                    style: AppText.title,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Baris 1: STATUS asli (fakta). Ghost → badge 👻 terpisah.
            _row(
              icon: Icons.circle,
              iconColor: AppTheme.statusColor(status),
              label: s.myStatusStatusLabel,
              child: Row(
                children: [
                  Text(_statusLabel(), style: AppText.bodyStrong),
                  if (invisible) ...[
                    const SizedBox(width: 6),
                    const Text('👻',
                        style: TextStyle(fontSize: AppGlyph.micro)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        s.myStatusGhostActive,
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Baris 2: TERLIHAT OLEH (efek privasi) — chip + subbaris.
            Builder(
              builder: (_) {
                final st = privacy;
                final vis = st.presence;
                final n = (st.exclusions['presence'] ?? const <String>{}).length;
                final (chip, sub) = myStatusVisibilityChip(s, vis, n);
                return _row(
                  icon: Icons.visibility_outlined,
                  iconColor: AppTheme.primary,
                  label: s.myStatusVisibleTo,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _chip(chip),
                      if (sub != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          sub,
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            // Baris 3: FOTO PROFIL (dimensi privasi terpisah).
            Builder(
              builder: (_) {
                final vis = privacy.profilePhoto;
                final n = (privacy.exclusions['profile_photo'] ??
                        const <String>{})
                    .length;
                final (chip, _) = myStatusVisibilityChip(s, vis, n);
                return _row(
                  icon: Icons.person_outline,
                  iconColor: AppTheme.textSecondary,
                  label: s.myStatusPhotoLabel,
                  child: _chip(chip),
                );
              },
            ),
            const SizedBox(height: 16),
            // Footer navigasi (bukan aksi ubah): buka Pengaturan Privasi.
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PrivacySettingsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.tune, size: 16),
                label: Text(s.myStatusManageInPrivacy),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required Color iconColor,
    required String label,
    required Widget child,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 2),
              child,
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: AppText.bodySmall.copyWith(
          color: AppTheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
