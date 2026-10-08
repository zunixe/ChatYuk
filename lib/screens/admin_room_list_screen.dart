import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;

import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../config/theme.dart';

import '../core/perf/perf_probe.dart';
import '../core/ui/scroll_pagination.dart';
import '../providers/riverpod/admin_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../utils.dart';
import '../widgets/admin_error_view.dart';
import 'admin_room_view_screen.dart';

/// Admin: daftar GRUP (private rooms) yang dibuat user — Monitor Grup.
///
/// Search + filter negara server-side (RPC `admin_list_private_rooms_page`)
/// sehingga list tetap ringan walau grup banyak.
class AdminRoomListScreen extends ConsumerStatefulWidget {
  const AdminRoomListScreen({super.key});

  @override
  ConsumerState<AdminRoomListScreen> createState() =>
      _AdminRoomListScreenState();
}

class _AdminRoomListScreenState extends ConsumerState<AdminRoomListScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  Timer? _searchDebounce;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  ScrollPagination? _pagination;
  String _query = '';
  String _country = '';

  /// Daftar negara yang tersedia (chip filter) — diisi dari hasil pertama.
  final Set<String> _countries = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final admin =
        ProviderScope.containerOf(context, listen: false).read(adminProvider);
    Future.microtask(() {
      admin.setRoomsFilter(search: '', country: '');
      admin.fetchRooms();
    });
    _startTimer();
    _pagination = ScrollPagination(
      controller: _scrollCtrl,
      onLoadMore: () {
        if (!mounted) return;
        admin.fetchMoreRooms();
      },
    );
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    final admin =
        ProviderScope.containerOf(context, listen: false).read(adminProvider);
    // 30 dtk — daftar grup tak perlu sesering monitor chat.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      admin.fetchRooms();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    } else if (state == AppLifecycleState.resumed && mounted) {
      if (_refreshTimer == null) _startTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _searchDebounce?.cancel();
    _pagination?.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _query = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final admin =
          ProviderScope.containerOf(context, listen: false).read(adminProvider);
      admin.setRoomsFilter(search: _query, country: _country);
      admin.fetchRooms();
    });
  }

  void _selectCountry(String c) {
    setState(() => _country = c);
    final admin =
        ProviderScope.containerOf(context, listen: false).read(adminProvider);
    admin.setRoomsFilter(search: _query, country: _country);
    admin.fetchRooms();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final ap = ref.watch(adminProvider);
    PerfProbe.buildCount('AdminRooms');

    final rooms = ap.rooms;
    final loading = ap.roomsLoading;
    final err = ap.roomsError;

    // Kumpulkan negara untuk chip filter (hanya saat belum difilter).
    if (_country.isEmpty) {
      for (final r in rooms) {
        final c = '${r['country'] ?? ''}'.trim();
        if (c.isNotEmpty) _countries.add(c);
      }
    }

    return Column(
      children: [
        _searchBar(s),
        if (_countries.isNotEmpty) _countryChips(s),
        Expanded(
          child: loading && rooms.isEmpty
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              : err != null && rooms.isEmpty
                  ? AdminErrorView(
                      s: s,
                      error: err,
                      onRetry: () => ap.fetchRooms(),
                    )
                  : rooms.isEmpty
                      ? _empty(s)
                      : RefreshIndicator(
                          onRefresh: () => ap.fetchRooms(),
                          child: ListView.builder(
                            controller: _scrollCtrl,
                            padding:
                                const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            itemCount: rooms.length + (ap.roomsHasMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i >= rooms.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }
                              return _roomCard(s, rooms[i]);
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _searchBar(S s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onQueryChanged,
        style: AppText.body,
        decoration: InputDecoration(
          hintText: s.adminRoomSearch,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onQueryChanged('');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: AppTheme.bgInput,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _countryChips(S s) {
    final list = _countries.toList()..sort();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(s.adminRoomCountryAll, _country.isEmpty, () => _selectCountry('')),
          for (final c in list)
            _chip(c, _country == c, () => _selectCountry(c)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        labelStyle: AppText.bodySmall.copyWith(
          color: selected ? Colors.white : AppTheme.textPrimary,
        ),
        selectedColor: AppTheme.primary,
        backgroundColor: AppTheme.bgInput,
        side: BorderSide(color: AppTheme.divider),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _empty(S s) {
    return Center(
      child: Text(
        _query.isEmpty && _country.isEmpty ? s.adminRoomNoData : s.adminRoomNoResult,
        style: AppText.body.copyWith(color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _roomCard(S s, Map<String, dynamic> r) {
    final name = '${r['name'] ?? ''}'.trim();
    final owner = '${r['owner_name'] ?? ''}'.trim();
    final country = '${r['country'] ?? ''}'.trim();
    final icon = '${r['icon'] ?? '💬'}';
    final hasPass = r['has_password'] == true;
    final memberCount = (r['member_count'] as num?)?.toInt() ?? 0;
    final msgCount = (r['message_count'] as num?)?.toInt() ?? 0;
    final lastMsg = '${r['last_message'] ?? ''}'.trim();
    final lastSender = '${r['last_message_sender'] ?? ''}'.trim();
    final expiresAt = r['expires_at'] != null
        ? DateTime.tryParse('${r['expires_at']}')
        : null;
    final expired =
        expiresAt != null && expiresAt.isBefore(DateTime.now());
    final lastAt = r['last_message_at'] != null
        ? DateTime.tryParse('${r['last_message_at']}')
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminRoomViewScreen(
                  roomId: '${r['id']}',
                  roomInfo: r,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ikon grup.
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(icon, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name.isEmpty ? '—' : name,
                              style: AppText.bodyStrong,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasPass)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(Icons.lock_outline,
                                  size: 14, color: AppTheme.textSecondary),
                            ),
                          if (expired)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  s.adminRoomExpired,
                                  style: AppText.micro
                                      .copyWith(color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.adminRoomOwner}: ${owner.isEmpty ? '—' : owner}'
                        '${country.isNotEmpty ? ' · $country' : ''}',
                        style: AppText.bodySmall
                            .copyWith(color: AppTheme.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.group_outlined,
                              size: 13, color: AppTheme.textSecondary),
                          const SizedBox(width: 3),
                          Text('$memberCount',
                              style: AppText.micro
                                  .copyWith(color: AppTheme.textSecondary)),
                          const SizedBox(width: 10),
                          Icon(Icons.chat_bubble_outline,
                              size: 13, color: AppTheme.textSecondary),
                          const SizedBox(width: 3),
                          Text('$msgCount',
                              style: AppText.micro
                                  .copyWith(color: AppTheme.textSecondary)),
                          const Spacer(),
                          if (lastAt != null)
                            Text(
                              _relTime(lastAt),
                              style: AppText.micro
                                  .copyWith(color: AppTheme.textSecondary),
                            ),
                        ],
                      ),
                      if (lastMsg.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${lastSender.isNotEmpty ? "$lastSender: " : ''}$lastMsg',
                          style: AppText.bodySmall
                              .copyWith(color: AppTheme.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _relTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'baru';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 30) return '${d.inDays}d';
    return formatDateWib(t);
  }
}
