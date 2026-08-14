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
  String? _claiming;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.missionsTitle),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: s.missionsDaily),
            Tab(text: s.missionsWeekly),
            Tab(text: s.missionsOnce),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : TabBarView(
              controller: _tab,
              children: [
                _list(s.missionsDailyHint, _daily, s),
                _list(s.missionsWeeklyHint, _weekly, s),
                _list(s.missionsOnceHint, _oneTime, s),
              ],
            ),
    );
  }

  Widget _list(String hint, List<dynamic> items, S s) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Expanded(child: Text(hint, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
            ]),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(s.missionsEmpty, style: const TextStyle(color: AppTheme.textSecondary))),
            )
          else
            ...items.map((e) => _MissionTile(
                  data: Map<String, dynamic>.from(e as Map),
                  claimingKey: _claiming,
                  onClaim: _claim,
                )),
        ],
      ),
    );
  }
}

class _MissionTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String? claimingKey;
  final void Function(String key, int reward) onClaim;
  const _MissionTile({required this.data, required this.claimingKey, required this.onClaim});

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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? AppTheme.online.withValues(alpha: 0.15)
                    : AppTheme.primary.withValues(alpha: 0.1),
              ),
              child: Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: done ? AppTheme.online : AppTheme.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_label(s, key),
                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('+$reward',
                          style: TextStyle(color: Colors.amber.shade800, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                    if (hasProgress) ...[
                      const SizedBox(width: 8),
                      Text('$current/$target',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    ],
                  ]),
                  if (hasProgress) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: target == 0 ? 0 : (current / target).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: AppTheme.divider,
                        valueColor: AlwaysStoppedAnimation(done ? AppTheme.online : AppTheme.primary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            _trailing(s, key, reward, done, claimable, isClaiming),
          ],
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          minimumSize: const Size(0, 32),
        ),
        child: isClaiming
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(s.missionClaim, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      );
    }
    if (done) {
      return Text(s.missionDone,
          style: const TextStyle(color: AppTheme.online, fontSize: 12, fontWeight: FontWeight.w600));
    }
    return const SizedBox.shrink();
  }
}
