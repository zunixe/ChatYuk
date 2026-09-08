import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/online_users_provider.dart';
import '../providers/social_provider.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
import '../utils.dart';
import '../widgets/profile_avatar.dart';
import 'private_chat_screen.dart';
import '../providers/call_provider.dart';
import '../providers/theme_provider.dart';

class PrivateChatsScreen extends StatefulWidget {
  final bool embedded;
  final String? externalQuery;
  const PrivateChatsScreen({super.key, this.embedded = false, this.externalQuery});

  @override
  State<PrivateChatsScreen> createState() => _PrivateChatsScreenState();
}

class _PrivateChatsScreenState extends State<PrivateChatsScreen> {
  Stream<List<PrivateChatInfo>>? _stream;
  List<PrivateChatInfo>? _initial;
  String? _boundUid;
  int _page = 1;
  static const int _pageSize = 20;
  final ScrollController _scrollCtrl = ScrollController();
  int _lastTotal = 0;
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;
  // Tampilan arsip (gaya WhatsApp): list hanya chat terarsip.
  bool _showArchived = false;
  int _archivedCount = 0;
  List<PrivateChatInfo> _lastFiltered = [];
  List<PrivateChatInfo> _lastChats = [];

  void _toggleSelect(String chatId) {
    setState(() {
      if (_selected.contains(chatId)) _selected.remove(chatId);
      else _selected.add(chatId);
    });
  }

  void _clearSelection() => setState(() => _selected.clear());

  /// Aksi massal gaya WhatsApp — pin, mute, arsip untuk semua terpilih.
  /// Tombol menampilkan AKSI (misal semua sudah pin → tawarkan unpin).
  Future<void> _pinSelected(String uid, bool pin) async {
    final s = context.read<LocaleProvider>().s;
    final chat = context.read<ChatProvider>();
    final ids = _selected.toList();
    _clearSelection();
    for (final id in ids) {
      try {
        await chat.pinChat(id, pin, myUid: uid);
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pin ? s.msgPinned : s.msgUnpinned)),
      );
    }
  }

  Future<void> _muteSelected(String uid, bool mute) async {
    final s = context.read<LocaleProvider>().s;
    final chat = context.read<ChatProvider>();
    final ids = _selected.toList();
    _clearSelection();
    for (final id in ids) {
      try {
        await chat.muteChat(id, mute, myUid: uid);
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mute ? s.msgMuted : s.msgUnmuted)),
      );
    }
  }

  Future<void> _archiveSelected(String uid, bool archive) async {
    final s = context.read<LocaleProvider>().s;
    final chat = context.read<ChatProvider>();
    final ids = _selected.toList();
    _clearSelection();
    for (final id in ids) {
      try {
        await chat.archiveChat(id, archive, myUid: uid);
      } catch (_) {}
    }
    // Habis unarchive → kembali ke list utama (tampilan arsip kini kosong).
    if (!archive && mounted) setState(() => _showArchived = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(archive ? s.msgArchived : s.msgUnarchived)),
      );
    }
  }

  Future<void> _confirmDeleteSelected(String uid) async {
    final s = context.read<LocaleProvider>().s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.btnDeleteSelected, style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(s.deleteSelectedConfirm(_selected.length), style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.btnDeleteSelected, style: const TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok == true) _deleteSelected(uid);
  }

  /// Ikon aksi bar seleksi gaya WhatsApp: pin, hapus, mute, arsip.
  /// Ikon = AKSI yang akan dijalankan (semua sudah pin → tawarkan unpin).
  List<Widget> _selectionActions(String uid, S s) {
    final byId = <String, PrivateChatInfo>{
      for (final c in _lastChats) c.chatId: c
    };
    var allPinned = _selected.isNotEmpty;
    var allMuted = _selected.isNotEmpty;
    for (final id in _selected) {
      final c = byId[id];
      if (c == null || !c.isPinnedFor(uid)) allPinned = false;
      if (c == null || !c.isMutedFor(uid)) allMuted = false;
    }
    return [
      IconButton(
        tooltip: allPinned ? s.btnUnpin : s.btnPin,
        icon: Icon(allPinned ? Icons.push_pin_outlined : Icons.push_pin),
        onPressed: () => _pinSelected(uid, !allPinned),
      ),
      IconButton(
        tooltip: s.btnDeleteChat,
        icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
        onPressed: () => _confirmDeleteSelected(uid),
      ),
      IconButton(
        tooltip: allMuted ? s.btnUnmute : s.btnMute,
        icon: Icon(allMuted
            ? Icons.notifications_active
            : Icons.notifications_off_outlined),
        onPressed: () => _muteSelected(uid, !allMuted),
      ),
      if (!_showArchived)
        IconButton(
          tooltip: s.btnArchive,
          icon: const Icon(Icons.archive_outlined),
          onPressed: () => _archiveSelected(uid, true),
        )
      else
        IconButton(
          tooltip: s.btnUnarchive,
          icon: const Icon(Icons.unarchive),
          onPressed: () => _archiveSelected(uid, false),
        ),
    ];
  }

  /// Bar seleksi dalam body (mode embedded — tab Chat tidak punya AppBar sendiri).
  Widget _selectionBar(String uid, S s) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppTheme.isDark ? 0.2 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: s.btnCancel,
            icon: const Icon(Icons.arrow_back),
            onPressed: _clearSelection,
          ),
          Text(
            s.selectedCount(_selected.length),
            style: AppText.bodyStrong,
          ),
          const Spacer(),
          ..._selectionActions(uid, s),
        ],
      ),
    );
  }

  /// Baris "Diarsipkan (n)" — ketuk untuk buka/tutup tampilan arsip.
  Widget _archivedToggle(S s) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() {
        _showArchived = !_showArchived;
        _selected.clear();
        _page = 1;
      }),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Icon(
              _showArchived ? Icons.unarchive : Icons.archive_outlined,
              size: 20,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: 10),
            Text(
              s.labelArchived(_archivedCount),
              style:
                  AppText.bodyStrong.copyWith(color: AppTheme.textPrimary),
            ),
            const Spacer(),
            Icon(
              _showArchived ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSelected(String uid) async {
    final ids = _selected.toList();
    _clearSelection();
    for (final id in ids) {
      await _deleteChat(uid, id);
    }
    // Kalau hapus dari tampilan arsip sampai habis → kembali ke utama.
    if (_showArchived && mounted) setState(() => _showArchived = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<LocaleProvider>().s.deleteSelectedSuccess(ids.length))),
      );
    }
  }

  Future<void> _deleteChat(String uid, String chatId) async {
    await context.read<ChatProvider>().hideChat(uid, chatId);
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // List chat hidup di IndexedStack → initState hanya sekali, padahal
    // swap akun (dummy ⇄ admin) mengganti auth.uid. Re-bind stream/snapshot
    // saat uid berubah supaya otherUid di-resolve ke akun yang benar.
    final uid = context.watch<AuthProvider>().uid;
    if (uid == _boundUid) return;
    _boundUid = uid;
    if (uid != null) {
      _initial = context.read<ChatProvider>().lastPrivateChatsSnapshot(uid);
      _stream = context.read<ChatProvider>().getMyPrivateChats(uid);
    } else {
      _initial = null;
      _stream = null;
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _pageDebounce = false;

  void _onScroll() {
    if (_pageDebounce) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 100) {
      _pageDebounce = true;
      _page++;
      setState(() {});
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _pageDebounce = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final auth = context.read<AuthProvider>();
    final s = context.watch<LocaleProvider>().s;
    final blocked = context.select<ChatProvider, List<String>>(
      (c) => c.blockedUids,
    );
    final onlineUsers = context.select<OnlineUsersProvider, List<UserModel>>(
      (o) => o.users,
    );
    if (auth.uid == null) return const SizedBox();

    final effectiveQuery = widget.externalQuery ?? _query;

    // Map uid → status & nama live dari daftar online users
    final statusMap = <String, String>{};
    final liveNameMap = <String, String>{};
    for (final u in onlineUsers) {
      statusMap[u.uid] = u.status;
      liveNameMap[u.uid] = u.nickname;
    }

    // ── Komputasi _lastFiltered di LEVEL BUILD (bukan di StreamBuilder) ──
    // agar sibling AnimatedContainer (tombol Hapus Semua) selalu melihat
    // data terbaru. StreamBuilder cuma simpan raw data ke _lastChats.
    if (_lastChats.isNotEmpty) {
      final filtered = effectiveQuery.isEmpty
          ? _lastChats
          : _lastChats.where((c) {
              final otherUid = c.participants.firstWhere(
                (p) => p != auth.uid,
                orElse: () => '',
              );
              final otherName =
                  liveNameMap[otherUid] ?? c.participantNames[otherUid] ?? '';
              return otherName.toLowerCase().contains(effectiveQuery);
            }).toList();
      // Urutkan: pinned paling atas, baru online, baru lastMessageAt
      filtered.sort((a, b) {
        final aPinned = a.isPinnedFor(auth.uid ?? '');
        final bPinned = b.isPinnedFor(auth.uid ?? '');
        if (aPinned && !bPinned) return -1;
        if (!aPinned && bPinned) return 1;
        if (aPinned && bPinned) {
          final aT = a.pinnedAtFor(auth.uid ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bT = b.pinnedAtFor(auth.uid ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
          final c = bT.compareTo(aT);
          if (c != 0) return c;
        }
        final aUid =
            a.participants.firstWhere((p) => p != auth.uid, orElse: () => '');
        final bUid =
            b.participants.firstWhere((p) => p != auth.uid, orElse: () => '');
        int rank(String v) => v == 'online' ? 0 : v == 'idle' ? 1 : 2;
        final ra = rank(statusMap[aUid] ?? 'offline');
        final rb = rank(statusMap[bUid] ?? 'offline');
        if (ra != rb) return ra.compareTo(rb);
        return b.lastMessageAt.compareTo(a.lastMessageAt);
      });
      _lastFiltered = filtered;
      final myUid = auth.uid ?? '';
      _archivedCount =
          _lastChats.where((c) => c.isArchivedFor(myUid)).length;
      // Pengaman: arsip kosong tapi masih di tampilan arsip (mis. habis
      // unarchive) → paksa kembali ke list utama agar halaman tak kosong.
      if (_showArchived && _archivedCount == 0) _showArchived = false;
      // Tampilan arsip: hanya chat terarsip. Normal: arsip disembunyikan.
      _lastFiltered = _showArchived
          ? filtered.where((c) => c.isArchivedFor(myUid)).toList()
          : filtered.where((c) => !c.isArchivedFor(myUid)).toList();
    }

    return PopScope(
      // Back sistem saat seleksi aktif = batal seleksi dulu.
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: widget.embedded
          ? null
          : _selectionMode
              ? AppBar(
                  leading: IconButton(
                    tooltip: s.btnCancel,
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _clearSelection,
                  ),
                  title: Text(s.selectedCount(_selected.length)),
                  actions: _selectionActions(auth.uid!, s),
                )
              : AppBar(title: Text(s.titlePrivateChat)),
      body: Column(
        children: [
          // Mode embedded (tab Chat): bar seleksi gaya WA di dalam body.
          if (_selectionMode && widget.embedded)
            _selectionBar(auth.uid!, s),
          if (_archivedCount > 0) _archivedToggle(s),
          Expanded(
            child: StreamBuilder<List<PrivateChatInfo>>(
              stream: _stream,
              initialData: _initial,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    snap.data == null) {
                  // Loader tema saat stream belum memberi data pertama.
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
                final chats = (snap.data ?? []).toList();
                // Simpan raw data ke field agar level build() bisa komputasi.
                if (_lastChats.length != chats.length ||
                    (chats.isNotEmpty && _lastChats != chats)) {
                  _lastChats = chats;
                  // Reset page jika data berubah total
                  if (chats.length != _lastTotal) {
                    _lastTotal = chats.length;
                    _page = 1;
                  }
                  // Trigger rebuild parent agar _lastFiltered (di level build())
                  // dihitung ulang — termasuk tombol "Hapus Semua".
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() {});
                  });
                }
                // _lastFiltered sudah dihitung di level build() —
                // gunakan di sini untuk rendering list.
                final filtered = _lastFiltered;
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('💬', style: TextStyle(fontSize: AppGlyph.xl)),
                        SizedBox(height: 12),
                        Text(
                          effectiveQuery.isEmpty ? s.noPrivateChats : s.searchNoResult,
                          style: AppText.bodyStrong.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          effectiveQuery.isEmpty ? s.noPrivateChatsHint : '',
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                // Tampilkan semua chat — yang diblokir tetap tampil dengan tanda khusus
                final paged = filtered.take(_page * _pageSize).toList();
                final hasMore = paged.length < filtered.length;
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    10,
                    16,
                    MediaQuery.of(context).padding.bottom + 16,
                  ),
                  itemCount: paged.length + (hasMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= paged.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                            color: AppTheme.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    }
                    final chat = paged[i];
                    final otherUid = chat.participants.firstWhere(
                      (p) => p != auth.uid,
                      orElse: () => '',
                    );
                    final otherName = liveNameMap[otherUid] ?? chat.participantNames[otherUid] ?? 'Anon';
                    final otherGender = chat.participantGenders[otherUid] ?? '';
                    final unread = chat.unreadCounts[auth.uid] ?? 0;
                    final isBlocked = blocked.contains(otherUid);

                    final isSelected = _selected.contains(chat.chatId);
                    final isPinned = chat.isPinnedFor(auth.uid ?? '');
                    return GestureDetector(
                      // Tahan = mulai seleksi (gaya WhatsApp), ketuk = tambah/kurangi.
                      onLongPress: () {
                        if (!_selectionMode) _toggleSelect(chat.chatId);
                      },
                      child: Dismissible(
                      key: ValueKey(chat.chatId),
                      direction: DismissDirection.horizontal,
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.only(left: 20),
                        margin: EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                              color: Colors.white,
                              size: 24,
                            ),
                            SizedBox(height: 4),
                            Text(
                              isPinned ? s.btnUnpin : s.btnPin,
                              style: AppText.caption.copyWith(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      secondaryBackground: Container(
                        alignment: Alignment.centerRight,
                        padding: EdgeInsets.only(right: 20),
                        margin: EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.danger,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_outline, color: Colors.white, size: 24),
                            SizedBox(height: 4),
                            Text(s.btnDelete, style: AppText.caption.copyWith(color: Colors.white)),
                          ],
                        ),
                      ),
                      confirmDismiss: (direction) async {
                        if (direction == DismissDirection.startToEnd) {
                          final myUid = auth.uid;
                          final ok = await context.read<ChatProvider>().pinChat(chat.chatId, !isPinned, myUid: myUid).then((_) => true).catchError((_) => false);
                          if (ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isPinned ? s.msgUnpinned : s.msgPinned)));
                          }
                          return false;
                        }
                        return await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppTheme.bgCard,
                                title: Text(s.btnDeleteChat, style: TextStyle(color: AppTheme.textPrimary)),
                                content: Text(s.deleteChatConfirm, style: TextStyle(color: AppTheme.textSecondary)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(context.read<LocaleProvider>().s.btnCancel)),
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(s.btnDeleteChat, style: const TextStyle(color: AppTheme.danger))),
                                ],
                              ),
                            ) ??
                            false;
                      },
                      onDismissed: (_) async {
                        final messenger = ScaffoldMessenger.of(context);
                        await _deleteChat(auth.uid!, chat.chatId);
                        if (mounted) {
                          messenger.showSnackBar(SnackBar(content: Text(s.deleteChatSuccess)));
                        }
                      },
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        margin: EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primary.withValues(alpha: AppTheme.isDark ? 0.15 : 0.06)
                              : isBlocked
                                  ? AppTheme.bgCard.withValues(alpha: 0.5)
                                  : AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: isSelected ? AppTheme.primary.withValues(alpha: 0.4) : Colors.transparent, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isSelected ? 0.08 : 0.05),
                              blurRadius: isSelected ? 12 : 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _selectionMode ? () => _toggleSelect(chat.chatId) : () => Navigator.push(
                              context,
                              PageRouteBuilder(
                                transitionDuration: const Duration(
                                  milliseconds: 320,
                                ),
                                reverseTransitionDuration: const Duration(
                                  milliseconds: 260,
                                ),
                                settings: RouteSettings(
                                  name: privateChatRoute(chat.chatId),
                                ),
                                pageBuilder: (_, __, ___) => PrivateChatScreen(
                                  chatId: chat.chatId,
                                  otherName: otherName,
                                  otherUid: otherUid,
                                  otherGender:
                                      chat.participantGenders[otherUid] ?? '',
                                  otherCountry:
                                      chat.participantLocations[otherUid] ?? '',
                                  otherAge: chat.participantAges[otherUid] ?? 0,
                                  otherRegistered:
                                      chat.participantRegistered[otherUid] ==
                                      true,
                                ),
                                transitionsBuilder: (_, animation, __, child) {
                                  final curved = CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                    reverseCurve: Curves.easeInCubic,
                                  );
                                  return SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(1, 0),
                                      end: Offset.zero,
                                    ).animate(curved),
                                    child: child,
                                  );
                                },
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                   ProfileAvatar(
                                    uid: otherUid,
                                    name: otherName,
                                    size: 44,
                                    borderRadius: 0,
                                    borderColor: isBlocked
                                        ? null
                                        : (otherGender == 'male'
                                            ? AppTheme.male
                                            : otherGender == 'female'
                                                ? AppTheme.female
                                                : AppTheme.accent),
                                    bgColor: isBlocked
                                        ? AppTheme.textSecondary.withValues(
                                            alpha: 0.15,
                                          )
                                        : AppTheme.accent.withValues(
                                            alpha: 0.15,
                                          ),
                                    textColor: isBlocked
                                        ? AppTheme.textSecondary
                                        : AppTheme.textPrimary,
                                    badge: isBlocked
                                        ? Container(
                                            padding: EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.danger,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Icon(
                                              Icons.block,
                                              size: 10,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Container(
                                            width: 11,
                                            height: 11,
                                            decoration: BoxDecoration(
                                              color:
                                                  (statusMap[otherUid] ??
                                                          'offline') ==
                                                      'online'
                                                  ? Color(0xFF4CAF50)
                                                  : (statusMap[otherUid] ??
                                                            'offline') ==
                                                        'idle'
                                                  ? Color(0xFFFFC107)
                                                  : Color(0xFF9E9E9E),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      otherName,
                                                      style: AppText.bodyStrong
                                                          .copyWith(
                                                            color: isBlocked
                                                                ? AppTheme
                                                                      .textSecondary
                                                                : AppTheme
                                                                      .textPrimary,
                                                          ),
                                                    ),
                                                  ),
                                                  if (isPinned) ...[
                                                    SizedBox(width: 3),
                                                    Icon(Icons.push_pin, size: 14, color: AppTheme.primary),
                                                  ],
                                                  if (chat.participantRegistered[otherUid] ==
                                                      true) ...[
                                                    SizedBox(width: 3),
                                                    Icon(
                                                      Icons.verified,
                                                      size: 14,
                                                      color: Color(0xFF4A90E2),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (isBlocked)
                                              Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.danger
                                                      .withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  s.msgBlocked.split(',').first,
                                                  style: AppText.micro.copyWith(
                                                    color: AppTheme.danger,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        SizedBox(height: 4),
                                        Builder(builder: (_) {
                                          final otherStatus = statusMap[otherUid] ?? 'offline';
                                          final isOnline = otherStatus == 'online';
                                          return Text(
                                            isOnline ? s.chatOnlineSubtitle : _chatSubtitle(chat, auth.uid!, s),
                                            style: AppText.bodySmall.copyWith(color: isOnline ? const Color(0xFF4CAF50) : AppTheme.textSecondary, fontWeight: isOnline ? FontWeight.w600 : FontWeight.w400),
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                          );
                                        }),
                                        SizedBox(height: 4),
                                        Text(
                                          '${chat.messageCount} ${s.chatMsgCount}',
                                          style: AppText.caption.copyWith(
                                            color: AppTheme.textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isBlocked)
                                    GestureDetector(
                                      onTap: () async {
                                        await context
                                            .read<ChatProvider>()
                                            .unblockUser(auth.uid!, otherUid);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(s.unblockSuccess),
                                            ),
                                          );
                                        }
                                      },
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: AppTheme.primary,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          s.btnUnblock,
                                          style: AppText.caption.copyWith(
                                            color: AppTheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _formatTime(chat.lastMessageAt, s),
                                          style: AppText.bodySmall.copyWith(
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                        // Tanda bisu gaya WA di samping jam.
                                        if (chat.isMutedFor(auth.uid ?? '')) ...[
                                          const SizedBox(height: 4),
                                          Icon(
                                            Icons.notifications_off,
                                            size: 14,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ],
                                        if (unread > 0) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primary,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '$unread',
                                              style: AppText.caption.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (otherUid.isNotEmpty &&
                                            chat.participantRegistered[otherUid] ==
                                                true) ...[
                                          const SizedBox(height: 6),
                                          _FriendButton(otherUid: otherUid),
                                        ],
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          ],
        ),
      ),
    );
  }

  String _chatSubtitle(PrivateChatInfo chat, String myUid, S s) {
    final otherUid = chat.participants.firstWhere(
      (p) => p != myUid,
      orElse: () => '',
    );
    final gender = chat.participantGenders[otherUid] ?? '';
    final age = chat.participantAges[otherUid] ?? 0;
    final loc = chat.participantLocations[otherUid] ?? '';
    final genderLabel = gender == 'male'
        ? s.genderMale
        : gender == 'female'
        ? s.genderFemale
        : '';
    final genderAgePart = genderLabel.isNotEmpty
        ? '$genderLabel${age > 0 ? ' $age' : ''}'
        : (age > 0 ? '$age' : '');
    final parts = [
      if (genderAgePart.isNotEmpty) genderAgePart,
      if (loc.isNotEmpty) loc,
    ];
    if (parts.isEmpty)
      return chat.lastMessage.isEmpty ? s.noMessages : chat.lastMessage;
    return parts.join(' · ');
  }

  String _formatTime(DateTime dt, S s) {
    return formatRelativeTime(dt, isId: s.isId);
  }
}

/// Tombol add friend di list pesan untuk user yang terdaftar (registered).
/// Status dibaca dari SocialProvider (set global, ter-load saat app start +
/// cache disk) — TANPA RPC per-item (dulu: my_social_status per tombol =
/// N+1 RPC, spinner berjejak saat jaringan lambat).
class _FriendButton extends StatefulWidget {
  final String otherUid;
  const _FriendButton({required this.otherUid});

  @override
  State<_FriendButton> createState() => _FriendButtonState();
}

class _FriendButtonState extends State<_FriendButton> {
  bool _busy = false;

  Future<void> _send() async {
    final s = context.read<LocaleProvider>().s;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final res = await context.read<SocialProvider>().sendFriendRequest(
      widget.otherUid,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != 'rejected') {
      messenger.showSnackBar(SnackBar(content: Text(s.friendRequestSent)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final social = context.watch<SocialProvider>();
    final isFriend = social.isFriend(widget.otherUid);
    final pending = social.isPendingFriendRequest(widget.otherUid);
    final done = isFriend || pending;
    final label = isFriend
        ? s.btnFriends
        : (pending ? s.btnFriendRequested : s.btnAddFriend);
    return GestureDetector(
      onTap: done || _busy ? null : _send,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: done
                ? AppTheme.textSecondary.withValues(alpha: 0.4)
                : AppTheme.primary,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: _busy
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppTheme.primary,
                ),
              )
            : Text(
                label,
                style: AppText.caption.copyWith(
                  color: done ? AppTheme.textSecondary : AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
