import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../models/room_model.dart';
import '../providers/room_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import 'room_chat_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

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

  Future<void> _initCountry() async {
    final auth = context.read<AuthProvider>();
    final profileCountry = auth.profile?.country ?? 'Indonesia';
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    final target = (saved != null && allCountries.contains(saved)) ? saved : profileCountry;
    if (!mounted) return;
    // arahkan provider ke negara profil (default) / terakhir terpilih
    await context.read<RoomProvider>().setCountry(target);
  }

  Future<void> _onCountryChanged(String country) async {
    await context.read<RoomProvider>().setCountry(country);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, country);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final roomProvider = context.watch<RoomProvider>();
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.primaryDark, AppTheme.primary, AppTheme.accent],
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ChatYuk', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            Text(s.titleRooms, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Pilih negara
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.public, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: roomProvider.country,
                        isExpanded: true,
                        isDense: true,
                        menuMaxHeight: 400,
                        hint: Text(s.lobbyCountryHint, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                        items: [
                          for (final c in allCountries)
                            DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis, maxLines: 1, style: const TextStyle(fontSize: 14))),
                        ],
                        onChanged: (v) { if (v != null) _onCountryChanged(v); },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: roomProvider.rooms.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🏠', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        Text(s.noRooms, style: const TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: roomProvider.rooms.length,
                    itemBuilder: (_, i) => _RoomCard(room: roomProvider.rooms[i]),
                  ),
          ),
        ],
      ),
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
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(room.icon, style: const TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.roomName(room.category), style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(s.roomDesc(room.category), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.online.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.online, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('${room.onlineCount} ${s.roomOnlineCount}', style: const TextStyle(color: AppTheme.online, fontSize: 12, fontWeight: FontWeight.w600)),
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