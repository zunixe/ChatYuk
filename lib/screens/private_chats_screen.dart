import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../services/chat_service.dart';
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

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 100) {
      _page++;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final s = context.watch<LocaleProvider>().s;
    final blocked = context.watch<ChatProvider>().blockedUids;
    if (auth.uid == null) return const SizedBox();

    return Scaffold(
      appBar: AppBar(title: Text(s.titlePrivateChat)),
      body: StreamBuilder<List<PrivateChatInfo>>(
        stream: _stream,
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final chats = snap.data ?? [];
          // Reset page jika data berubah total
          if (chats.length != _lastTotal) {
            _lastTotal = chats.length;
            _page = 1;
          }
          final visible = chats.where((c) {
            final otherUid = c.participants.firstWhere((p) => p != auth.uid, orElse: () => '');
            return !blocked.contains(otherUid);
          }).toList();
          final paged = visible.take(_page * _pageSize).toList();
          final hasMore = paged.length < visible.length;
          if (visible.isEmpty) {
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

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
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
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(otherName[0].toUpperCase(),
                              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(otherName, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                _chatSubtitle(chat, auth.uid!, s),
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_formatTime(chat.lastMessageAt, s), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                            if (unread > 0) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(10)),
                                child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ],
                        ),
                      ],
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
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return s.timeJustNow;
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}${s.isId ? "j" : "h"}';
    return '${diff.inDays}d';
  }
}
