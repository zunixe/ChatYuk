import 'package:flutter/material.dart';
import '../core/admin_gate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../providers/room_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import 'private_rooms_screen.dart';
import '../providers/theme_provider.dart';
import '../widgets/search_dropdown.dart';
import 'rooms_explore_screen.dart';

class LobbyScreen extends StatefulWidget {
  final bool embedded;
  final String? externalQuery;
  const LobbyScreen({super.key, this.embedded = false, this.externalQuery});

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
    if (mounted) context.read<RoomProvider>().fetchExplore();
  }

  Future<void> _onCountryChanged(String country) async {
    await context.read<RoomProvider>().setCountry(country);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, country);
    if (mounted) context.read<RoomProvider>().fetchExplore(refresh: true);
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
          // Field saja tanpa kartu & ikon samping (seperti filter online).
          Padding(
            padding: EdgeInsets.fromLTRB(10, 12, 10, 4),
            child: SearchDropdown(
              value: roomProvider.country,
              label: s.lobbyCountryHint,
              icon: Icons.public_rounded,
              items: allCountries,
              labels: allCountries,
              searchHint: s.searchCountry,
              emptyText: s.searchNoResult,
              onChanged: (v) => _onCountryChanged(v),
            ),
          ),
          Expanded(
            child: RoomsExploreScreen(
              externalQuery: widget.externalQuery,
            ),
          ),
        ],
      ),
    );
  }
}

