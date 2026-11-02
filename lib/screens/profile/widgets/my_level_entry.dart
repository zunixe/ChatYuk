import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../providers/riverpod/my_level_provider.dart';
import '../../my_level_screen.dart';

/// Baris menu My Level di halaman Profil — MALE only (di-gate pemanggil).
/// Subtitle menampilkan level terkini dari `myLevelProvider`
/// (RPC `get_my_level`; reward naik-level dicetak server, idempoten).
class MyLevelEntryCard extends ConsumerWidget {
  const MyLevelEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final lv = ref.watch(myLevelProvider);
    return Material(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyLevelScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  size: 17,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.myLevelTitle,
                      style: AppText.bodyStrong.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      lv.loading ? '…' : s.levelShort(lv.level),
                      style: AppText.micro.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
