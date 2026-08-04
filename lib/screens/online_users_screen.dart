import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/online_users_provider.dart';
import 'private_chat_screen.dart';

class OnlineUsersScreen extends StatefulWidget {
  const OnlineUsersScreen({super.key});

  @override
  State<OnlineUsersScreen> createState() => _OnlineUsersScreenState();
}

class _OnlineUsersScreenState extends State<OnlineUsersScreen> {
  String _negara = 'Semua';
  String _gender = 'Semua';

  Future<void> _startChat(BuildContext context, UserModel user) async {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final myUid = auth.uid;
    final myName = auth.profile?.nickname ?? 'Anon';
    if (myUid == null || user.uid == myUid) return;

    try {
      final chatId = await chat.startPrivateChat(
        myUid: myUid,
        otherUid: user.uid,
        myName: myName,
        otherName: user.nickname,
      );
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PrivateChatScreen(
            chatId: chatId,
            otherName: user.nickname,
            otherUid: user.uid,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e')),
        );
      }
    }
  }

  List<String> _negaraList() {
    return ['Semua', ...kotaByNegara.keys];
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('User Online')),
      body: Consumer<OnlineUsersProvider>(
        builder: (_, provider, _) {
          final chat = context.read<ChatProvider>();
          final allUsers = provider.users
              .where((u) => u.uid != auth.uid && !chat.isBlocked(u.uid))
              .toList();

          final negaras = _negaraList();
          if (!negaras.contains(_negara)) {
            _negara = 'Semua';
          }

          final users = allUsers.where((u) {
            if (_negara != 'Semua' && u.country != _negara) return false;
            if (_gender != 'Semua' && u.gender != _gender) return false;
            return true;
          }).toList();

          return Column(
            children: [
              // ── Filters ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _FilterDropdown(
                        value: _negara,
                        label: 'Negara',
                        icon: Icons.public,
                        items: negaras,
                        onChanged: (v) => setState(() => _negara = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FilterDropdown(
                        value: _gender,
                        label: 'Gender',
                        icon: Icons.person_outline,
                        items: const ['Semua', '👨 Laki-laki', '👩 Perempuan'],
                        values: const ['Semua', 'male', 'female'],
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                    ),
                  ],
                ),
              ),
              // ── List ──
              Expanded(
                child: users.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('🟢', style: TextStyle(fontSize: 48)),
                            SizedBox(height: 12),
                            Text('Tidak ada user cocok', style: TextStyle(color: AppTheme.textSecondary)),
                            SizedBox(height: 4),
                            Text('Coba ubah filter atau cek lagi nanti', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        itemCount: users.length,
                        itemBuilder: (_, i) => _UserCard(
                          user: users[i],
                          onTap: () => _startChat(context, users[i]),
                        ),
                      ),
              ),
            ],
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
  final List<String>? values;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: Icon(icon, size: 20, color: AppTheme.textSecondary),
        labelText: label,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            for (int i = 0; i < items.length; i++)
              DropdownMenuItem(
                value: values != null ? values![i] : items[i],
                child: Text(items[i], overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  const _UserCard({required this.user, required this.onTap});

  Color _statusColor(String status) {
    switch (status) {
      case 'idle':
        return AppTheme.idle;
      case 'offline':
        return AppTheme.offline;
      default:
        return AppTheme.online;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'idle':
        return 'Idle';
      case 'offline':
        return 'Offline';
      default:
        return 'Online';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = user.gender == 'male'
        ? AppTheme.male
        : user.gender == 'female'
            ? AppTheme.female
            : AppTheme.accent;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              // Avatar
              Stack(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.15),
                      border: Border.all(color: color, width: 1.5),
                      image: user.avatar.isNotEmpty
                          ? DecorationImage(
                              image: MemoryImage(base64Decode(user.avatar)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: user.avatar.isNotEmpty
                        ? null
                        : Center(
                            child: Text(
                              user.initial,
                              style: TextStyle(
                                color: color,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: _statusColor(user.status),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.nickname,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${user.gender == 'male' ? '👨 Laki-laki' : user.gender == 'female' ? '👩 Perempuan' : '🧑 Lainnya'} · ${user.city}, ${user.country}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // Status + chat icon
              Column(
                children: [
                  Text(
                    _statusLabel(user.status),
                    style: TextStyle(
                      color: _statusColor(user.status),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      color: AppTheme.primary,
                      size: 17,
                    ),
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
