import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/online_users_provider.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
import '../utils.dart';
import 'private_chat_screen.dart';

class PrivateChatsScreen extends StatefulWidget {
  const PrivateChatsScreen({super.key});

  @override
  State<PrivateChatsScreen> createState() => _PrivateChatsScreenState();
}

class _PrivateChatsScreenState extends State<PrivateChatsScreen> {
  Stream<List<PrivateChatInfo>>? _stream;
  int _page = 1;
  static const int _pageSize = 20;
  final ScrollController _scrollCtrl = ScrollController();
  int _lastTotal = 0;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    if (auth.uid != null) {
      _stream = context.read<ChatProvider>().getMyPrivateChats(auth.uid!);
    }
    _scrollCtrl.addListener(_onScroll);
  }

  Future<void> _deleteChat(String uid, String chatId) async {
    await context.read<ChatProvider>().hideChat(uid, chatId);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool _pageDebounce = false;

  void _onScroll() {
    if (_pageDebounce) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 100) {
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
    final auth = context.read<AuthProvider>();
    final s = context.watch<LocaleProvider>().s;
    final blocked = context.select<ChatProvider, List<String>>((c) => c.blockedUids);
    final onlineUsers = context.select<OnlineUsersProvider, List<UserModel>>((o) => o.users);
    if (auth.uid == null) return const SizedBox();

    // Map uid → status dari daftar online users
    final statusMap = <String, String>{};
    for (final u in onlineUsers) {
      statusMap[u.uid] = u.status;
    }

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(title: Text(s.titlePrivateChat)),
      body: StreamBuilder<List<PrivateChatInfo>>(
        stream: _stream,
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final chats = (snap.data ?? []).toList();
          // Reset page jika data berubah total
          if (chats.length != _lastTotal) {
            _lastTotal = chats.length;
            _page = 1;
          }
          if (chats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('💬', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text(s.noPrivateChats, style: const TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  Text(s.noPrivateChatsHint, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            );
          }
          // Tampilkan semua chat — yang diblokir tetap tampil dengan tanda khusus
          final paged = chats.take(_page * _pageSize).toList();
          final hasMore = paged.length < chats.length;
          return ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            itemCount: paged.length + (hasMore ? 1 : 0),
            itemBuilder: (_, i) {
              if (i >= paged.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
                  ),
                );
              }
              final chat = paged[i];
              final otherUid = chat.participants.firstWhere((p) => p != auth.uid, orElse: () => '');
              final otherName = chat.participantNames[otherUid] ?? 'Anon';
              final unread = chat.unreadCounts[auth.uid] ?? 0;
              final isBlocked = blocked.contains(otherUid);

              return Dismissible(
                key: ValueKey(chat.chatId),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.delete_outline, color: Colors.white, size: 24),
                      const SizedBox(height: 4),
                      Text(s.btnDelete, style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppTheme.bgCard,
                      title: Text(s.btnDeleteChat, style: const TextStyle(color: AppTheme.textPrimary)),
                      content: Text(s.deleteChatConfirm, style: const TextStyle(color: AppTheme.textSecondary)),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(context.read<LocaleProvider>().s.btnCancel)),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: Text(s.btnDeleteChat, style: const TextStyle(color: AppTheme.danger)),
                        ),
                      ],
                    ),
                  ) ?? false;
                },
                onDismissed: (_) async {
                  final messenger = ScaffoldMessenger.of(context);
                  await _deleteChat(auth.uid!, chat.chatId);
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(s.deleteChatSuccess)));
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isBlocked ? AppTheme.bgCard.withValues(alpha: 0.5) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PrivateChatScreen(
                            chatId: chat.chatId,
                            otherName: otherName,
                            otherUid: otherUid,
                            otherGender: chat.participantGenders[otherUid] ?? '',
                            otherCountry: chat.participantLocations[otherUid] ?? '',
                            otherAge: chat.participantAges[otherUid] ?? 0,
                            otherRegistered: chat.participantRegistered[otherUid] == true,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: isBlocked
                                      ? AppTheme.textSecondary.withValues(alpha: 0.15)
                                      : AppTheme.accent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(otherName.isNotEmpty ? otherName[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      color: isBlocked ? AppTheme.textSecondary : AppTheme.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    )),
                                ),
                              ),
                              if (isBlocked)
                                Positioned(
                                  right: -2, bottom: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.danger,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.block, size: 10, color: Colors.white),
                                  ),
                                )
                              else
                                Positioned(
                                  right: -1, bottom: -1,
                                  child: () {
                                    final status = statusMap[otherUid] ?? 'offline';
                                    final color = status == 'online'
                                        ? const Color(0xFF4CAF50)
                                        : status == 'idle'
                                            ? const Color(0xFFFFC107)
                                            : const Color(0xFF9E9E9E);
                                    return Container(
                                      width: 12, height: 12,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                    );
                                  }(),
                                ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(otherName,
                                              style: TextStyle(
                                                color: isBlocked ? AppTheme.textSecondary : AppTheme.textPrimary,
                                                fontWeight: FontWeight.w600,
                                              )),
                                          ),
                                          if (chat.participantRegistered[otherUid] == true) ...[
                                            const SizedBox(width: 3),
                                            const Icon(Icons.verified, size: 14, color: Color(0xFF4A90E2)),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (isBlocked)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.danger.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(s.msgBlocked.split(',').first,
                                          style: const TextStyle(color: AppTheme.danger, fontSize: 10, fontWeight: FontWeight.w600)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _chatSubtitle(chat, auth.uid!, s),
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${chat.messageCount} ${s.chatMsgCount}',
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                                ),                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        if (isBlocked)
                          GestureDetector(
                            onTap: () async {
                              await context.read<ChatProvider>().unblockUser(auth.uid!, otherUid);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(s.unblockSuccess)));
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.primary),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(s.btnUnblock,
                                style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_formatTime(chat.lastMessageAt, s),
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              if (unread > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('$unread',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ],
                          ),
                       ],
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
    );
  }

  String _chatSubtitle(PrivateChatInfo chat, String myUid, S s) {
    final otherUid = chat.participants.firstWhere((p) => p != myUid, orElse: () => '');
    final gender = chat.participantGenders[otherUid] ?? '';
    final age = chat.participantAges[otherUid] ?? 0;
    final loc = chat.participantLocations[otherUid] ?? '';
    final genderLabel = gender == 'male' ? s.genderMale : gender == 'female' ? s.genderFemale : '';
    final genderAgePart = genderLabel.isNotEmpty ? '$genderLabel${age > 0 ? ' $age' : ''}' : (age > 0 ? '$age' : '');
    final parts = [if (genderAgePart.isNotEmpty) genderAgePart, if (loc.isNotEmpty) loc];
    if (parts.isEmpty) return chat.lastMessage.isEmpty ? s.noMessages : chat.lastMessage;
    return parts.join(' · ');
  }

  String _formatTime(DateTime dt, S s) {
    return formatRelativeTime(dt, isId: s.isId);
  }
}
