import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../services/points_service.dart';

// Top-level untuk compute() — decode avatar base64 di background isolate
Uint8List? _decodeAvatar(String b64) {
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  final PointsService _service = PointsService();
  late final TabController _tab = TabController(length: 2, vsync: this);
  String _scope = 'weekly';
  bool _loading = true;
  List<dynamic> _entries = [];
  Map<String, dynamic>? _me;

  @override
  void initState() {
    super.initState();
    _tab.addListener(() {
      if (_tab.indexIsChanging) return;
      final scope = _tab.index == 0 ? 'weekly' : 'alltime';
      if (scope != _scope) {
        _scope = scope;
        _load();
      }
    });
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
      final res = await _service.leaderboard(_scope);
      if (!mounted) return;
      setState(() {
        _entries = (res['entries'] as List?) ?? [];
        _me = res['me'] is Map ? Map<String, dynamic>.from(res['me']) : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _me = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.lbTitle),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: s.lbWeekly),
            Tab(text: s.lbAllTime),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: AppTheme.textSecondary),
                SizedBox(width: 6),
                Text(_scope == 'weekly' ? s.lbWeeklyHint : s.lbAllTimeHint,
                    style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _entries.isEmpty
                    ? Center(child: Text(s.lbEmpty, style: TextStyle(color: AppTheme.textSecondary)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _entries.length,
                          separatorBuilder: (_, otherIndex) => const Divider(height: 1, indent: 64),
                          itemBuilder: (_, i) => _RankTile(
                            entry: Map<String, dynamic>.from(_entries[i] as Map),
                          ),
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _me == null
          ? null
          : _MyRankBar(rank: (_me!['rank'] as num?)?.toInt(), score: (_me!['score'] as num?)?.toInt() ?? 0),
    );
  }
}

class _RankTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _RankTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final rank = (entry['rank'] as num?)?.toInt() ?? 0;
    final nickname = entry['nickname']?.toString() ?? '—';
    final avatar = entry['avatar']?.toString() ?? '';
    final score = (entry['score'] as num?)?.toInt() ?? 0;
    final registered = entry['is_registered'] == true;
    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 28, child: _RankBadge(rank: rank)),
          const SizedBox(width: 4),
          _Avatar(base64: avatar, nickname: nickname),
        ],
      ),
      title: Row(
        children: [
          Flexible(child: Text(nickname, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600))),
          if (registered) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, size: 14, color: AppTheme.primary),
          ],
        ],
      ),
      trailing: Text('$score',
          style: AppText.bodyStrong.copyWith(color: AppTheme.primary, fontWeight: FontWeight.w800)),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    if (rank == 1) return const Text('🥇', style: TextStyle(fontSize: AppGlyph.sm), textAlign: TextAlign.center);
    if (rank == 2) return const Text('🥈', style: TextStyle(fontSize: AppGlyph.sm), textAlign: TextAlign.center);
    if (rank == 3) return const Text('🥉', style: TextStyle(fontSize: AppGlyph.sm), textAlign: TextAlign.center);
    return Text('$rank',
        textAlign: TextAlign.center,
        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary, fontWeight: FontWeight.w700));
  }
}

class _Avatar extends StatelessWidget {
  final String base64;
  final String nickname;
  const _Avatar({required this.base64, required this.nickname});

  @override
  Widget build(BuildContext context) {
    final initial = nickname.isNotEmpty ? nickname[0].toUpperCase() : '?';
    if (base64.isEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: AppTheme.accent.withValues(alpha: 0.2),
        child: Text(initial, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700)),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: compute(_decodeAvatar, base64),
      builder: (_, snap) {
        if (snap.data == null) {
          return CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.accent.withValues(alpha: 0.2),
            child: Text(initial, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700)),
          );
        }
        return CircleAvatar(radius: 18, backgroundImage: MemoryImage(snap.data!));
      },
    );
  }
}

class _MyRankBar extends StatelessWidget {
  final int? rank;
  final int score;
  const _MyRankBar({required this.rank, required this.score});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Container(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.primary,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          const Icon(Icons.person_pin_circle_outlined, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rank == null ? s.lbUnranked : '${s.lbYourRank}: #$rank',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          Text('$score',
              style: AppText.titleEmphasis.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
