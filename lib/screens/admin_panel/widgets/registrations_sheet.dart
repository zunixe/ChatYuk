import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;

import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../utils.dart';
import '../../../widgets/sheet_drag_handle.dart';
import '../../../providers/riverpod/admin_provider.dart';

class AdminRegistrationsSheet extends ConsumerStatefulWidget {
  const AdminRegistrationsSheet();
  @override
  ConsumerState<AdminRegistrationsSheet> createState() => AdminRegistrationsSheetState();
}

class AdminRegistrationsSheetState extends ConsumerState<AdminRegistrationsSheet> {
  // true = baru daftar dulu (default, sama seperti server); false = lama daftar.
  bool _newestFirst = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ProviderScope.containerOf(context, listen: false).read(adminProvider).fetchRegistrations(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    // GRANULAR: data registrasi bagian dari domain STATS.
    ref.watch(adminProvider.select((p) => p.revStats));
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    // Urutkan di klien (≤200 baris, instan) — server selalu newest-first.
    final list = [...admin.registrations];
    list.sort((a, b) {
      DateTime dt(Object? v) =>
          DateTime.tryParse('$v') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final cmp = dt(a['created_at']).compareTo(dt(b['created_at']));
      return _newestFirst ? -cmp : cmp;
    });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.adminRegListTitle,
                      style: AppText.title,
                    ),
                  ),
                  PopupMenuButton<bool>(
                    tooltip: _newestFirst
                        ? s.adminRegSortNewest
                        : s.adminRegSortOldest,
                    icon: const Icon(
                      Icons.sort_rounded,
                      size: 20,
                      color: AppTheme.primary,
                    ),
                    onSelected: (v) => setState(() => _newestFirst = v),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: true,
                        child: Text(s.adminRegSortNewest),
                      ),
                      PopupMenuItem(
                        value: false,
                        child: Text(s.adminRegSortOldest),
                      ),
                    ],
                  ),
                ],
              ),
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
                        // Tanggal + JAM register (WIB) — eksplisit supaya
                        // admin tahu waktu pastinya, bukan cuma "3 hari lalu".
                        final createdDt = r['created_at'] != null
                            ? DateTime.tryParse('${r['created_at']}')
                            : null;
                        final createdFull = formatDateTimeWib(createdDt);
                        final createdRel = createdDt != null
                            ? formatRelativeTime(createdDt, isId: s.isId)
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
                              const SizedBox(width: 8),
                              // Tanggal + jam register (WIB) + jarak relatif.
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    createdFull,
                                    style: AppText.micro.copyWith(
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  if (createdRel.isNotEmpty)
                                    Text(
                                      createdRel,
                                      style: AppText.micro.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                ],
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
