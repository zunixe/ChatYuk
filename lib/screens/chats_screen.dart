import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../services/chat_service.dart';
import '../widgets/chat_yuk_chat_header.dart';
import '../widgets/anon_prompt_dialog.dart';
import 'group_screen.dart';
import 'private_chats_screen.dart';
import 'lobby_screen.dart';
import 'call_history_screen.dart';
import 'post_composer_screen.dart';
import '../config/theme.dart';

/// Menu "Chat" gabungan: section Pesan (private) + Grup + Room.
///
/// Header ringkas (ala Timeline) dengan menu pindah section; TabBar lama
/// dihapus. Isi daftar berganti memakai [IndexedStack] (state tiap section
/// tetap hidup — perilaku sama dengan TabBarView lama).
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
    final showSearch = _isSearching;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: ChatYukChatHeader(
        section: _section,
        onSectionChanged: _changeSection,
        unreadCounts: _unreadCounts(),
        onSearch: () => setState(() => _isSearching = !_isSearching),
        onMore: _openMoreMenu,
        onCompose: _openCompose,
      ),
      body: Column(
        children: [
          // Field cari tampil di bawah header saat mode cari (pola lama:
          // query dibawa pindah section, tidak di-reset).
          if (showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  style: AppText.body.copyWith(color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: isPesan ? s.searchHint : s.searchRoomHint,
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
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _section.index,
              children: [
                PrivateChatsScreen(embedded: true, externalQuery: _query),
                GroupScreen(externalQuery: _query),
                LobbyScreen(embedded: true, externalQuery: _query),
              ],
            ),
          ),
        ],
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

  void _openCompose() {
    final auth = ProviderScope.containerOf(context, listen: false).read(authProvider.notifier);
    if (!(auth.profile?.isRegistered ?? false)) {
      showAnonPromptDialog(context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PostComposerScreen()),
    );
  }

  Future<void> _openMoreMenu() async {
    final s = ref.read(localeProvider).s;
    final box = _moreBtnKey.currentContext?.findRenderObject() as RenderBox?;
    final offset = box != null
        ? box.localToGlobal(Offset.zero)
        : Offset(MediaQuery.sizeOf(context).width - 200, 60);
    final sel = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx - 160,
        offset.dy + 44,
        offset.dx + 60,
        0,
      ),
      color: kChatMenuBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kChatMenuBorder),
      ),
      items: [
        PopupMenuItem(
          value: 'recent_calls',
          height: 46,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.call_rounded, size: 20, color: kChatMenuText),
            title: Text(s.menuRecentCalls),
          ),
        ),
        PopupMenuItem(
          value: 'new_group',
          height: 46,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.group_add_rounded, size: 20, color: kChatMenuText),
            title: Text(s.menuNewGroup),
          ),
        ),
        PopupMenuItem(
          value: 'read_all',
          height: 46,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.done_all_rounded, size: 20, color: kChatMenuText),
            title: Text(s.menuReadAll),
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
