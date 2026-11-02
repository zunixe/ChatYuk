import 'package:flutter/material.dart';

import '../../config/strings.dart';
import '../../config/theme.dart';

/// Card satu misi — progress, reward, status (aktif / selesai / terkunci).
///
/// Aturan tampilan:
/// - Terkunci: kartu redup dengan latar `bgInput`, ikon gembok, tanpa progress
///   bar, chip reward redup + label "Terkunci".
/// - Aktif: progress bar + `progress / target`.
/// - Selesai: border & progress hijau, tombol klaim.
class MissionCard extends StatelessWidget {
  final String missionKey;
  final String title;
  final String description;
  final int progress;
  final int target;
  final int rewardCoins;
  final bool isCompleted;
  final bool claimed;
  final bool isLocked;
  final VoidCallback? onTap;
  final VoidCallback? onClaim;

  const MissionCard({
    super.key,
    required this.missionKey,
    required this.title,
    this.description = '',
    required this.progress,
    required this.target,
    required this.rewardCoins,
    this.isCompleted = false,
    this.claimed = false,
    this.isLocked = false,
    this.onTap,
    this.onClaim,
  });

  static const _done = Color(0xFF2ECC71);

  double get _fraction => target > 0 ? (progress / target).clamp(0.0, 1.0) : 0.0;

  @override
  Widget build(BuildContext context) {
    final s = S(isId: Localizations.localeOf(context).languageCode == 'id');
    final locked = isLocked;
    final done = isCompleted && !locked;

    final accent = done ? _done : (locked ? AppTheme.textSecondary : AppTheme.primary);
    final titleColor = locked
        ? AppTheme.textSecondary
        : done
        ? _done
        : AppTheme.textPrimary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: locked ? AppTheme.bgInput : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done ? _done.withValues(alpha: 0.45) : AppTheme.divider,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: locked ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusIcon(locked: locked, done: done, accent: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TitleRow(
                        title: title,
                        titleColor: titleColor,
                        rewardCoins: rewardCoins,
                        locked: locked,
                        done: done,
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (locked) ...[
                        const SizedBox(height: 7),
                        _LockedBadge(label: s.missionLocked('')),
                      ] else ...[
                        const SizedBox(height: 9),
                        _ProgressRow(
                          progress: progress,
                          target: target,
                          fraction: _fraction,
                          accent: accent,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!locked && isCompleted && !claimed && onClaim != null) ...[
                  const SizedBox(width: 4),
                  _ClaimButton(onClaim: onClaim!, label: s.missionClaim(0).split(' ').first),
                ] else if (claimed) ...[
                  const SizedBox(width: 6),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.check_circle, color: _done, size: 20),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final bool locked;
  final bool done;
  final Color accent;

  const _StatusIcon({
    required this.locked,
    required this.done,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(
        locked
            ? Icons.lock_outline
            : done
            ? Icons.check
            : Icons.emoji_events_outlined,
        size: 18,
        color: accent,
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  final String title;
  final Color titleColor;
  final int rewardCoins;
  final bool locked;
  final bool done;

  const _TitleRow({
    required this.title,
    required this.titleColor,
    required this.rewardCoins,
    required this.locked,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final chipBg = locked
        ? AppTheme.bgCard
        : (done ? MissionCard._done : Colors.amber).withValues(alpha: 0.14);
    final chipFg = locked
        ? AppTheme.textSecondary
        : (done ? MissionCard._done : Colors.amber);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            style: AppText.bodyStrong.copyWith(color: titleColor),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: chipFg.withValues(alpha: 0.35)),
          ),
          child: Text(
            '+$rewardCoins',
            style: AppText.label.copyWith(
              color: chipFg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final int progress;
  final int target;
  final double fraction;
  final Color accent;

  const _ProgressRow({
    required this.progress,
    required this.target,
    required this.fraction,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor: AppTheme.divider,
              color: accent,
              minHeight: 5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$progress/$target',
          style: AppText.micro.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _LockedBadge extends StatelessWidget {
  final String label;

  const _LockedBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.lock_outline, size: 12, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _ClaimButton extends StatelessWidget {
  final VoidCallback onClaim;
  final String label;

  const _ClaimButton({required this.onClaim, required this.label});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onClaim,
      style: FilledButton.styleFrom(
        backgroundColor: MissionCard._done,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
