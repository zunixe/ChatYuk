import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/admin_provider.dart';
import '../providers/locale_provider.dart';
import '../utils.dart';
import 'admin_chat_view_screen.dart';
import '../providers/theme_provider.dart';

/// Admin: daftar semua percakapan user (monitoring).
class AdminChatListScreen extends StatefulWidget {
  const AdminChatListScreen({super.key});

  @override
  State<AdminChatListScreen> createState() => _AdminChatListScreenState();
}

class _AdminChatListScreenState extends State<AdminChatListScreen> {
  Timer? _refreshTimer;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<AdminProvider>().fetchChats());
    // Polling berkala → daftar chat selalu fresh tanpa loading flash.
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      context.read<AdminProvider>().refreshChats();
    });
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final admin = context.read<AdminProvider>();
    if (!_scrollCtrl.hasClients) return;
    // Load halaman berikutnya saat mendekati bawah list.
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 300) {
      admin.fetchMoreChats();
    }
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> chats) {
    // Sembunyikan chat kosong (belum ada percakapan) dari monitor.
    final nonEmpty = chats.where((chat) => ((chat['message_count'] ?? 0) as num) > 0).toList();
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return nonEmpty;
    return nonEmpty.where((chat) {
      final names = (chat['participant_names'] as Map<dynamic, dynamic>?) ?? {};
      final label = names.values.where((e) => e != null && '$e'.isNotEmpty).join(' ').toLowerCase();
      final lastMsg = (chat['last_message'] as String? ?? '').toLowerCase();
      return label.contains(q) || lastMsg.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final admin = context.watch<AdminProvider>();
    final s = context.watch<LocaleProvider>().s;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(s.adminChatMonitor,
                  style: AppText.titleEmphasis),
              ),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: AppTheme.primary),
                onPressed: () => admin.fetchChats(),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: s.adminSearchChat,
              prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 20),
              isDense: true,
              filled: true,
              fillColor: AppTheme.bgInput,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: admin.chatsLoading && admin.chats.isEmpty
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : admin.chatsError != null
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
                    SizedBox(height: 8),
                    Text(admin.chatsError!, style: TextStyle(color: AppTheme.danger)),
                    SizedBox(height: 8),
                    ElevatedButton(onPressed: () => admin.fetchChats(), child: Text(s.btnRetry)),
                  ]),
                )
              : _filtered(admin.chats).isEmpty
                  ? Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.chat_bubble_outline, size: 48, color: AppTheme.textSecondary),
                        SizedBox(height: 12),
                        Text(_query.isEmpty ? s.adminChatNoChats : s.searchNoResult,
                          style: TextStyle(color: AppTheme.textSecondary)),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: () => admin.fetchChats(),
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        itemCount: _filtered(admin.chats).length + (admin.chatsHasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          final filtered = _filtered(admin.chats);
                          if (i >= filtered.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                            );
                          }
                          final chat = filtered[i];
                          return _AdminChatCard(chat: chat, s: s, adminUids: admin.adminUids);
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

class _AdminChatCard extends StatelessWidget {
  final Map<String, dynamic> chat;
  final S s;
  final List<String> adminUids;
  const _AdminChatCard({required this.chat, required this.s, required this.adminUids});

  @override
  Widget build(BuildContext context) {
    final names = (chat['participant_names'] as Map<dynamic, dynamic>?) ?? {};
    final participants = (chat['participants'] as List<dynamic>?) ?? const [];
    final nameList = names.values.where((e) => e != null && '$e'.isNotEmpty).toList();
    final label = nameList.isNotEmpty
        ? nameList.join(' & ')
        : participants.length == 1
            ? '${participants.length} ${s.adminUserSingular}'
            : '${participants.length} ${s.adminUsersPlural}';
    // Urutan uid SAMA dengan urutan nama di judul (kiri → kanan).
    final orderUids = names.entries
        .where((e) => e.value != null && '${e.value}'.isNotEmpty)
        .map((e) => '${e.key}')
        .toList();
    for (final p in participants) {
      final u = '$p';
      if (!orderUids.contains(u)) orderUids.add(u);
    }
    final lastMsg = (chat['last_message'] as String? ?? '').trim();
    final count = chat['message_count'] ?? 0;
    final tsRaw = chat['last_message_at'];
    final ts = tsRaw != null ? DateTime.tryParse('$tsRaw') : null;

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AdminChatViewScreen(
              chatId: chat['chat_id'] as String? ?? '',
              chatLabel: label,
              participantOrder: orderUids,
            )),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.forum_outlined, color: AppTheme.primary, size: 22),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                        style: AppText.bodyStrong,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      SizedBox(height: 3),
                      Text(
                        lastMsg.isEmpty
                            ? (count > 0 ? '$count ${s.adminChatMsgs}' : '')
                            : lastMsg,
                        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (count > 0)
                      Text('$count', style: AppText.bodySmall.copyWith(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                    if (ts != null) ...[
                      SizedBox(height: 2),
                      Text(formatRelativeTime(ts, isId: s.isId),
                        style: AppText.micro.copyWith(color: AppTheme.textSecondary, fontWeight: FontWeight.w400)),
                    ],
                  ],
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _showDeleteDialog(context),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline, size: 20, color: AppTheme.danger),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final participants = (chat['participants'] as List<dynamic>?) ?? const [];
    final names = (chat['participant_names'] as Map<dynamic, dynamic>?) ?? {};
    final myUids = participants.map((e) => '$e').toList();
    if (myUids.length < 2) return;

    final selected = <String>{};
    // Secara default centang SEMUA user yang bukan admin.
    for (final uid in myUids) {
      if (!adminUids.contains(uid)) selected.add(uid);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final delMe = myUids[0];
          final delOther = myUids[1];
          final isAdminMe = adminUids.contains(delMe);
          final isAdminOther = adminUids.contains(delOther);
          final nameMe = '${names[delMe] ?? 'User'}' + (isAdminMe ? ' ${s.adminCannotDeleteAdmin}' : '');
          final nameOther = '${names[delOther] ?? 'User'}' + (isAdminOther ? ' ${s.adminCannotDeleteAdmin}' : '');

          return AlertDialog(
            backgroundColor: AppTheme.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(children: [
              Icon(Icons.delete_forever, color: AppTheme.danger, size: 22),
              SizedBox(width: 10),
              Expanded(child: Text(s.adminDeleteChatTitle, style: AppText.titleEmphasis)),
            ]),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.adminDeleteChatBody, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: selected.contains(delMe),
                    onChanged: isAdminMe ? null : (v) => setState(() {
                      v == true ? selected.add(delMe) : selected.remove(delMe);
                    }),
                    title: Text('${s.adminDeleteUser}: $nameMe',
                      style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    activeColor: AppTheme.danger,
                  ),
                  CheckboxListTile(
                    value: selected.contains(delOther),
                    onChanged: isAdminOther ? null : (v) => setState(() {
                      v == true ? selected.add(delOther) : selected.remove(delOther);
                    }),
                    title: Text('${s.adminDeleteUser}: $nameOther',
                      style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    activeColor: AppTheme.danger,
                  ),
                  SizedBox(height: 4),
                  Text(s.adminDeleteChatOnly, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel, style: TextStyle(color: AppTheme.textSecondary))),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
                child: Text(s.adminDeleteChat, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final admin = context.read<AdminProvider>();
    final ok = await admin.deleteChat(chat['chat_id'] as String? ?? '', selected.toList());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? s.adminChatDeleted : s.adminDeleteFail)),
    );
    admin.fetchChats();
  }
}
