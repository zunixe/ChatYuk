import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/admin_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../utils.dart';

/// Admin: daftar pesan Hubungi Kami dari pengguna.
class AdminContactTab extends StatefulWidget {
  const AdminContactTab({super.key});

  @override
  State<AdminContactTab> createState() => _AdminContactTabState();
}

class _AdminContactTabState extends State<AdminContactTab> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<AdminProvider>().fetchContactMessages());
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final admin = context.read<AdminProvider>();
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 300) {
      admin.fetchMoreContactMessages();
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> msg) async {
    final s = context.read<LocaleProvider>().s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.btnDelete),
        content: Text(s.adminContactDeleteMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.btnDelete),
          ),
        ],
      ),
    );
    if (ok == true) {
      context.read<AdminProvider>().deleteContactMessage(msg['id'] as String);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final admin = context.watch<AdminProvider>();
    final s = context.watch<LocaleProvider>().s;

    final unread = admin.contactMessages
        .where((m) => m['is_read'] != true)
        .length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.adminContactTab,
                  style: AppText.bodyStrong.copyWith(color: AppTheme.primary),
                ),
              ),
              if (unread > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.danger,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$unread',
                    style: AppText.micro.copyWith(color: Colors.white),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    size: 20, color: AppTheme.primary),
                onPressed: () => admin.fetchContactMessages(),
              ),
            ],
          ),
        ),
        Expanded(
          child: admin.contactLoading && admin.contactMessages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : admin.contactError != null && admin.contactMessages.isEmpty
                  ? Center(
                      child: TextButton(
                        onPressed: () => admin.fetchContactMessages(),
                        child: Text('${admin.contactError}'),
                      ),
                    )
                  : admin.contactMessages.isEmpty
                      ? Center(
                          child: Text(
                            s.adminContactEmpty,
                            style: AppText.bodySmall
                                .copyWith(color: AppTheme.textSecondary),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: admin.fetchContactMessages,
                          child: ListView.separated(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(16),
                            itemCount: admin.contactMessages.length + 1,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              if (i == admin.contactMessages.length) {
                                return admin.contactHasMore
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Center(
                                            child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child:
                                              CircularProgressIndicator(strokeWidth: 2),
                                        )),
                                      )
                                    : const SizedBox(height: 12);
                              }
                              return _messageCard(context, admin.contactMessages[i]);
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _messageCard(BuildContext context, Map<String, dynamic> msg) {
    final s = context.read<LocaleProvider>().s;
    final read = msg['is_read'] == true;
    final name = (msg['name'] as String?)?.trim().isNotEmpty == true
        ? msg['name'] as String
        : null;
    final createdAt = msg['created_at'] != null
        ? DateTime.tryParse('${msg['created_at']}')
        : null;

    return Container(
      decoration: BoxDecoration(
        color: read ? AppTheme.bgCard : AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name ?? '—',
                          style: AppText.bodyStrong.copyWith(
                            color: read ? AppTheme.textSecondary : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!read) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.danger,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${s.labelNew}',
                            style: AppText.micro.copyWith(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (createdAt != null)
                        Text(
                          formatTime(createdAt),
                          style: AppText.micro
                              .copyWith(color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    msg['message'] as String? ?? '',
                    style: AppText.bodySmall,
                    textAlign: TextAlign.justify,
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  icon: Icon(
                    read ? Icons.mark_email_unread_outlined : Icons.done_all,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  tooltip: read ? s.labelNew : s.labelRead,
                  onPressed: () => context
                      .read<AdminProvider>()
                      .setContactRead(msg['id'] as String, read: !read),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppTheme.danger),
                  tooltip: s.btnDelete,
                  onPressed: () => _confirmDelete(msg),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}