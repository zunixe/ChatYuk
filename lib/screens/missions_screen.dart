import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../services/points_service.dart';

class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen>
    with SingleTickerProviderStateMixin {
  final PointsService _service = PointsService();
  late final TabController _tab = TabController(length: 3, vsync: this);
  int get _tzOffset => DateTime.now().timeZoneOffset.inMinutes;

  bool _loading = true;
  List<dynamic> _daily = [];
  List<dynamic> _weekly = [];
  List<dynamic> _oneTime = [];
  int _points = 0;
  int _streak = 0;
  String? _claiming;

  @override
  void initState() {
    super.initState();
    _tab.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _service.quests(_tzOffset);
      if (!mounted) return;
      setState(() {
        _daily = (res['daily'] as List?) ?? [];
        _weekly = (res['weekly'] as List?) ?? [];
        _oneTime = (res['oneTime'] as List?) ?? [];
        _points = (res['points'] as num?)?.toInt() ?? 0;
        _streak = (res['streak'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _claim(String key, int reward) async {
    if (_claiming != null) return;
    setState(() => _claiming = key);
    final s = context.read<LocaleProvider>().s;
    try {
      final res = await _service.claimWeeklyQuest(key, _tzOffset);
      if (!mounted) return;
      if (res['claimed'] == true) {
        final pp = context.read<PointsProvider>();
        pp.setPoints((res['points'] as num?)?.toInt() ?? pp.points);
        pp.showPointsToast(context, s.missionClaimedToast(reward));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errGeneric}$e')));
      }
    } finally {
      if (mounted) setState(() => _claiming = null);
    }
  }

  int _doneCount(List<dynamic> items) =>
      items.where((e) => (e as Map)['done'] == true).length;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final current = _tab.index == 0 ? _daily : _tab.index == 1 ? _weekly : _oneTime;
    final claimableCount = _weekly.where((e) => (e as Map)['claimable'] == true).length;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 190,
            pinned: true,
            backgroundColor: AppTheme.primary,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(s.missionsTitle, style: const TextStyle(color: Colors.white)),
            flexibleSpace: FlexibleSpaceBar(
              background: _Header(points: _points, streak: _streak, s: s),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: AppTheme.primary,
                child: TabBar(
                  controller: _tab,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  labelStyle: AppText.bodyStrong,
                  unselectedLabelStyle: AppText.body.copyWith(fontWeight: FontWeight.w500),
                  tabs: [
                    _tabWithBadge(s.missionsDaily, 0),
                    _tabWithBadge(s.missionsWeekly, claimableCount),
                    _tabWithBadge(s.missionsOnce, 0),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : Column(
                children: [
                  _ProgressBanner(
                    done: _doneCount(current),
                    total: current.length,
                    hint: _tab.index == 0
                        ? s.missionsDailyHint
                        : _tab.index == 1
                            ? s.missionsWeeklyHint
                            : s.missionsOnceHint,
                    s: s,
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tab,
                      children: [
                        _list(_daily, s),
                        _list(_weekly, s),
                        _list(_oneTime, s),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _tabWithBadge(String text, int badge) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (badge > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(10)),
              child: Text('$badge', style: AppText.micro.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _list(List<dynamic> items, S s) {
    if (items.isEmpty) {
      return Center(child: Text(s.missionsEmpty, style: TextStyle(color: AppTheme.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: items.length,
        itemBuilder: (_, i) => _MissionCard(
          data: Map<String, dynamic>.from(items[i] as Map),
          claimingKey: _claiming,
          onClaim: _claim,
          index: i,
        ),
      ),
    );
  }
}

// ── Header dengan gradient + saldo poin + streak ──
class _Header extends StatelessWidget {
  final int points;
  final int streak;
  final S s;
  const _Header({required this.points, required this.streak, required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, AppTheme.primaryDark, Color(0xFF6A1B9A)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.stars_rounded, color: Colors.amber, size: 32),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(s.missionsMyPoints,
                      style: AppText.bodySmall.copyWith(color: Colors.white70, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text('$points',
                      style: AppText.display.copyWith(color: Colors.white, height: 1)),
                ],
              ),
              const Spacer(),
              if (streak > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: AppGlyph.sm)),
                      const SizedBox(height: 2),
                      Text('$streak',
                          style: AppText.bodyStrong.copyWith(color: Colors.white, fontWeight: FontWeight.w800, height: 1)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Banner progress tab aktif ──
class _ProgressBanner extends StatelessWidget {
  final int done;
  final int total;
  final String hint;
  final S s;
  const _ProgressBanner({required this.done, required this.total, required this.hint, required this.s});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final allDone = total > 0 && done == total;
    return Container(
      margin: EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44, height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 44, height: 44,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 5,
                    backgroundColor: AppTheme.divider,
                    valueColor: AlwaysStoppedAnimation(allDone ? AppTheme.online : AppTheme.primary),
                  ),
                ),
                Text('${(pct * 100).round()}%',
                    style: AppText.micro.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allDone ? s.missionsAllDone : s.missionsProgress(done, total),
                  style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2),
                Text(hint, style: AppText.caption.copyWith(color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Kartu misi ──
class _MissionCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String? claimingKey;
  final void Function(String key, int reward) onClaim;
  final int index;
  const _MissionCard({required this.data, required this.claimingKey, required this.onClaim, required this.index});

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
    'registered': (icon: Icons.mark_email_read_rounded, color: Color(0xFF43A047)),
    'rated_app': (icon: Icons.star_rounded, color: Color(0xFFFFB300)),
    'completed_profile': (icon: Icons.badge_rounded, color: Color(0xFFFB8C00)),
    'invited_friend': (icon: Icons.share_rounded, color: Color(0xFF00ACC1)),
    'first_photo': (icon: Icons.photo_camera_rounded, color: Color(0xFFD81B60)),
    'first_room_chat': (icon: Icons.chat_bubble_rounded, color: Color(0xFF3949AB)),
  };

  String _label(S s, String key) {
    switch (key) {
      case 'daily_login': return s.mDailyLogin;
      case 'room_read': return s.mRoomRead;
      case 'new_chat': return s.mNewChat;
      case 'online_5min': return s.mOnline5;
      case 'online_30min': return s.mOnline30;
      case 'online_60min': return s.mOnline60;
      case 'online_120min': return s.mOnline120;
      case 'w_login': return s.mwLogin;
      case 'w_social': return s.mwSocial;
      case 'w_active': return s.mwActive;
      case 'registered': return s.mRegistered;
      case 'rated_app': return s.mRatedApp;
      case 'completed_profile': return s.mCompletedProfile;
      case 'invited_friend': return s.mInvitedFriend;
      case 'first_photo': return s.mFirstPhoto;
      case 'first_room_chat': return s.mFirstRoomChat;
      default: return key;
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
    final meta = _meta[key] ?? (icon: Icons.emoji_events_rounded, color: AppTheme.primary);

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 260 + index * 45),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 16), child: child),
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
                width: 46, height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: done
                        ? [AppTheme.online.withValues(alpha: 0.85), AppTheme.online]
                        : [meta.color.withValues(alpha: 0.85), meta.color],
                  ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [BoxShadow(color: (done ? AppTheme.online : meta.color).withValues(alpha: 0.3), blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: Icon(done ? Icons.check_rounded : meta.icon, color: Colors.white, size: 24),
              ),
              SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(_label(s, key),
                              style: AppText.bodyStrong.copyWith(
                                fontWeight: FontWeight.w700,
                                decoration: done ? TextDecoration.none : null,
                              )),
                        ),
                        _RewardChip(reward: reward, done: done),
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
                                tween: Tween(begin: 0, end: target == 0 ? 0 : (current / target).clamp(0.0, 1.0)),
                                builder: (_, v, __) => LinearProgressIndicator(
                                  value: v,
                                  minHeight: 7,
                                  backgroundColor: AppTheme.divider,
                                  valueColor: AlwaysStoppedAnimation(done ? AppTheme.online : meta.color),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text('$current/$target',
                              style: AppText.caption.copyWith(color: AppTheme.textSecondary, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ] else if (claimable) ...[
                      const SizedBox(height: 4),
                      Text(s.missionsReadyClaim,
                          style: AppText.caption.copyWith(color: AppTheme.primary, fontWeight: FontWeight.w600)),
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

  Widget _trailing(S s, String key, int reward, bool done, bool claimable, bool isClaiming) {
    if (claimable) {
      return ElevatedButton(
        onPressed: isClaiming ? null : () => onClaim(key, reward),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: const Size(0, 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: isClaiming
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(s.missionClaim, style: AppText.label.copyWith(letterSpacing: 0, fontWeight: FontWeight.w800)),
      );
    }
    if (done) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: AppTheme.online.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: const Icon(Icons.done_all_rounded, color: AppTheme.online, size: 18),
      );
    }
    return const SizedBox.shrink();
  }
}

class _RewardChip extends StatelessWidget {
  final int reward;
  final bool done;
  const _RewardChip({required this.reward, required this.done});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: done
              ? [AppTheme.online.withValues(alpha: 0.15), AppTheme.online.withValues(alpha: 0.15)]
              : [const Color(0xFFFFF3E0), const Color(0xFFFFE0B2)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.monetization_on_rounded,
              size: 12, color: done ? AppTheme.online : const Color(0xFFF57C00)),
          const SizedBox(width: 3),
          Text('+$reward',
              style: AppText.caption.copyWith(
                color: done ? AppTheme.online : const Color(0xFFE65100),
                fontWeight: FontWeight.w800,
              )),
        ],
      ),
    );
  }
}
