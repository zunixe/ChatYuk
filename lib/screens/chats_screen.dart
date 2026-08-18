import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import 'private_chats_screen.dart';
import 'lobby_screen.dart';

/// Menu "Chat" gabungan: sub-tab Pesan (private) + Room.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.headerGradient.colors.first,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: AppTheme.headerGradient,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ChatYuk', style: AppText.title.copyWith(color: Colors.white)),
            Text(s.navChats, style: AppText.bodySmall.copyWith(color: Colors.white70)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: s.tabMessages),
            Tab(text: s.tabRooms),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          PrivateChatsScreen(embedded: true),
          LobbyScreen(embedded: true),
        ],
      ),
    );
  }
}
