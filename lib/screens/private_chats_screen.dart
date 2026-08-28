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
import '../services/social_service.dart';
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
  List<PrivateChatInfo> _lastFiltered = [];
  List<PrivateChatInfo> _lastChats = [];

  void _toggleSelect(String chatId) {
    setState(() {
      if (_selected.contains(chatId)) _selected.remove(chatId);
      else _selected.add(chatId);
    });
  }

  void _selectAll(List<PrivateChatInfo> chats) {
    setState(() => _selected.addAll(chats.map((c) => c.chatId)));
  }

  void _clearSelection() => setState(() => _selected.clear());

  Future<void> _deleteSelected(String uid) async {
    final ids = _selected.toList();
    _clearSelection();
    for (final id in ids) {
      await _deleteChat(uid, id);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<LocaleProvider>().s.deleteSelectedSuccess(ids.length))),
      );
    }
  }

  Future<void> _deleteAll(String uid, List<PrivateChatInfo> chats) async {
    final s = context.read<LocaleProvider>().s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.btnDeleteAll, style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(s.deleteAllConfirm, style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.btnDeleteAll, style: const TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok != true) return;
    _clearSelection();
    for (final c in chats) {
      await _deleteChat(uid, c.chatId);
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.deleteAllSuccess)));
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

  Future<void> _deleteChat(String uid, String chatId) async {
    await context.read<ChatProvider>().hideChat(uid, chatId);
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
      // Urutkan: online teratas
      filtered.sort((a, b) {
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
    }

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: widget.embedded ? null : AppBar(title: Text(_selectionMode ? s.selectedCount(_selected.length) : s.titlePrivateChat)),
      body: Column(
        children: [
          AnimatedContainer(
            duration: Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.fromLTRB(16, 2, 16, 4),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _selectionMode ? AppTheme.primary.withValues(alpha: AppTheme.isDark ? 0.18 : 0.08) : AppTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _selectionMode ? AppTheme.primary.withValues(alpha: 0.25) : AppTheme.divider, width: 1),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: AppTheme.isDark ? 0.2 : 0.06), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Row(
                children: [
                  if (_selectionMode) ...[
                    TextButton.icon(icon: Icon(_selected.length == _lastFiltered.length ? Icons.deselect : Icons.select_all, size: 18), label: Text(_selected.length == _lastFiltered.length ? s.btnDeselectAll : s.btnSelectAll, style: AppText.caption), onPressed: () {
                      if (_selected.length == _lastFiltered.length) _clearSelection(); else _selectAll(_lastFiltered);
                    }),
                    SizedBox(width: 8),
                    TextButton.icon(icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.danger), label: Text(s.btnDeleteSelected, style: AppText.caption.copyWith(color: AppTheme.danger)), onPressed: _selected.isEmpty ? null : () async {
                      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(backgroundColor: AppTheme.bgCard, title: Text(s.btnDeleteSelected, style: TextStyle(color: AppTheme.textPrimary)), content: Text(s.deleteSelectedConfirm(_selected.length), style: TextStyle(color: AppTheme.textSecondary)), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.btnDeleteSelected, style: const TextStyle(color: AppTheme.danger)))]));
                      if (ok == true) _deleteSelected(auth.uid!);
                    }),
                    Spacer(),
                    TextButton(onPressed: _clearSelection, child: Text(s.btnCancel, style: AppText.caption)),
                  ] else ...[
                    if (_lastFiltered.isNotEmpty)
                      TextButton.icon(icon: Icon(Icons.delete_sweep, size: 18, color: AppTheme.danger), label: Text(s.btnDeleteAll, style: AppText.caption.copyWith(color: AppTheme.danger)), onPressed: () => _deleteAll(auth.uid!, _lastFiltered)),
                    Spacer(),
                    TextButton.icon(icon: Icon(Icons.checklist, size: 18), label: Text(s.btnSelectAll, style: AppText.caption), onPressed: () => _selectAll(_lastFiltered)),
                  ],
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<PrivateChatInfo>>(
              stream: _stream,
              initialData: _initial,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    snap.data == null) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
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
                    4,
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
                    final unread = chat.unreadCounts[auth.uid] ?? 0;
                    final isBlocked = blocked.contains(otherUid);

                    final isSelected = _selected.contains(chat.chatId);
                    return GestureDetector(
                      onLongPress: () => _toggleSelect(chat.chatId),
                      child: Dismissible(
                      key: ValueKey(chat.chatId),
                      direction: DismissDirection.endToStart,
                      background: Container(
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
                            Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                              size: 24,
                            ),
                            SizedBox(height: 4),
                            Text(
                              s.btnDelete,
                              style: AppText.caption.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppTheme.bgCard,
                                title: Text(
                                  s.btnDeleteChat,
                                  style: TextStyle(color: AppTheme.textPrimary),
                                ),
                                content: Text(
                                  s.deleteChatConfirm,
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: Text(
                                      context
                                          .read<LocaleProvider>()
                                          .s
                                          .btnCancel,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: Text(
                                      s.btnDeleteChat,
                                      style: const TextStyle(
                                        color: AppTheme.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                      },
                      onDismissed: (_) async {
                        final messenger = ScaffoldMessenger.of(context);
                        await _deleteChat(auth.uid!, chat.chatId);
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(content: Text(s.deleteChatSuccess)),
                          );
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
                                  if (_selectionMode) ...[
                                    Checkbox(value: isSelected, onChanged: (_) => _toggleSelect(chat.chatId), activeColor: AppTheme.primary),
                                    SizedBox(width: 4),
                                  ],
                                  ProfileAvatar(
                                    uid: otherUid,
                                    name: otherName,
                                    size: 44,
                                    borderRadius: 12,
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
                                            width: 12,
                                            height: 12,
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
                                                width: 2,
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
                                        SizedBox(height: 2),
                                        Builder(builder: (_) {
                                          final otherStatus = statusMap[otherUid] ?? 'offline';
                                          final isOnline = otherStatus == 'online';
                                          return Text(
                                            isOnline ? s.chatOnlineSubtitle : _chatSubtitle(chat, auth.uid!, s),
                                            style: AppText.bodySmall.copyWith(color: isOnline ? const Color(0xFF4CAF50) : AppTheme.textSecondary, fontWeight: isOnline ? FontWeight.w600 : FontWeight.w400),
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                          );
                                        }),
                                        SizedBox(height: 2),
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
/// Status: friends / request pending (sent|received) / add friend.
class _FriendButton extends StatefulWidget {
  final String otherUid;
  const _FriendButton({required this.otherUid});

  @override
  State<_FriendButton> createState() => _FriendButtonState();
}

class _FriendButtonState extends State<_FriendButton> {
  final SocialService _service = SocialService();
  bool _pendingRequest = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st = await _service.mySocialStatus(widget.otherUid);
      if (!mounted) return;
      setState(() {
        _pendingRequest =
            st['friend_request_sent'] == true ||
            st['friend_request_received'] == true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final s = context.read<LocaleProvider>().s;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final res = await context.read<SocialProvider>().sendFriendRequest(
      widget.otherUid,
    );
    if (!mounted) return;
    setState(() {
      if (res == 'pending' || res == 'friends') _pendingRequest = true;
      _busy = false;
    });
    messenger.showSnackBar(SnackBar(content: Text(s.friendRequestSent)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final isFriend = context.watch<SocialProvider>().isFriend(widget.otherUid);
    if (_loading) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: AppTheme.textSecondary,
        ),
      );
    }
    final done = isFriend || _pendingRequest;
    final label = isFriend
        ? s.btnFriends
        : (_pendingRequest ? s.btnFriendRequested : s.btnAddFriend);
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
        child: Text(
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
