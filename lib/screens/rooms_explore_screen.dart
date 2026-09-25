import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/strings.dart';
import '../config/theme.dart';
import '../models/room_model.dart';
import '../providers/locale_provider.dart';
import '../providers/room_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/empty_state_view.dart';
import 'room_chat_screen.dart';
import 'rooms_explore/widgets/category_chips.dart';
import 'rooms_explore/widgets/create_room_sheet.dart';
import 'rooms_explore/widgets/room_explore_card.dart';

/// Explore room ala gambar: chip kategori (Rame = agregat online > 0) +
/// satu list global + grup + FAB Buat Room (gratis).
/// Dipakai sebagai isi tab Room di [LobbyScreen] (tanpa Scaffold sendiri).
/// [externalQuery]: filter nama + isi dari ikon cari AppBar (pola Pesan).
class RoomsExploreScreen extends StatefulWidget {
  final String? externalQuery;
  const RoomsExploreScreen({super.key, this.externalQuery});

  @override
  State<RoomsExploreScreen> createState() => _RoomsExploreScreenState();
}

class _RoomsExploreScreenState extends State<RoomsExploreScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<RoomProvider>().fetchExplore();
    });
  }

  Future<void> _openRoom(String roomId, int index) async {
    final rp = context.read<RoomProvider>();
    final rooms = rp.exploreRooms;
    if (index < 0 || index >= rooms.length) return;
    final room = rooms[index];
    unawaited(rp.markRoomRead(roomId));
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomChatScreen(room: room)),
    );
    if (mounted) context.read<RoomProvider>().fetchExplore();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final rp = context.watch<RoomProvider>();
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
    final isRame = rp.exploreCategory == 'rame' && !searching;

    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 8),
            CategoryChips(
              selected: rp.exploreCategory,
              onSelect: (id) => rp.setExploreCategory(id),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _buildList(s, rp, rooms, isRame, searching),
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
                rp.exploreCategory,
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
    RoomProvider rp,
    List<RoomModel> rooms,
    bool isRame,
    bool searching,
  ) {
    if (rp.exploreLoading && rooms.isEmpty && !searching) {
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
