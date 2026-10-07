import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import 'group_screen.dart';
import 'private_chats_screen.dart';
import 'lobby_screen.dart';
import 'call_history_screen.dart';
import '../config/theme.dart';

/// Menu "Chat" gabungan: sub-tab Pesan (private) + Grup + Room.
class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  bool _isSearching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onTabChanged);
    // PERF: JANGAN `_tab.animation!.addListener(setState)` — itu me-rebuild
    // SELURUH ChatsScreen tiap FRAME saat swipe/pindah tab (AppBar + TabBarView
    // + 3 halaman). Yang bergantung posisi tab hanya hint search & menu
    // actions → di-drive ValueListenableBuilder sempit di build().
  }

  void _onTabChanged() {
    // Search berlaku di SEMUA tab (Pesan/Grup/Room) — query dibawa pindah
    // tab, tidak di-reset (pola lama yang reset saat keluar Pesan dihapus).
    //
    // CATATAN: user ANON kini BOLEH membuka tab Pesan, Grup, maupun Global
    // Room (keputusan produk). Gate popup "lengkapi email" di sini DIHAPUS —
    // anon hanya dibatasi pada aksi tertentu (chat baru/call/room join),
    // bukan sekadar melihat tab.
    //
    // Rebuild SEKALI saat index tab berubah (bukan tiap frame animasi):
    // dipakai memperbarui hint search & menu actions (isPesanTab).
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final tabProgress = _tab.animation!.value;
    final isPesanTab = tabProgress < 0.5;
    // Search ala Pesan berlaku di ketiga tab (Pesan/Grup/Global Room).
    final showSearch = _isSearching;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        backgroundColor: AppTheme.headerGradient.colors.first,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        leading: IconButton(
          tooltip: s.searchRoomHint,
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
        ),
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
                      hintText:
                          isPesanTab ? s.searchHint : s.searchRoomHint,
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
                      case 'recent_calls':
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CallHistoryScreen(),
                          ),
                        );
                        break;
                      case 'new_group':
                        showCreateGroupDialog(context);
                        break;
                      case 'read_all':
                        final uid = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).uid;
                        if (uid == null || uid.isEmpty) return;
                        ProviderScope.containerOf(context, listen: false).read(chatProvider.notifier).markAllChatsRead(uid);
                        break;
                    }
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      value: 'recent_calls',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.call_rounded, size: 20),
                        title: Text(s.menuRecentCalls),
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    PopupMenuItem(
                      value: 'new_group',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.group_add_rounded, size: 20),
                        title: Text(s.menuNewGroup),
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
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
          GroupScreen(externalQuery: _query),
          LobbyScreen(embedded: true, externalQuery: _query),
        ],
      ),
    );
  }
}
