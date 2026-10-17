import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/strings.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../core/nav_guard.dart';
import '../models/room_model.dart';
import '../providers/riverpod/room_notifications_provider.dart';
import '../providers/riverpod/room_provider.dart';
import '../widgets/chat_yuk_chat_header.dart';
import '../widgets/room_notif_sidebar.dart';
import 'room_chat_screen.dart';
import 'group_screen.dart';
import 'private_chats_screen.dart';
import 'lobby_screen.dart';
import 'call_history_screen.dart';
import '../config/theme.dart';

/// Tab di dalam section PESAN: chat pribadi + grup jadi satu tempat.
enum ChatTab { private, groups }

/// Tujuan geser horizontal di halaman Chat — urutan ala Timeline:
/// Private → Groups → Rooms → (balik) Groups → Private.
/// [velocity] negatif = geser ke KIRI (maju). null = tidak berpindah.
({ChatSection section, ChatTab tab})? chatSwipeTarget({
  required ChatSection section,
  required ChatTab tab,
  required double velocity,
  double minVelocity = 260,
}) {
  if (velocity.abs() < minVelocity) return null;
  final forward = velocity < 0;
  if (forward) {
    // Private → Groups (masih di section Pesan).
    if (section == ChatSection.messages && tab == ChatTab.private) {
      return (section: ChatSection.messages, tab: ChatTab.groups);
    }
    // Groups → Rooms.
    if (section == ChatSection.messages) {
      return (section: ChatSection.rooms, tab: tab);
    }
    return null; // Rooms = ujung kanan
  }
  // Mundur: Rooms → Groups.
  if (section == ChatSection.rooms) {
    return (section: ChatSection.messages, tab: ChatTab.groups);
  }
  // Groups → Private.
  if (tab == ChatTab.groups) {
    return (section: ChatSection.messages, tab: ChatTab.private);
  }
  return null; // Private = ujung kiri
}

/// Menu "Chat" gabungan: section Pesan (private) + Grup + Room.
///
/// Header ringkas (ala Timeline) dengan menu pindah section; TabBar lama
/// dihapus. Isi daftar berganti memakai [IndexedStack] (state tiap section
/// tetap hidup — perilaku sama dengan TabBarView lama).
/// Lebar perkiraan menu titik-3 (untuk memposisikan tepat di bawah ikon).
const double _kMoreMenuWidth = 200;

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  ChatSection _section = ChatSection.messages;
  ChatTab _tab = ChatTab.private;
  bool _isSearching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';
  final _moreBtnKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Notifikasi room/grup: muat data global room sekali (TTL di provider).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(roomProvider.notifier).loadMyGlobalRooms(refresh: true);
      }
    });
  }

  /// Buka room/grup dari sidebar notifikasi (langsung, dengan nav guard).
  /// Notifikasi hanya muncul untuk room yang PERNAH dibuka user, jadi gate
  /// password/kuota join tidak relevan lagi.
  void _openNotifRoom(RoomModel room) {
    final navKey = navKeyRoom(room.id);
    if (!tryClaimNav(navKey)) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => RoomChatScreen(room: room)))
        .then((_) => releaseNav(navKey));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _changeSection(ChatSection s) {
    if (_section == s) return;
    setState(() => _section = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final isPesan = _section == ChatSection.messages;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: ChatYukChatHeader(
        section: _section,
        onSectionChanged: _changeSection,
        unreadCounts: _unreadCounts(),
        onSearch: () => setState(() => _isSearching = true),
        onCloseSearch: () {
          setState(() {
            _isSearching = false;
            _searchCtrl.clear();
            _query = '';
          });
        },
        isSearching: _isSearching,
        searchController: _searchCtrl,
        onSearchChanged: (v) =>
            setState(() => _query = v.trim().toLowerCase()),
        searchHint: isPesan ? s.searchHint : s.searchRoomHint,
        onMore: _openMoreMenu,
        notificationCount: ref.watch(roomNotifCountProvider),
        onNotifications: () => showRoomNotifSidebar(
          context,
          onOpenRoom: _openNotifRoom,
        ),
      ),
      // SWIPE kiri/kanan: Private → Grup → Global Room (dan balik) — sama
      // seperti Timeline. GestureDetector horizontal tidak mengganggu scroll
      // vertikal daftar.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) {
          final next = chatSwipeTarget(
            section: _section,
            tab: _tab,
            velocity: d.primaryVelocity ?? 0,
          );
          if (next == null) return;
          setState(() {
            _section = next.section;
            _tab = next.tab;
          });
        },
        child: IndexedStack(
          index: _section.index,
          children: [
            // SECTION PESAN = tab Pesan (private) + Grup.
            Column(
              children: [
                _pesanTabs(s),
                Expanded(
                  child: IndexedStack(
                    index: _tab.index,
                    children: [
                      PrivateChatsScreen(embedded: true, externalQuery: _query),
                      GroupScreen(externalQuery: _query),
                    ],
                  ),
                ),
              ],
            ),
            LobbyScreen(embedded: true, externalQuery: _query),
          ],
        ),
      ),
    );
  }

  /// Tab kecil "Pesan | Grup" di dalam section Pesan.
  Widget _pesanTabs(S s) {
    Widget tab(String label, ChatTab t) {
      final on = _tab == t;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _tab = t),
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on
                  ? AppTheme.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: AppText.bodyStrong.copyWith(
                color: on ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            tab(s.tabMessages, ChatTab.private),
            tab(s.tabGroups, ChatTab.groups),
          ],
        ),
      ),
    );
  }

  /// Unread per section: Pesan = total chat private belum dibaca (agregasi
  /// snapshot terakhir); Grup/Room = 0 (belum ada agregator khusus).
  Map<ChatSection, int> _unreadCounts() {
    final uid = ref.watch(authProvider.select((a) => a.uid));
    if (uid == null) return const {};
    final snap =
        ref.read(chatProvider.notifier).lastPrivateChatsSnapshot(uid) ??
        const <PrivateChatInfo>[];
    var unread = 0;
    for (final c in snap) {
      unread += (c.unreadCounts[uid] ?? 0);
    }
    return {ChatSection.messages: unread};
  }

  Future<void> _openMoreMenu() async {
    final s = ref.read(localeProvider).s;
    final box = _moreBtnKey.currentContext?.findRenderObject() as RenderBox?;
    final screenW = MediaQuery.sizeOf(context).width;
    // Menu MENEMPEL di bawah tombol titik-3, rata kanan dengan tombolnya.
    // Dulu posisi dihitung `offset.dx - 160` (menggeser 160px ke KIRI dari
    // pojok kiri-atas tombol) sehingga menu melayang jauh dari ikon.
    final RelativeRect pos;
    if (box != null) {
      final topLeft = box.localToGlobal(Offset.zero);
      final w = box.size.width;
      pos = RelativeRect.fromLTRB(
        // Lebar menu ±200: biarkan Flutter meng-clamp agar tidak keluar layar.
        (topLeft.dx + w - _kMoreMenuWidth).clamp(8.0, screenW),
        topLeft.dy + box.size.height + 4, // tepat di bawah ikon
        // Sisi kanan: sejajar tepi kanan tombol (rawat jarak ke tepi layar).
        screenW - (topLeft.dx + w) + 8,
        0,
      );
    } else {
      // Fallback (tombol belum ter-layout): kanan-atas seperti header.
      pos = RelativeRect.fromLTRB(screenW - _kMoreMenuWidth - 12, 60, 12, 0);
    }
    final sel = await showMenu<String>(
      context: context,
      position: pos,
      color: kChatMenuBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kChatMenuBorder),
      ),
      items: [
        PopupMenuItem(
          value: 'recent_calls',
          height: 46,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.call_rounded, size: 20, color: kChatMenuText),
            title: Text(s.menuRecentCalls,
                style: TextStyle(color: kChatMenuText, fontSize: AppTextSize.s15)),
          ),
        ),
        PopupMenuItem(
          value: 'new_group',
          height: 46,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.group_add_rounded, size: 20, color: kChatMenuText),
            title: Text(s.menuNewGroup,
                style: TextStyle(color: kChatMenuText, fontSize: AppTextSize.s15)),
          ),
        ),
        PopupMenuItem(
          value: 'read_all',
          height: 46,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.done_all_rounded, size: 20, color: kChatMenuText),
            title: Text(s.menuReadAll,
                style: TextStyle(color: kChatMenuText, fontSize: AppTextSize.s15)),
          ),
        ),
      ],
    );
    if (!mounted || sel == null) return;
    switch (sel) {
      case 'recent_calls':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CallHistoryScreen()),
        );
        break;
      case 'new_group':
        showCreateGroupDialog(context);
        break;
      case 'read_all':
        final uid = ProviderScope.containerOf(context, listen: false)
            .read(authProvider.notifier)
            .uid;
        if (uid == null || uid.isEmpty) return;
        ProviderScope.containerOf(context, listen: false)
            .read(chatProvider.notifier)
            .markAllChatsRead(uid);
        break;
    }
  }
}
