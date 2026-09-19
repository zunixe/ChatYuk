import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../providers/locale_provider.dart';

// ── Kartu misi ──
class MissionCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String? claimingKey;
  final void Function(String key, int reward) onClaim;
  final int index;
  const MissionCard({
    required this.data,
    required this.claimingKey,
    required this.onClaim,
    required this.index,
  });

  static const _meta = <String, ({IconData icon, Color color})>{
    'daily_login': (icon: Icons.wb_sunny_rounded, color: Color(0xFFFFA000)),
    'room_read': (icon: Icons.menu_book_rounded, color: Color(0xFF00897B)),
    'new_chat': (icon: Icons.person_add_rounded, color: Color(0xFF1E88E5)),
    'online_5min': (icon: Icons.timer_rounded, color: Color(0xFF43A047)),
    'online_30min': (icon: Icons.timer_rounded, color: Color(0xFF43A047)),
    'online_60min': (icon: Icons.timer_rounded, color: Color(0xFF43A047)),
    'online_120min': (icon: Icons.timer_rounded, color: Color(0xFF43A047)),
    'w_login': (icon: Icons.calendar_month_rounded, color: Color(0xFF8E24AA)),
    'w_social': (icon: Icons.groups_rounded, color: Color(0xFF1E88E5)),
    'w_active': (icon: Icons.forum_rounded, color: Color(0xFFE53935)),
    'registered': (
      icon: Icons.mark_email_read_rounded,
      color: Color(0xFF43A047),
    ),
    'rated_app': (icon: Icons.star_rounded, color: Color(0xFFFFB300)),
    'completed_profile': (icon: Icons.badge_rounded, color: Color(0xFFFB8C00)),
    'invited_friend': (icon: Icons.share_rounded, color: Color(0xFF00ACC1)),
    'first_photo': (icon: Icons.photo_camera_rounded, color: Color(0xFFD81B60)),
    'first_room_chat': (
      icon: Icons.chat_bubble_rounded,
      color: Color(0xFF3949AB),
    ),
  };

  String _label(S s, String key) {
    switch (key) {
      case 'daily_login':
        return s.mDailyLogin;
      case 'room_read':
        return s.mRoomRead;
      case 'new_chat':
        return s.mNewChat;
      case 'online_5min':
        return s.mOnline5;
      case 'online_30min':
        return s.mOnline30;
      case 'online_60min':
        return s.mOnline60;
      case 'online_120min':
        return s.mOnline120;
      case 'w_login':
        return s.mwLogin;
      case 'w_social':
        return s.mwSocial;
      case 'w_active':
        return s.mwActive;
      case 'registered':
        return s.mRegistered;
      case 'rated_app':
        return s.mRatedApp;
      case 'completed_profile':
        return s.mCompletedProfile;
      case 'invited_friend':
        return s.mInvitedFriend;
      case 'first_photo':
        return s.mFirstPhoto;
      case 'first_room_chat':
        return s.mFirstRoomChat;
      default:
        return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final key = data['key']?.toString() ?? '';
    final reward = (data['reward'] as num?)?.toInt() ?? 0;
    final done = data['done'] == true;
    final claimable = data['claimable'] == true;
    final target = (data['target'] as num?)?.toInt() ?? 1;
    final current = (data['current'] as num?)?.toInt() ?? 0;
    final hasProgress = target > 1;
    final isClaiming = claimingKey == key;
    final meta =
        _meta[key] ??
        (icon: Icons.emoji_events_rounded, color: AppTheme.primary);

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 260 + index * 45),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 16),
          child: child,
        ),
      ),
      child: Container(
        margin: EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: claimable
              ? Border.all(color: AppTheme.primary, width: 1.5)
              : Border.all(color: Colors.transparent),
          boxShadow: [
            BoxShadow(
              color: claimable
                  ? AppTheme.primary.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: claimable ? 12 : 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              // Ikon berwarna
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: done
                        ? [
                            AppTheme.online.withValues(alpha: 0.85),
                            AppTheme.online,
                          ]
                        : [meta.color.withValues(alpha: 0.85), meta.color],
                  ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: (done ? AppTheme.online : meta.color).withValues(
                        alpha: 0.3,
                      ),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  done ? Icons.check_rounded : meta.icon,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _label(s, key),
                            style: AppText.bodyStrong.copyWith(
                              fontWeight: FontWeight.w700,
                              decoration: done ? TextDecoration.none : null,
                            ),
                          ),
                        ),
                        RewardChip(reward: reward, done: done),
                      ],
                    ),
                    if (hasProgress) ...[
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: TweenAnimationBuilder<double>(
                                duration: Duration(milliseconds: 600),
                                curve: Curves.easeOut,
                                tween: Tween(
                                  begin: 0,
                                  end: target == 0
                                      ? 0
                                      : (current / target).clamp(0.0, 1.0),
                                ),
                                builder: (_, v, __) => LinearProgressIndicator(
                                  value: v,
                                  minHeight: 7,
                                  backgroundColor: AppTheme.divider,
                                  valueColor: AlwaysStoppedAnimation(
                                    done ? AppTheme.online : meta.color,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '$current/$target',
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ] else if (claimable) ...[
                      const SizedBox(height: 4),
                      Text(
                        s.missionsReadyClaim,
                        style: AppText.caption.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _trailing(s, key, reward, done, claimable, isClaiming),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trailing(
    S s,
    String key,
    int reward,
    bool done,
    bool claimable,
    bool isClaiming,
  ) {
    if (claimable) {
      return ElevatedButton(
        onPressed: isClaiming ? null : () => onClaim(key, reward),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: const Size(0, 36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: isClaiming
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                s.missionClaim,
                style: AppText.label.copyWith(
                  letterSpacing: 0,
                  fontWeight: FontWeight.w800,
                ),
              ),
      );
    }
    if (done) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppTheme.online.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.done_all_rounded,
          color: AppTheme.online,
          size: 18,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class RewardChip extends StatelessWidget {
  final int reward;
  final bool done;
  const RewardChip({required this.reward, required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: done
              ? [
                  AppTheme.online.withValues(alpha: 0.15),
                  AppTheme.online.withValues(alpha: 0.15),
                ]
              : [const Color(0xFFFFF3E0), const Color(0xFFFFE0B2)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monetization_on_rounded,
            size: 12,
            color: done ? AppTheme.online : const Color(0xFFF57C00),
          ),
          const SizedBox(width: 3),
          Text(
            '+$reward',
            style: AppText.caption.copyWith(
              color: done ? AppTheme.online : const Color(0xFFE65100),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
