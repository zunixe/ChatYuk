import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/admin_gate.dart';
import '../core/perf/perf_probe.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../providers/riverpod/room_provider.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/points_provider.dart';
import 'private_rooms_screen.dart';
import '../providers/riverpod/theme_provider.dart';
import '../widgets/search_dropdown.dart';
import 'rooms_explore_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  final bool embedded;
  final String? externalQuery;

  /// Kategori awal untuk RoomsExploreScreen (mis. 'general' saat dibuka dari
  /// kapsul Global Room di halaman Online). null = default.
  final String? initialCategory;
  const LobbyScreen({
    super.key,
    this.embedded = false,
    this.externalQuery,
    this.initialCategory,
  });

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
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
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    final profileCountry = auth.profile?.country ?? 'Indonesia';
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    final target = (saved != null && allCountries.contains(saved))
        ? saved
        : profileCountry;
    if (!mounted) return;
    await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).setCountry(target);
    // Muat harga room (dual pricing) dari server.
    ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier).refreshRoomPricing();
    if (mounted) ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).fetchExplore();
  }

  Future<void> _onCountryChanged(String country) async {
    await ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).setCountry(country);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, country);
    if (mounted) ProviderScope.containerOf(context, listen: false).read(roomProvider.notifier).fetchExplore(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('Lobby');
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    // PERF: build utama hanya butuh `country` — daftar room ada di
    // RoomsExploreScreen (baca sendiri). Dulu `watch<RoomProvider>()` penuh
    // → seluruh layar rebuild tiap notify RoomProvider (sering).
    final country = ref.watch(roomProvider.select((rp) => rp.country));
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
              value: country,
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
              initialCategory: widget.initialCategory,
            ),
          ),
        ],
      ),
    );
  }
}

