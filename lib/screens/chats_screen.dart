import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Section berikutnya setelah geser horizontal (ala Timeline).
/// [velocity] negatif = geser ke KIRI → section berikutnya.
/// null = tidak berpindah (velocity terlalu kecil / sudah di ujung).
ChatSection? chatSectionAfterSwipe(
  ChatSection current,
  double velocity, {
  double minVelocity = 260,
}) {
  if (velocity.abs() < minVelocity) return null;
  final i = current.index + (velocity < 0 ? 1 : -1);
  if (i < 0 || i >= ChatSection.values.length) return null;
  return ChatSection.values[i];
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
    // Terima permintaan pindah section dari luar (mis. pintasan Global Room
    // di halaman Online) → tampilkan section Rooms tanpa perlu halaman kedua.
    requestedChatSection.addListener(_applyRequestedSection);
    // Bisa saja permintaan sudah di-set SEBELUM layar ini mount pertama kali.
    _applyRequestedSection();
  }

  void _applyRequestedSection() {
    final want = requestedChatSection.value;
    if (want == null) return;
    requestedChatSection.value = null; // sekali pakai
    if (!mounted) {
      // Layar belum ter-mount: simpan lagi agar dibaca di initState berikut.
      requestedChatSection.value = want;
      return;
    }
    _changeSection(want);
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
    requestedChatSection.removeListener(_applyRequestedSection);
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
      // SWIPE kiri/kanan pindah section (Pesan ⇄ Global Room).
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) {
          final next = chatSectionAfterSwipe(
            _section,
            d.primaryVelocity ?? 0,
          );
          if (next != null) _changeSection(next);
        },
        child: IndexedStack(
          index: _section.index,
          children: [
            PrivateChatsScreen(embedded: true, externalQuery: _query),
            LobbyScreen(embedded: true, externalQuery: _query),
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
