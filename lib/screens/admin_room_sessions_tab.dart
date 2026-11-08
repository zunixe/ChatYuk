import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../config/supabase_config.dart';
import '../config/theme.dart';
import '../core/admin_gate.dart';
import '../providers/riverpod/locale_provider.dart';
import '../utils.dart';

/// Admin — Room v2 "Sesi Terjadwal + Host" (docs/ROOM_V2_TASK.md).
/// KPI sesi + form jadwal (room + host is_host + judul + format + jam)
/// + kelola host (toggle is_host) + tabel sesi (peak, gifts, jadwal vs mulai).
class AdminRoomSessionsTab extends ConsumerStatefulWidget {
  const AdminRoomSessionsTab({super.key});

  @override
  ConsumerState<AdminRoomSessionsTab> createState() =>
      _AdminRoomSessionsTabState();
}

class _AdminRoomSessionsTabState extends ConsumerState<AdminRoomSessionsTab> {
  bool _loading = true;
  Map<String, dynamic> _stats = const {};
  List<Map<String, dynamic>> _sessions = const [];
  List<Map<String, dynamic>> _rooms = const [];
  List<Map<String, dynamic>> _hosts = const [];

  // Form jadwal.
  String? _roomId;
  String? _hostUid;
  final _titleCtrl = TextEditingController();
  String _format = 'bebas';
  DateTime? _startAt;
  DateTime? _endAt;
  bool _saving = false;

  // Kelola host.
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = const [];
  bool _searching = false;

  static const _formats = [
    'bebas',
    'karaoke',
    'curhat',
    'debat',
    'quiz',
    'werewolf',
    'musik',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _isAdmin =>
      AdminGate.isRealAdmin(SupabaseConfig.client.auth.currentUser?.email);

  Future<void> _load() async {
    if (!_isAdmin) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final sb = SupabaseConfig.client;
      final results = await Future.wait<dynamic>([
        sb.rpc('admin_room_session_stats', params: {'p_days': 30}),
        sb
            .from('room_sessions')
            .select(
                'id,room_id,title,format,starts_at,ends_at,status,started_at,ended_at,peak_viewers,gifts_total,host_uid')
            .order('starts_at', ascending: false)
            .limit(100),
        sb
            .from('rooms')
            .select('id,name,icon')
            .eq('is_private', false)
            .order('order')
            .limit(200),
        sb.from('profiles').select('id,nickname').eq('is_host', true).limit(200),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] is Map
            ? Map<String, dynamic>.from(results[0] as Map)
            : const {};
        _sessions = _asList(results[1]);
        _rooms = _asList(results[2]);
        _hosts = _asList(results[3]);
        _roomId ??= _rooms.isNotEmpty ? '${_rooms.first['id']}' : null;
        _hostUid ??= _hosts.isNotEmpty ? '${_hosts.first['id']}' : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('$e');
    }
  }

  List<Map<String, dynamic>> _asList(dynamic v) => (v as List)
      .whereType<Map>()
      .map((r) => Map<String, dynamic>.from(r))
      .toList(growable: false);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickDateTime({required bool start}) async {
    final now = DateTime.now();
    final base = (start ? _startAt : _endAt) ?? now.add(const Duration(hours: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null || !mounted) return;
    final dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() {
      if (start) {
        _startAt = dt;
        if (_endAt == null || !_endAt!.isAfter(dt)) {
          _endAt = dt.add(const Duration(hours: 1));
        }
      } else {
        _endAt = dt;
      }
    });
  }

  Future<void> _save() async {
    final s = ref.read(localeProvider).s;
    if (_roomId == null || _hostUid == null) {
      _snack(s.adminRsNoHost);
      return;
    }
    if (_titleCtrl.text.trim().length < 3) {
      _snack(s.adminRsTitle);
      return;
    }
    if (_startAt == null || _endAt == null) return;
    setState(() => _saving = true);
    try {
      await SupabaseConfig.client.rpc('schedule_room_session', params: {
        'p_room_id': _roomId,
        'p_host_uid': _hostUid,
        'p_title': _titleCtrl.text.trim(),
        'p_format': _format,
        'p_starts_at': _startAt!.toUtc().toIso8601String(),
        'p_ends_at': _endAt!.toUtc().toIso8601String(),
      });
      if (!mounted) return;
      _titleCtrl.clear();
      _snack(s.adminRsSaved);
      await _load();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _searchUsers() async {
    final q = _searchCtrl.text.trim();
    if (q.length < 2) return;
    setState(() => _searching = true);
    try {
      final rows = await SupabaseConfig.client
          .from('profiles')
          .select('id,nickname,is_host')
          .ilike('nickname', '%$q%')
          .limit(20);
      if (!mounted) return;
      setState(() => _searchResults = _asList(rows));
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _toggleHost(String uid, bool value) async {
    final s = ref.read(localeProvider).s;
    try {
      await SupabaseConfig.client.rpc(
        'admin_set_host',
        params: {'p_uid': uid, 'p_is_host': value},
      );
      if (!mounted) return;
      setState(() {
        _searchResults = [
          for (final r in _searchResults)
            if ('${r['id']}' == uid) {...r, 'is_host': value} else r,
        ];
      });
      _snack(s.adminRsHostActive(
          _searchResults.firstWhere((r) => '${r['id']}' == uid,
              orElse: () => const {'nickname': ''})['nickname']?.toString() ??
              ''));
      await _load();
    } catch (e) {
      _snack('$e');
    }
  }

  String _fmtDt(DateTime? v) => v == null ? '—' : formatDateTimeWib(v);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    if (!_isAdmin) {
      return Center(
        child: Text(
          s.adminRsEmpty,
          style: AppText.body.copyWith(color: AppTheme.textSecondary),
        ),
      );
    }
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppTheme.primary,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          _kpiRow(s),
          const SizedBox(height: 16),
          _scheduleForm(s),
          const SizedBox(height: 16),
          _hostManager(s),
          const SizedBox(height: 16),
          _sessionTable(s),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );

  Widget _kpi(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppText.caption
                    .copyWith(color: AppTheme.textSecondary)),
            const SizedBox(height: 2),
            Text(value, style: AppText.titleEmphasis),
          ],
        ),
      );

  Widget _kpiRow(S s) {
    String n(Object? v) => '${v ?? 0}';
    return _card(
      child: Wrap(
        runSpacing: 12,
        children: [
          Row(children: [
            _kpi(s.adminRsKpiSessions, n(_stats['sessions'])),
            _kpi(s.adminRsKpiOnTime, '${n(_stats['on_time_pct'])}%'),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _kpi(s.adminRsKpiDuration, '${n(_stats['avg_duration_min'])} ${s.adminRsMinutes}'),
            _kpi(s.adminRsKpiPeak, n(_stats['avg_peak_viewers'])),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _kpi(s.adminRsKpiGifts, n(_stats['total_gifts'])),
            const Spacer(),
          ]),
        ],
      ),
    );
  }

  Widget _scheduleForm(S s) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.adminRsScheduleTitle, style: AppText.titleEmphasis),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _roomId,
            decoration: InputDecoration(labelText: s.adminRsRoom),
            items: [
              for (final r in _rooms)
                DropdownMenuItem(
                  value: '${r['id']}',
                  child: Text('${r['icon'] ?? '💬'} ${r['name'] ?? r['id']}',
                      style: AppText.body),
                ),
            ],
            onChanged: (v) => setState(() => _roomId = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _hostUid,
            decoration: InputDecoration(labelText: s.adminRsHost),
            items: [
              for (final h in _hosts)
                DropdownMenuItem(
                  value: '${h['id']}',
                  child: Text('${h['nickname'] ?? h['id']}',
                      style: AppText.body),
                ),
            ],
            onChanged: (v) => setState(() => _hostUid = v),
          ),
          if (_hosts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(s.adminRsNoHost,
                  style: AppText.caption
                      .copyWith(color: AppTheme.danger)),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _titleCtrl,
            style: AppText.body,
            decoration: InputDecoration(labelText: s.adminRsTitle),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _format,
            decoration: InputDecoration(labelText: s.adminRsFormat),
            items: [
              for (final f in _formats)
                DropdownMenuItem(
                  value: f,
                  child: Text(f, style: AppText.body),
                ),
            ],
            onChanged: (v) => setState(() => _format = v ?? 'bebas'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDateTime(start: true),
                  child: Text(
                    '${s.adminRsStart}: ${_fmtDt(_startAt)}',
                    style: AppText.label,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDateTime(start: false),
                  child: Text(
                    '${s.adminRsEnd}: ${_fmtDt(_endAt)}',
                    style: AppText.label,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(s.adminRsSave),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hostManager(S s) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.adminRsManageHost, style: AppText.titleEmphasis),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: AppText.body,
                  decoration:
                      InputDecoration(hintText: s.adminRsSearchUser),
                  onSubmitted: (_) => _searchUsers(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _searching ? null : _searchUsers,
                icon: const Icon(Icons.search_rounded, size: 20),
              ),
            ],
          ),
          for (final r in _searchResults)
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${r['nickname'] ?? r['id']}',
                  style: AppText.bodyStrong),
              value: r['is_host'] == true,
              onChanged: (v) => _toggleHost('${r['id']}', v),
            ),
        ],
      ),
    );
  }

  Widget _sessionTable(S s) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.adminRsTableTitle, style: AppText.titleEmphasis),
          const SizedBox(height: 8),
          if (_sessions.isEmpty)
            Text(s.adminRsEmpty,
                style: AppText.bodySmall
                    .copyWith(color: AppTheme.textSecondary))
          else
            for (final row in _sessions) _sessionRow(s, row),
        ],
      ),
    );
  }

  Widget _sessionRow(S s, Map<String, dynamic> r) {
    final status = '${r['status'] ?? ''}';
    final startsAt = DateTime.tryParse('${r['starts_at']}');
    final startedAt = DateTime.tryParse('${r['started_at']}');
    final lateMin = (startsAt != null && startedAt != null)
        ? startedAt.difference(startsAt).inMinutes
        : null;
    final color = switch (status) {
      'live' => AppTheme.danger,
      'ended' => AppTheme.textSecondary,
      'cancelled' => AppTheme.textSecondary,
      _ => AppTheme.primary,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r['title'] ?? ''}',
                  style: AppText.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(status.toUpperCase(),
                    style: AppText.micro.copyWith(color: color)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${r['room_id']} · ${_fmtDt(startsAt)} → ${startedAt == null ? '—' : _fmtDt(startedAt)}'
            '${lateMin != null && lateMin > 0 ? ' (${s.adminRsLate} $lateMin ${s.adminRsMinutes})' : ''}',
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '👥 ${r['peak_viewers'] ?? 0} · 🎁 ${r['gifts_total'] ?? 0}',
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const Divider(height: 12),
        ],
      ),
    );
  }
}
