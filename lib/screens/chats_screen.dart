import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../widgets/anon_prompt_dialog.dart';
import 'group_screen.dart';
import 'private_chats_screen.dart';
import 'lobby_screen.dart';

/// Menu "Chat" gabungan: sub-tab Pesan (private) + Grup + Room.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  bool _isSearching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onTabChanged);
    _tab.animation!.addListener(_onTabAnimated);
  }

  void _onTabChanged() {
    if (_tab.index != 0 && _isSearching) {
      setState(() {
        _isSearching = false;
        _searchCtrl.clear();
        _query = '';
      });
    }
    // Tab Grup khusus terdaftar (tap maupun swipe) — anon dikembalikan
    // ke tab sebelumnya + dialog ajakan daftar (pola timeline _onNavTap).
    // Sesi dummy (admin jadi anon) diizinkan — bukan anon sungguhan.
    if (_tab.index == 1 && mounted) {
      final auth = context.read<AuthProvider>();
      final allowed = (auth.profile?.isRegistered ?? false) ||
          auth.dummySessionActive;
      if (!allowed) {
        showAnonPromptDialog(context);
        final prev = _tab.previousIndex == 1 ? 0 : _tab.previousIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _tab.index == 1) _tab.index = prev;
        });
      }
    }
  }

  void _onTabAnimated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tab.animation!.removeListener(_onTabAnimated);
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final tabProgress = _tab.animation!.value;
    final isPesanTab = tabProgress < 0.5;
    final showSearch = _isSearching && isPesanTab;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.headerGradient.colors.first,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        leading: isPesanTab
            ? IconButton(
                tooltip: s.searchHint,
                icon: Icon(showSearch ? Icons.close : Icons.search_rounded),
                color: Colors.white,
                onPressed: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      _searchCtrl.clear();
                      _query = '';
                    }
                  });
                },
              )
            : null,
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SizeTransition(
              sizeFactor: anim,
              axis: Axis.horizontal,
              axisAlignment: -1,
              child: child,
            ),
          ),
          child: showSearch
              ? SizedBox(
                  key: const ValueKey('search'),
                  height: 40,
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                    style: AppText.body.copyWith(color: Colors.white),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: s.searchHint,
                      hintStyle: AppText.body.copyWith(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 20),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 36, minHeight: 0),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: Colors.white70),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white24,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                )
              : Column(
                  key: const ValueKey('title'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ChatYuk',
                        style: AppText.title.copyWith(color: Colors.white)),
                    Text(
                      s.navChats,
                      style: AppText.bodySmall.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        // Menu ⋮ gaya WA: Grup Baru + Tandai semua dibaca (tab Pesan).
        actions: isPesanTab
            ? [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    switch (v) {
                      case 'new_group':
                        _tab.animateTo(1);
                        break;
                      case 'read_all':
                        final uid = context.read<AuthProvider>().uid;
                        if (uid == null || uid.isEmpty) return;
                        context.read<ChatProvider>().markAllChatsRead(uid);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'new_group',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.group_add_rounded, size: 20),
                        title: Text(s.menuNewGroup),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'read_all',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.done_all_rounded, size: 20),
                        title: Text(s.menuReadAll),
                      ),
                    ),
                  ],
                ),
              ]
            : null,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: s.tabMessages),
            Tab(text: s.tabGroups),
            Tab(text: s.tabRooms),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          PrivateChatsScreen(embedded: true, externalQuery: _query),
          const GroupScreen(),
          LobbyScreen(embedded: true),
        ],
      ),
    );
  }
}
