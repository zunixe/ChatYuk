import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/chat_service.dart';
import 'private_chat_screen.dart';

class PrivateChatsScreen extends StatelessWidget {
  const PrivateChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    if (auth.uid == null) return const SizedBox();

    return Scaffold(
      appBar: AppBar(title: const Text('Private Chat')),
      body: StreamBuilder<List<PrivateChatInfo>>(
        stream: context.read<ChatProvider>().getMyPrivateChats(auth.uid!),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final chats = snap.data ?? [];
          final blocked = context.read<ChatProvider>().blockedUids;
          final visible = chats.where((c) {
            final otherUid = c.participants.firstWhere((p) => p != auth.uid, orElse: () => '');
            return !blocked.contains(otherUid);
          }).toList();
          if (visible.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('💬', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 12),
                  Text('Belum ada private chat', style: TextStyle(color: AppTheme.textSecondary)),
                  SizedBox(height: 4),
                  Text('Klik user di chat room untuk mulai', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: visible.length,
            itemBuilder: (_, i) {
              final chat = visible[i];
              final otherUid = chat.participants.firstWhere((p) => p != auth.uid, orElse: () => '');
              final otherName = chat.participantNames[otherUid] ?? 'Anon';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PrivateChatScreen(chatId: chat.chatId, otherName: otherName, otherUid: otherUid),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(
                              otherName[0].toUpperCase(),
                              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(otherName, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                chat.lastMessage.isEmpty ? 'Belum ada pesan' : chat.lastMessage,
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Time
                        Text(_formatTime(chat.lastMessageAt), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Baru';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}j';
    return '${diff.inDays}h';
  }
}