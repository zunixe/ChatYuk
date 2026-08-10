import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../config/regions.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/points_provider.dart';
import '../providers/online_users_provider.dart';
import '../services/chat_service.dart';
import 'private_chat_screen.dart';

Uint8List? _decodeBase64(String b64) {
  try { return base64Decode(b64); } catch (_) { return null; }
}

class _BoundedCache<T> {
  final int maxSize;
  final _map = <String, T>{};
  final _order = <String>[];
  _BoundedCache(this.maxSize);
  T? get(String key) {
    final i = _order.indexOf(key);
    if (i >= 0) { _order.removeAt(i); _order.add(key); }
    return _map[key];
  }
  T putIfAbsent(String key, T ifAbsent()) {
    final existing = _map[key];
    if (existing != null) return existing;
    if (_order.length >= maxSize) { _map.remove(_order.removeAt(0)); }
    final val = ifAbsent();
    _map[key] = val;
    _order.add(key);
    return val;
  }
  void clear() { _map.clear(); _order.clear(); }
}

final _avatarCache = _BoundedCache<Uint8List>(80);

void clearAllAvatarCaches() {
  _avatarCache.clear();
}

class OnlineUsersScreen extends StatefulWidget {
  const OnlineUsersScreen({super.key});

  @override
  State<OnlineUsersScreen> createState() => _OnlineUsersScreenState();
}

class _OnlineUsersScreenState extends State<OnlineUsersScreen> with AutomaticKeepAliveClientMixin {
  String _negara = 'all';
  String _gender = 'all';
  String _search = '';
  int _page = 1;
  static const int _pageSize = 20;
  static const _prefKeyNegara = 'filter_negara';
  static const _prefKeyGender = 'filter_gender';
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadFilter();
  }

  Future<void> _loadFilter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _negara = prefs.getString(_prefKeyNegara) ?? 'all';
      _gender = prefs.getString(_prefKeyGender) ?? 'all';
    });
  }

  Future<void> _saveFilter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyNegara, _negara);
    await prefs.setString(_prefKeyGender, _gender);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _scrollDebounce = false;

  void _onScroll() {
    if (_scrollDebounce) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 100) {
      _scrollDebounce = true;
      _page++;
      setState(() {});
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _scrollDebounce = false;
      });
    }
  }

  Future<void> _startChat(BuildContext context, UserModel user) async {
    final auth = context.read<AuthProvider>();
    final chat = context.read<ChatProvider>();
    final s = context.read<LocaleProvider>().s;
    final myUid = auth.uid;
    final myName = auth.profile?.nickname ?? 'Anon';
    if (myUid == null || user.uid == myUid) return;
    try {
      // User bisa saja sudah dihapus saat list masih tampil → cek dulu.
      final active = await chat.isUserActive(user.uid);
      if (!context.mounted) return;
      if (!active) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.errUserNotFound)),
        );
        return;
      }
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
      context.read<PointsProvider>().oneTimeBonus('new_chat_${user.uid}', 5);
      Navigator.push(context, MaterialPageRoute(builder: (_) => PrivateChatScreen(chatId: chatId, otherName: user.nickname, otherUid: user.uid, otherGender: user.gender, otherCountry: user.country, otherAge: user.age, otherRegistered: user.isRegistered)));
    } catch (e) {
      final msg = e.toString().toLowerCase();
      // TOCTOU: user dihapus antara isUserActive check dan startPrivateChat
      if (msg.contains('23503') || msg.contains('foreign key') || msg.contains('42501')) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errUserNotFound)));
        }
        return;
      }
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
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.primaryDark, AppTheme.primary, AppTheme.accent],
            ),
          ),
        ),
        title: Consumer<OnlineUsersProvider>(
          builder: (_, prov, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.titleOnline, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              Text('${prov.users.length} ${s.isId ? "pengguna aktif" : "active users"}',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Consumer<OnlineUsersProvider>(
        builder: (_, provider, __) {
          final chat = context.read<ChatProvider>();
          final allUsers = provider.users.where((u) => u.uid != auth.uid && !chat.isBlocked(u.uid)).toList();

          final users = allUsers.where((u) {
            if (_negara != 'all' && u.country != _negara) return false;
            if (_gender != 'all' && u.gender != _gender) return false;
            if (_search.isNotEmpty &&
                !u.nickname.toLowerCase().contains(_search.toLowerCase())) {
              return false;
            }
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

              final paged = users.take(_page * _pageSize).toList();
              final hasMore = paged.length < users.length;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() { _search = v; _page = 1; }),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: s.searchHint,
                        prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18, color: AppTheme.textSecondary),
                                onPressed: () { _searchCtrl.clear(); setState(() { _search = ''; _page = 1; }); },
                              )
                            : null,
                        filled: true,
                        fillColor: AppTheme.bgCard,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _FilterDropdown(
                            value: _negara,
                            label: s.labelCountry,
                            icon: Icons.public,
                            items: ['all', ...allCountries],
                            labels: [s.filterAll, ...allCountries],
                            onChanged: (v) {
                              setState(() { _negara = v; _page = 1; });
                              _saveFilter();
                            },
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
                            onChanged: (v) {
                              setState(() { _gender = v; _page = 1; });
                              _saveFilter();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: !provider.hasLoaded
                        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
                        : users.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('🟢', style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text(_search.isNotEmpty ? s.searchNoResult : s.noOnlineUsers, style: const TextStyle(color: AppTheme.textSecondary)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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
                              return _UserCard(
                                user: paged[i],
                                onTap: () => _startChat(context, paged[i]),
                                unreadCount: unreadMap[paged[i].uid] ?? 0,
                              );
                            },
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
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: Icon(icon, size: 20, color: AppTheme.textSecondary),
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          menuMaxHeight: 400,
          items: [
            for (int i = 0; i < items.length; i++)
              DropdownMenuItem(
                value: items[i],
                child: Text(
                  labels[i],
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      image: user.avatar.isNotEmpty
                          ? DecorationImage(
                              image: MemoryImage(_avatarCache.putIfAbsent(user.avatar, () => base64Decode(user.avatar))),
                              fit: BoxFit.cover,
                            )
                          : null,
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(user.nickname, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                        ),
                        if (user.isRegistered) ...[
                          const SizedBox(width: 4),
                          const Tooltip(
                            message: 'Verified',
                            child: Icon(Icons.verified, size: 15, color: Color(0xFF4A90E2)),
                          ),
                        ],
                      ],
                    ),
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
      ),
    );
  }
}
