import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../models/room_model.dart';
import '../core/nav_guard.dart';
import '../core/perf/perf_probe.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/room_provider.dart';
import '../providers/riverpod/theme_provider.dart';
import '../widgets/empty_state_view.dart';
import 'room_chat_screen.dart';
import 'rooms_explore/widgets/category_chips.dart';
import 'rooms_explore/widgets/create_room_sheet.dart';
import 'rooms_explore/widgets/room_explore_card.dart';
import '../widgets/message/photo_prefetch.dart';
import '../config/strings.dart';

/// Explore room ala gambar: chip kategori (Rame = agregat online > 0) +
/// satu list global + grup + FAB Buat Room (gratis).
/// Dipakai sebagai isi tab Room di [LobbyScreen] (tanpa Scaffold sendiri).
/// [externalQuery]: filter nama + isi dari ikon cari AppBar (pola Pesan).
class RoomsExploreScreen extends ConsumerStatefulWidget {
  final String? externalQuery;

  /// Kategori yang dipilih saat layar pertama dibuka (mis. 'general' saat
  /// dibuka dari kapsul Global Room di halaman Online). null = default.
  final String? initialCategory;
  const RoomsExploreScreen({
    super.key,
    this.externalQuery,
    this.initialCategory,
  });

  @override
  ConsumerState<RoomsExploreScreen> createState() => _RoomsExploreScreenState();
}

class _RoomsExploreScreenState extends ConsumerState<RoomsExploreScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final rp = ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier);
      if (widget.initialCategory != null) {
        rp.setExploreCategory(widget.initialCategory!);
      }
      rp.fetchExplore();
    });
  }

  Future<void> _openRoom(String roomId, int index) async {
    final rp = ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier);
    final rooms = rp.exploreRooms;
    if (index < 0 || index >= rooms.length) return;
    final room = rooms[index];
    unawaited(rp.markRoomRead(roomId));
    if (!mounted) return;
    final navKey = navKeyRoom(room.id);
    if (!tryClaimNav(navKey)) return;
    // Precache poster/thumb dari cache (bila ada) — frame pertama room isi.
    try {
      await PhotoPrefetch.precacheAll(context, 'room_${room.id}')
          .timeout(const Duration(milliseconds: 450));
    } catch (_) {}
    if (!mounted) {
      releaseNav(navKey);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomChatScreen(room: room)),
    ).then((_) => releaseNav(navKey));
    if (mounted) ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).fetchExplore();
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('RoomsExplore');
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    // PERF: `exploreRooms` mengembalikan list BARU tiap akses (`.where()
    // .toList()` + sort) → TIDAK boleh di-select langsung (identity selalu
    // beda = rebuild tiap notify). `select` signature `exploreSig` (murni,
    // dari isi `_explore`) + category + loading → rebuild hanya saat data
    // benar-benar berubah. Data aktual dibaca via `read` (snapshot terbaru
    // saat rebuild dipicu).
    ref.watch(roomProvider.select((rp) => rp.exploreSig));
    final exploreCategory =
        ref.watch(roomProvider.select((rp) => rp.exploreCategory));
    final exploreLoading =
        ref.watch(roomProvider.select((rp) => rp.exploreLoading));
    final rp = ref.read(roomProvider.notifier);
    final q = (widget.externalQuery ?? '').trim().toLowerCase();
    final searching = q.isNotEmpty;
    final rooms = searching
        ? rp.exploreRooms.where((r) {
            final title = r.name.isNotEmpty
                ? r.name
                : s.roomName(r.category);
            return title.toLowerCase().contains(q) ||
                r.lastText.toLowerCase().contains(q) ||
                r.lastSenderName.toLowerCase().contains(q);
          }).toList()
        : rp.exploreRooms;
    final isRame = exploreCategory == 'rame' && !searching;

    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 8),
            CategoryChips(
              selected: exploreCategory,
              onSelect: (id) => rp.setExploreCategory(id),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _buildList(s, rp, rooms, isRame, searching, exploreLoading),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => showCreateExploreRoomDialog(
                context,
                exploreCategory,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primaryDark,
                      AppTheme.primary,
                      AppTheme.accent,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s.btnCreateRoom,
                      style: AppText.bodyStrong.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList(
    S s,
    RoomNotifier rp,
    List<RoomModel> rooms,
    bool isRame,
    bool searching,
    bool exploreLoading,
  ) {
    if (exploreLoading && rooms.isEmpty && !searching) {
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
    if (rooms.isEmpty) {
      return EmptyStateView(
        icon: searching ? Icons.search_off_rounded : Icons.home_rounded,
        title: searching
            ? s.searchNoResult
            : (isRame ? s.exploreEmptyRame : s.noRooms),
        hint: searching
            ? ''
            : (isRame ? s.exploreEmptyRameHint : s.noRoomsHint),
      );
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () => rp.fetchExplore(refresh: true),
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          10,
          8,
          10,
          MediaQuery.of(context).padding.bottom + 88,
        ),
        itemCount: rooms.length,
        itemBuilder: (_, i) => RoomExploreCard(
          room: rooms[i],
          onTap: () => _openRoom(rooms[i].id, i),
        ),
      ),
    );
  }
}
