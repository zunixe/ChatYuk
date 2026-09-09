import 'package:flutter/material.dart';
import '../core/admin_gate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../models/room_model.dart';
import '../providers/room_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import 'room_chat_screen.dart';
import 'private_rooms_screen.dart';
import '../providers/theme_provider.dart';
import '../widgets/room_icon.dart';
import '../widgets/search_dropdown.dart';

class LobbyScreen extends StatefulWidget {
  final bool embedded;
  const LobbyScreen({super.key, this.embedded = false});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  static const _prefKey = 'lobby_country';

  @override
  void initState() {
    super.initState();
    _initCountry();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initCountry() async {
    final auth = context.read<AuthProvider>();
    final profileCountry = auth.profile?.country ?? 'Indonesia';
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    final target = (saved != null && allCountries.contains(saved))
        ? saved
        : profileCountry;
    if (!mounted) return;
    await context.read<RoomProvider>().setCountry(target);
    // Muat harga room (dual pricing) dari server.
    context.read<PointsProvider>().refreshRoomPricing();
  }

  Future<void> _onCountryChanged(String country) async {
    await context.read<RoomProvider>().setCountry(country);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, country);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    final roomProvider = context.watch<RoomProvider>();
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: widget.embedded
          ? null
          : AppBar(
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primaryDark,
                      AppTheme.primary,
                      AppTheme.accent,
                    ],
                  ),
                ),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ChatYuk',
                    style: AppText.title.copyWith(color: Colors.white),
                  ),
                  Text(
                    s.titleRooms,
                    style: AppText.bodySmall.copyWith(color: Colors.white70),
                  ),
                ],
              ),
              iconTheme: IconThemeData(color: Colors.white),
              // Fitur private room v2 (QR + admin) — admin build saja.
              actions: [
                if (AdminGate.panelBuilder != null)
                  IconButton(
                    tooltip: s.privateRoomsTitle,
                    icon: const Icon(Icons.meeting_room_outlined),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PrivateRoomsScreen(),
                        ),
                      );
                    },
                  ),
              ],
            ),
      body: Column(
        children: [
          // Pilih negara (hanya room global — tab Grup punya layar sendiri).
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.public_rounded,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: SearchDropdown(
                      value: roomProvider.country,
                      label: s.lobbyCountryHint,
                      icon: Icons.public_rounded,
                      items: allCountries,
                      labels: allCountries,
                      onChanged: (v) => _onCountryChanged(v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _GlobalRoomsTab(rooms: roomProvider.rooms, loaded: roomProvider.hasLoaded),
          ),
        ],
      ),
    );
  }
}

class _GlobalRoomsTab extends StatelessWidget {
  final List<RoomModel> rooms;
  final bool loaded;
  const _GlobalRoomsTab({required this.rooms, this.loaded = true});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    if (rooms.isEmpty && !loaded) {
      // Data belum selesai dimuat — loader tema (nol warna abu skeleton).
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🏠', style: TextStyle(fontSize: AppGlyph.xl)),
            SizedBox(height: 12),
            Text(
              s.noRooms,
              style: AppText.bodyStrong.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      itemCount: rooms.length,
      itemBuilder: (_, i) => _RoomCard(room: rooms[i]),
    );
  }
}


class _RoomCard extends StatelessWidget {
  final RoomModel room;
  const _RoomCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RoomChatScreen(room: room)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                RoomIcon(category: room.category, emoji: room.icon),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.roomName(room.category),
                        style: AppText.titleEmphasis,
                      ),
                      SizedBox(height: 2),
                      Text(
                        s.roomDesc(room.category),
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.online.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppTheme.online,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${room.onlineCount} ${s.roomOnlineCount}',
                        style: AppText.caption.copyWith(
                          color: AppTheme.online,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
}

/// Icon dalam squircle tinted untuk item menu � gaya konsisten
/// dengan bottom sheet lain.

