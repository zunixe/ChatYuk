import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../providers/riverpod/auth_provider.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../widgets/person_avatar.dart';

/// Baris "Apa yang baru?" di atas feed (ala Threads): avatar + nama sendiri
/// + placeholder. Tap → [onTap] (buka composer postingan baru).
class WhatsNewRow extends ConsumerWidget {
  final VoidCallback onTap;
  const WhatsNewRow({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final uid = ref.watch(authProvider.select((a) => a.uid)) ?? '';
    final name = ref.watch(
      authProvider.select((a) => a.profile?.nickname ?? ''),
    );
    final gender = ref.watch(
      authProvider.select((a) => a.profile?.gender ?? ''),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                PersonAvatar(
                  key: ValueKey('whatsnew_$uid'),
                  uid: uid,
                  name: name,
                  gender: gender,
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.whatsNewHint,
                        maxLines: 1,
                        style: AppText.body.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Sama persis dengan pemisah antar PostCard.
        const Divider(height: 1, thickness: 0.5),
      ],
    );
  }
}
