import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/strings.dart';
import '../config/theme.dart';
import 'missions/widgets/mission_card.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../providers/theme_provider.dart';

class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen>
    with SingleTickerProviderStateMixin {
  PointsProvider get _service => context.read<PointsProvider>();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
      }
    } finally {
      if (mounted) setState(() => _claiming = null);
    }
  }

  int _doneCount(List<dynamic> items) =>
      items.where((e) => (e as Map)['done'] == true).length;

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final current = _tab.index == 0
        ? _daily
        : _tab.index == 1
        ? _weekly
        : _oneTime;
    final claimableCount = _weekly
        .where((e) => (e as Map)['claimable'] == true)
        .length;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 190,
            pinned: true,
            backgroundColor: AppTheme.primary,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              s.missionsTitle,
              style: const TextStyle(color: Colors.white),
            ),
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
                  unselectedLabelStyle: AppText.body.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
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
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              )
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
              decoration: BoxDecoration(
                color: AppTheme.danger,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badge',
                style: AppText.micro.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _list(List<dynamic> items, S s) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          s.missionsEmpty,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          12,
          4,
          12,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => MissionCard(
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
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.stars_rounded,
                  color: Colors.amber,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    s.missionsMyPoints,
                    style: AppText.bodySmall.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$points',
                    style: AppText.display.copyWith(
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (streak > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: AppGlyph.sm)),
                      const SizedBox(height: 2),
                      Text(
                        '$streak',
                        style: AppText.bodyStrong.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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
  const _ProgressBanner({
    required this.done,
    required this.total,
    required this.hint,
    required this.s,
  });

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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 5,
                    backgroundColor: AppTheme.divider,
                    valueColor: AlwaysStoppedAnimation(
                      allDone ? AppTheme.online : AppTheme.primary,
                    ),
                  ),
                ),
                Text(
                  '${(pct * 100).round()}%',
                  style: AppText.micro.copyWith(fontWeight: FontWeight.w800),
                ),
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
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  hint,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


