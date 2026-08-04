import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/online_users_provider.dart';
import '../services/chat_service.dart';
import 'private_chat_screen.dart';

class OnlineUsersScreen extends StatefulWidget {
  const OnlineUsersScreen({super.key});

  @override
  State<OnlineUsersScreen> createState() => _OnlineUsersScreenState();
}

class _OnlineUsersScreenState extends State<OnlineUsersScreen> with AutomaticKeepAliveClientMixin {
  String _negara = 'all';
  String _gender = 'all';

  @override
  bool get wantKeepAlive => true;

  Future<void> _startChat(BuildContext context, UserModel user) async {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final s = context.read<LocaleProvider>().s;
    final myUid = auth.uid;
    final myName = auth.profile?.nickname ?? 'Anon';
    if (myUid == null || user.uid == myUid) return;
    try {
      final chatId = await chat.startPrivateChat(
        myUid: myUid,
        otherUid: user.uid,
        myName: myName,
        otherName: user.nickname,
        myGender: auth.profile?.gender ?? '',
        otherGender: user.gender,
        myCountry: auth.profile?.country ?? '',
        otherCountry: user.country,
        myAge: auth.profile?.age ?? 0,
        otherAge: user.age,
      );
      if (!context.mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => PrivateChatScreen(chatId: chatId, otherName: user.nickname, otherUid: user.uid, otherGender: user.gender, otherCountry: user.country, otherAge: user.age)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.errGeneric}$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final auth = context.read<AuthProvider>();
    final s = context.watch<LocaleProvider>().s;
    final isId = s.isId;

    return Scaffold(
      appBar: AppBar(title: Text(s.titleOnline)),
      body: Consumer<OnlineUsersProvider>(
        builder: (_, provider, __) {
          final chat = context.read<ChatProvider>();
          final allUsers = provider.users.where((u) => u.uid != auth.uid && !chat.isBlocked(u.uid)).toList();

          final users = allUsers.where((u) {
            if (_negara != 'all' && u.country != _negara) return false;
            if (_gender != 'all' && u.gender != _gender) return false;
            return true;
          }).toList();

          return StreamBuilder<List<PrivateChatInfo>>(
            stream: auth.uid != null ? chat.getMyPrivateChats(auth.uid!) : const Stream.empty(),
            builder: (_, chatSnap) {
              final chats = chatSnap.data ?? [];
              final unreadMap = <String, int>{};
              for (final c in chats) {
                final otherUid = c.participants.firstWhere((p) => p != auth.uid, orElse: () => '');
                if (otherUid.isNotEmpty) {
                  final count = c.unreadCounts[auth.uid] ?? 0;
                  if (count > 0) unreadMap[otherUid] = count;
                }
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _FilterDropdown(
                            value: _negara,
                            label: s.labelCountry,
                            icon: Icons.public,
                            items: ['all', ...kotaByNegara.keys],
                            labels: [s.filterAll, ...kotaByNegara.keys.map((k) => negaraLabel(k, isId))],
                            onChanged: (v) => setState(() => _negara = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _FilterDropdown(
                            value: _gender,
                            label: 'Gender',
                            icon: Icons.person_outline,
                            items: const ['all', 'male', 'female'],
                            labels: [s.filterAll, s.filterMale, s.filterFemale],
                            onChanged: (v) => setState(() => _gender = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: users.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('🟢', style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text(s.noOnlineUsers, style: const TextStyle(color: AppTheme.textSecondary)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                            itemCount: users.length,
                            itemBuilder: (_, i) => _UserCard(
                              user: users[i],
                              onTap: () => _startChat(context, users[i]),
                              unreadCount: unreadMap[users[i].uid] ?? 0,
                            ),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final List<String> items;
  final List<String> labels;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(isDense: true, prefixIcon: Icon(icon, size: 20, color: AppTheme.textSecondary), labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            for (int i = 0; i < items.length; i++)
              DropdownMenuItem(value: items[i], child: Text(labels[i], overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  final int unreadCount;
  const _UserCard({required this.user, required this.onTap, this.unreadCount = 0});

  Color _statusColor(String status) {
    if (status == 'idle') return AppTheme.idle;
    if (status == 'offline') return AppTheme.offline;
    return AppTheme.online;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final color = user.gender == 'male' ? AppTheme.male : user.gender == 'female' ? AppTheme.female : AppTheme.accent;
    final genderLabel = user.gender == 'male' ? s.genderMale : user.gender == 'female' ? s.genderFemale : s.genderOther;
    final statusLabel = user.status == 'idle' ? s.statusIdle : user.status == 'offline' ? s.statusOffline : s.statusOnline;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.15),
                      border: Border.all(color: color, width: 1.5),
                      image: user.avatar.isNotEmpty ? DecorationImage(image: MemoryImage(base64Decode(user.avatar)), fit: BoxFit.cover) : null,
                    ),
                    child: user.avatar.isNotEmpty ? null : Center(child: Text(user.initial, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700))),
                  ),
                  Positioned(right: 0, bottom: 0,
                    child: Container(width: 11, height: 11,
                      decoration: BoxDecoration(color: _statusColor(user.status), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(right: -2, top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
                        child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.nickname, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                        Text('$genderLabel ${user.age} · ${user.city}, ${user.country}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  Text(statusLabel, style: TextStyle(color: _statusColor(user.status), fontSize: 10, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.chat_bubble_outline, color: AppTheme.primary, size: 17),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
