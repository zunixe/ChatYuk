import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../models/mission.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/missions_provider.dart';
import '../providers/riverpod/points_provider.dart';
import 'missions/widgets/bonus_widgets.dart';

/// Layar Bonus (ala Vava) — sign-in rewards 7 hari (male) + Tugas Pemula
/// (misi utama) + Bonus Harian (misi harian). Reward = YukCoin via
/// `claim_mission_reward` / `daily_login_bonus` (server-side, atomic).
class MissionsScreen extends ConsumerStatefulWidget {
  const MissionsScreen({super.key});

  @override
  ConsumerState<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends ConsumerState<MissionsScreen> {
  Timer? _tick;
  Duration _untilReset = Duration.zero;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _updateCountdown();
    // Countdown reset harian (tengah malam WIB) — 1 detik per tick, HANYA
    // selama layar terbuka (dispose membatalkan — anti pending-timer test).
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateCountdown();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tick = null;
    super.dispose();
  }

  /// Tanggal hari ini menurut waktu LOKAL HP — server memakai offset yang
  /// sama (`_local_day`), jadi pengguna di negara mana pun melihat hari yang
  /// konsisten dengan yang bisa diklaim.
  String get _todayLocal {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  void _updateCountdown() {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final d = nextMidnight.difference(now);
    if (mounted) {
      setState(() => _untilReset = d.isNegative ? Duration.zero : d);
    }
  }

  String get _countdownLabel {
    final h = _untilReset.inHours;
    final m = _untilReset.inMinutes.remainder(60);
    final sec = _untilReset.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _claimSignIn() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    final s = ref.read(localeProvider).s;
    final r = await ref.read(pointsProvider.notifier).claimDailyLogin();
    if (!mounted) return;
    setState(() => _claiming = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r.bonus > 0 ? s.bonusStreakToast(r.bonus) : s.bonusStreakToastZero,
        ),
      ),
    );
  }

  Future<void> _claimMission(String key, int coins) async {
    final s = ref.read(localeProvider).s;
    final notifier = ref.read(missionsProvider.notifier);
    final ok = await notifier.claimReward(key);
    if (!mounted || !ok) return;
    // Bucket ditentukan server: female → `earned` bila device & IP tidak
    // dipakai akun lain, selain itu `bonus`. Saldo total tetap naik.
    unawaited(ref.read(pointsProvider.notifier).refreshWallet());
    final isFemale =
        ref.read(authProvider.notifier).profile?.gender == 'female';
    final String text;
    if (notifier.lastClaimBucket == 'earned') {
      text = s.bonusRewardCoinsWithdrawable(coins);
    } else if (isFemale &&
        (notifier.lastClaimReason == 'shared_device' ||
            notifier.lastClaimReason == 'shared_ip')) {
      text = s.bonusRewardCoinsSharedDevice(coins);
    } else {
      text = s.bonusRewardCoinsNonWithdrawable(coins);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final st = ref.watch(missionsProvider);
    final notifier = ref.read(missionsProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(s.bonusTitle),
        backgroundColor: AppTheme.bgScreen,
        actions: [
          IconButton(
            tooltip: s.btnRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => notifier.refresh(),
          ),
        ],
      ),
      body: st.loading
          ? const Center(child: CircularProgressIndicator())
          : st.error != null
          ? _ErrorView(
              s: s,
              message: st.error!,
              onRetry: () => notifier.refresh(),
            )
          : RefreshIndicator(
              onRefresh: () => notifier.refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 28),
                children: [
                  if (st.showSignIn) ...[
                    _SectionHeader(
                      icon: Icons.event_available_rounded,
                      color: AppTheme.primary,
                      title: s.bonusSignInRewards,
                    ),
                    _SignInGrid(s: s, st: st),
                    _SignInButton(
                      s: s,
                      claimedToday:
                          st.lastLoginDate != null &&
                          st.lastLoginDate == _todayLocal,
                      countdown: _countdownLabel,
                      claiming: _claiming,
                      onTap: _claimSignIn,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _SectionHeader(
                    icon: Icons.emoji_events_outlined,
                    color: Colors.amber,
                    title: s.bonusBeginnerTasks,
                    // Female: misi nyonya jadi counter koin di samping judul
                    // (bukan baris) + counter "x/y selesai" — dua-duanya
                    // rata kanan. Male: hanya "x/y selesai".
                    trailing: st.nyonyaMission != null
                        ? null
                        : s.missionsCompletedCount(
                            st.mainMissions.where((m) => m.isCompleted).length,
                            st.mainMissions.length,
                          ),
                    // Female: "x/y selesai" di samping judul supaya tidak
                    // berebut tempat dengan counter nyonya (dulu overflow).
                    subtitle: st.nyonyaMission != null
                        ? s.missionsCompletedCount(
                            st.mainMissions.where((m) => m.isCompleted).length,
                            st.mainMissions.length,
                          )
                        : null,
                    trailingWidget: st.nyonyaMission != null
                        ? _NyonyaCounter(
                            s: s,
                            mission: st.nyonyaMission!,
                            onClaim: st.nyonyaMission!.canClaim
                                ? () => _claimMission(
                                    st.nyonyaMission!.missionKey,
                                    st.nyonyaMission!.rewardCoins,
                                  )
                                : null,
                          )
                        : null,
                  ),
                  ...st.mainMissions
                      .where((m) => m.missionKey != 'nyonya_1000')
                      .map(
                        (m) => BonusTaskRow(
                          title: m.title,
                          progressLabel: m.targetValue > 1
                              ? s.bonusTaskProgress(m.progress, m.targetValue)
                              : '',
                          rewardCoins: m.rewardCoins,
                          claimed: m.claimed,
                          claimLabel: s.bonusClaim,
                          onClaim: m.canClaim
                              ? () => _claimMission(m.missionKey, m.rewardCoins)
                              : null,
                        ),
                      ),
                  const SizedBox(height: 8),
                  _SectionHeader(
                    icon: Icons.today_outlined,
                    color: Colors.blue,
                    title: s.bonusDailyBonus,
                    trailing: st.totalCoins >= 1200
                        ? s.missionsCompletedCount(
                            st.dailyMissions.where((m) => m.isCompleted).length,
                            st.dailyMissions.length,
                          )
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      s.bonusDailyNote,
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  if (st.totalCoins < 1200) ...[
                    _UnlockBanner(s: s, coins: st.totalCoins),
                    const SizedBox(height: 6),
                  ],
                  ...st.dailyMissions.map(
                    (m) => BonusTaskRow(
                      title: m.title,
                      progressLabel: m.targetValue > 1
                          ? s.bonusTaskProgress(m.progress, m.targetValue)
                          : '',
                      rewardCoins: m.rewardCoins,
                      claimed: m.claimed,
                      locked: m.isLocked,
                      claimLabel: s.bonusClaim,
                      onClaim: m.canClaim
                          ? () => _claimMission(m.missionKey, m.rewardCoins)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Grid sign-in 7 hari: baris 1 = Hari 1–4, baris 2 = Hari 5–7 (Hari 7
/// lebih lebar, reward terbesar). State kartu dari streak + tanggal klaim.
class _SignInGrid extends StatelessWidget {
  final S s;
  final MissionsState st;
  const _SignInGrid({required this.s, required this.st});

  ({int claimedDays, int todayCard}) get _grid {
    final today = _todayOfContext;
    final yesterday = _dateStr(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final claimedToday = st.lastLoginDate != null && st.lastLoginDate == today;
    // Sehari terlewat → streak putus; server baru mereset saat klaim
    // berikutnya, jadi grid harus menampilkan Hari 1 (bukan hari lanjutan).
    final broken =
        st.lastLoginDate == null ||
        (st.lastLoginDate!.compareTo(yesterday) < 0);
    final streak = broken ? 0 : st.loginStreak.clamp(0, 7);
    if (claimedToday) {
      return (claimedDays: streak, todayCard: 0);
    }
    // Belum klaim hari ini: streak >= 7 → siklus reset (hari 1 aktif lagi).
    if (streak >= 7) return (claimedDays: 0, todayCard: 1);
    return (claimedDays: streak, todayCard: streak + 1);
  }

  static String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Tanggal LOKAL HP — server memakai offset zona waktu yang sama.
  String get _todayOfContext => _dateStr(DateTime.now());

  int _cardState(int day) {
    final g = _grid;
    if (day <= g.claimedDays) return 2;
    if (day == g.todayCard) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    Widget card(int day, {int flex = 1}) => Expanded(
      flex: flex,
      child: BonusDayCard(
        day: day,
        coins: kStreakRewards[day - 1],
        state: _cardState(day),
        dayLabel: s.bonusDay(day),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              card(1),
              const SizedBox(width: 8),
              card(2),
              const SizedBox(width: 8),
              card(3),
              const SizedBox(width: 8),
              card(4),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              card(5),
              const SizedBox(width: 8),
              card(6),
              const SizedBox(width: 8),
              // Hari 7 = reward terbesar → kartu lebih lebar (ala Vava).
              card(7, flex: 2),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tombol "Sign in" besar ala Vava — countdown reset harian di dalamnya.
/// Sudah klaim → disabled dengan label "Sudah klaim hari ini".
class _SignInButton extends StatelessWidget {
  final S s;
  final bool claimedToday;
  final String countdown;
  final bool claiming;
  final VoidCallback onTap;
  const _SignInButton({
    required this.s,
    required this.claimedToday,
    required this.countdown,
    required this.claiming,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = claimedToday || claiming;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: disabled ? null : onTap,
          style: FilledButton.styleFrom(
            backgroundColor: disabled ? AppTheme.bgInput : AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                claimedToday ? s.bonusSignInDone : s.bonusSignIn,
                style: AppText.button.copyWith(
                  color: disabled ? AppTheme.textSecondary : Colors.white,
                ),
              ),
              if (!claimedToday) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  countdown,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Header seksi (ikon + judul + trailing opsional).
/// [trailingWidget] menang atas [trailing] bila keduanya diisi.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? trailing;
  final String? subtitle;
  final Widget? trailingWidget;
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.title,
    this.trailing,
    this.subtitle,
    this.trailingWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: AppText.label.copyWith(color: AppTheme.textPrimary),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Text(
              subtitle!,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
          const Spacer(),
          if (trailingWidget != null)
            trailingWidget!
          else if (trailing != null)
            Flexible(
              child: Text(
                trailing!,
                textAlign: TextAlign.right,
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Counter misi nyonya di samping judul "Tugas Pemula" (female).
/// Menampilkan progres `cur/target` + ikon koin; saat target tercapai
/// berubah jadi tombol klaim +reward; sudah diklaim → centang abu.
class _NyonyaCounter extends StatelessWidget {
  final S s;
  final Mission mission;
  final VoidCallback? onClaim;
  const _NyonyaCounter({required this.s, required this.mission, this.onClaim});

  @override
  Widget build(BuildContext context) {
    if (mission.canClaim && onClaim != null) {
      return FilledButton(
        onPressed: onClaim,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(
          '${s.bonusClaim} +${mission.rewardCoins}',
          style: AppText.caption.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            mission.claimed
                ? Icons.check_circle_rounded
                : Icons.monetization_on_rounded,
            size: 15,
            color: mission.claimed ? AppTheme.onlineDark : AppTheme.idle,
          ),
          const SizedBox(width: 4),
          Text(
            s.bonusCounterProgress(mission.progress, mission.targetValue),
            style: AppText.caption.copyWith(
              color: mission.claimed
                  ? AppTheme.textSecondary
                  : AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner progres membuka misi harian (butuh 1200 koin).
class _UnlockBanner extends StatelessWidget {
  final S s;
  final int coins;
  const _UnlockBanner({required this.s, required this.coins});

  @override
  Widget build(BuildContext context) {
    final pct = (coins / 1200).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 15, color: Colors.blue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.missionsUnlockTitle,
                  style: AppText.caption.copyWith(
                    color: Colors.blue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                s.missionsUnlockProgress(coins),
                style: AppText.caption.copyWith(
                  color: Colors.blue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.blue.withValues(alpha: 0.15),
              color: Colors.blue,
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final S s;
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({
    required this.s,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.orange, size: 36),
            const SizedBox(height: 10),
            Text(
              message,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(s.btnRetry)),
          ],
        ),
      ),
    );
  }
}
