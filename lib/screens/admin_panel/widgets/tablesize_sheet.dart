import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/strings.dart';
import '../../../config/theme.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../utils.dart';

/// Bottom sheet rincian ukuran tabel database (dibuka dari baris Database
/// di kartu Ringkasan). Fetch fresh tiap dibuka — RPC hanya baca katalog.
Future<void> showTableSizeSheet(BuildContext context) {
  final S s = context.read<LocaleProvider>().s;
  context.read<AdminProvider>().fetchTableSizes();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.adminTableSizesTitle, style: AppText.title),
              const SizedBox(height: 2),
              Text(
                s.adminTableSizesTapHint,
                style: AppText.caption.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _TableSizeBody(s: s)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TableSizeBody extends StatelessWidget {
  // WAJIB bertipe S (bukan dynamic): getter admin adalah extension
  // SAdminX — extension tidak jalan di receiver dynamic (NoSuchMethod
  // saat runtime → sheet abu-abu di release).
  final S s;
  const _TableSizeBody({required this.s});

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    if (admin.tableSizesLoading && admin.tableSizes.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final rows = admin.tableSizes;
    if (rows.isEmpty) {
      return Center(
        child: Text(
          s.adminTableSizesEmpty,
          style: AppText.bodySmall.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      );
    }
    final maxBytes = rows.fold<int>(
      1,
      (m, r) => (((r['total_bytes'] ?? 0) as num).toInt() > m)
          ? ((r['total_bytes'] ?? 0) as num).toInt()
          : m,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.adminTableColTable,
                  style: AppText.label.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  s.adminTableColSize,
                  textAlign: TextAlign.right,
                  style: AppText.label.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  s.adminTableColRows,
                  textAlign: TextAlign.right,
                  style: AppText.label.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, index) => const Divider(height: 12),
            itemBuilder: (_, i) {
              final r = rows[i];
              final schema = '${r['schema'] ?? ''}';
              final table = '${r['table'] ?? ''}';
              final total = ((r['total_bytes'] ?? 0) as num).toInt();
              final idx = ((r['index_bytes'] ?? 0) as num).toInt();
              final rowsEst = ((r['rows_est'] ?? -1) as num).toInt();
              final share = (total / maxBytes).clamp(0.0, 1.0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          schema.isEmpty ? table : '$schema.$table',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyStrong,
                        ),
                      ),
                      SizedBox(
                        width: 76,
                        child: Text(
                          formatBytes(total),
                          textAlign: TextAlign.right,
                          style: AppText.bodySmall,
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          rowsEst < 0 ? '–' : _compact(rowsEst, s.isId),
                          textAlign: TextAlign.right,
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 4,
                      backgroundColor:
                          AppTheme.divider.withValues(alpha: 0.4),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        i == 0 ? AppTheme.danger : AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'index ${formatBytes(idx)}',
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Angka baris ringkas: 6485 → 6,5 rb (id) / 6.5k (en).
String _compact(int v, bool isId) {
  if (v < 1000) return '$v';
  final k = v / 1000;
  final t = k >= 100 ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
  return isId ? '${t.replaceAll('.', ',')} rb' : '${t}k';
}
