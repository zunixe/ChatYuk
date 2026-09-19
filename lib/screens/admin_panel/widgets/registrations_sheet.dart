import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../utils.dart';

class AdminRegistrationsSheet extends StatefulWidget {
  const AdminRegistrationsSheet();
  @override
  State<AdminRegistrationsSheet> createState() => AdminRegistrationsSheetState();
}

class AdminRegistrationsSheetState extends State<AdminRegistrationsSheet> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => context.read<AdminProvider>().fetchRegistrations(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final admin = context.watch<AdminProvider>();
    final list = admin.registrations;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(s.adminRegListTitle, style: AppText.title),
            ),
            Expanded(
              child: admin.registrationsLoading && list.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : list.isEmpty
                  ? Center(
                      child: Text(
                        s.adminNoUsers,
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        MediaQuery.of(context).padding.bottom + 24,
                      ),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final r = list[i];
                        final nick = r['nickname'] ?? '?';
                        final email = r['email'] ?? '-';
                        final created = r['created_at'] != null
                            ? formatRelativeTime(
                                DateTime.tryParse(r['created_at']) ??
                                    DateTime.now(),
                                isId: s.isId,
                              )
                            : '';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$nick'.isNotEmpty
                                        ? '$nick'[0].toUpperCase()
                                        : '?',
                                    style: AppText.bodyStrong.copyWith(
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(nick, style: AppText.bodyStrong),
                                    Text(
                                      email,
                                      style: AppText.caption.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                created,
                                style: AppText.micro.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Card penggunaan data Supabase: pie chart DB vs gambar + kuota +
/// pertumbuhan per hari/minggu/bulan.
