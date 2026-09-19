import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../utils.dart';

class AdminStorageUsageCard extends StatefulWidget {
  const AdminStorageUsageCard();
  @override
  State<AdminStorageUsageCard> createState() => AdminStorageUsageCardState();
}

class AdminStorageUsageCardState extends State<AdminStorageUsageCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final a = context.read<AdminProvider>();
      a.fetchStorageStats();
      a.fetchCfUsage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final admin = context.watch<AdminProvider>();
    final st = admin.storageStats;
    final loading = admin.storageStatsLoading && st == null;

    final dbBytes = ((st?['db_bytes'] ?? 0) as num).toInt();
    final storBytes = ((st?['storage_bytes'] ?? 0) as num).toInt();
    final files = ((st?['storage_files'] ?? 0) as num).toInt();
    final total = ((st?['total_bytes'] ?? 0) as num).toInt();
    final quotaDb = ((st?['quota_db_bytes'] ?? 1) as num).toInt();
    final quotaStor = ((st?['quota_storage_bytes'] ?? 1) as num).toInt();

    final growth = (st?['growth'] as Map<String, dynamic>?) ?? const {};

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.donut_small_rounded,
                        size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(s.adminStorageTitle, style: AppText.bodyStrong),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // Pie chart DB vs Storage.
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CustomPaint(
                        painter: AdminUsagePiePainter(dbBytes, storBytes),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Builder(builder: (_) {
                      final dbPct = quotaDb > 0 ? dbBytes / quotaDb : 0.0;
                      final storPct =
                          quotaStor > 0 ? storBytes / quotaStor : 0.0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _legendRow(AppTheme.primary, s.adminStorageDb,
                              formatBytes(dbBytes)),
                          _legendRow(AppTheme.accent, s.adminStorageImages,
                              formatBytes(storBytes)),
                          const Divider(height: 18),
                          _kv(s.adminStorageTotal, formatBytes(total)),
                          _kv('${s.adminStorageDb} (${s.adminQuotaLabel})',
                              '${formatBytes(dbBytes)} / ${formatBytes(quotaDb)}'),
                          _progress(dbPct.clamp(0.0, 1.0), AppTheme.primary),
                          _kv('${s.adminStorageImages} (${s.adminQuotaLabel})',
                              '${formatBytes(storBytes)} / ${formatBytes(quotaStor)}'),
                          _progress(storPct.clamp(0.0, 1.0), AppTheme.accent),
                          _kv(s.adminStorageFiles, '$files'),
                        ],
                      );
                    })),
                  ],
                ),
                const SizedBox(height: 16),
                Text(s.adminStorageGrowth, style: AppText.bodyStrong),
                const SizedBox(height: 6),
                _growthTable(s, growth),
                const SizedBox(height: 16),
                Text(s.adminCfTitle, style: AppText.bodyStrong),
                const SizedBox(height: 8),
                _cfSection(admin, s),
              ],
            ),
    );
  }

Widget _cfSection(AdminProvider admin, S s) {
    final cf = admin.cfUsage;
    if (cf == null) {
      return Text(
        '...',
        style: AppText.caption.copyWith(color: AppTheme.textSecondary),
      );
    }
    if (cf['configured'] != true) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.bgInput.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          s.adminCfNotConfigured,
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
        ),
      );
    }
    if (cf['error'] != null) {
      return Text(
        '${cf['error']}',
        style: AppText.caption.copyWith(color: AppTheme.danger),
      );
    }
    final monthBytes = ((cf['month_bytes'] ?? 0) as num).toInt();
    final weekBytes = ((cf['week_bytes'] ?? 0) as num).toInt();
    final dayBytes = ((cf['day_bytes'] ?? 0) as num).toInt();
    final quota = ((cf['quota_bytes'] ?? 1) as num).toInt();
    final pct = quota > 0 ? (monthBytes / quota).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${s.adminCfMonth}: ${formatBytes(monthBytes)}',
                style: AppText.bodySmall,
              ),
            ),
            Text(
              '${s.adminQuotaLabel}: ${formatBytes(quota)}',
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct <= 0 ? null : pct,
              minHeight: 5,
              backgroundColor: AppTheme.divider.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation<Color>(
                pct > 0.85 ? AppTheme.danger : AppTheme.primary,
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '${s.adminGrowthDay}: ${formatBytes(dayBytes)}',
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                '${s.adminGrowthWeek}: ${formatBytes(weekBytes)}',
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                '${(pct * 100).toStringAsFixed(1)}%',
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _legendRow(Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label, style: AppText.bodySmall),
          ),
          Text(value, style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
          ),
          Text(v, style: AppText.bodySmall),
        ],
      ),
    );
  }

  Widget _progress(double pct, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct <= 0 ? null : pct,
          minHeight: 5,
          backgroundColor: AppTheme.divider.withValues(alpha: 0.4),
          valueColor: AlwaysStoppedAnimation<Color>(
            pct > 0.85 ? AppTheme.danger : color,
          ),
        ),
      ),
    );
  }

  Widget _growthTable(S s, Map<String, dynamic> growth) {
    final rows = [
      (
        s.adminGrowthDay,
        growth['day'] ?? const {},
      ),
      (s.adminGrowthWeek, growth['week'] ?? const {}),
      (s.adminGrowthMonth, growth['month'] ?? const {}),
    ];
    Widget cellHeader(String t, {bool count = false}) => Expanded(
          child: Align(
            alignment: count ? Alignment.centerRight : Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                t,
                maxLines: 1,
                style: AppText.micro.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
    String fmtCell(Map m, String key, {bool count = false}) {
      final v = (m[key] ?? 0) as num;
      return count ? '$v' : (v <= 0 ? '-' : formatBytes(v));
    }
    Widget cellValue(String t, {bool strong = false}) => Expanded(
          child: Text(
            t,
            maxLines: 1,
            style: strong
                ? AppText.caption.copyWith(fontWeight: FontWeight.w700)
                : AppText.micro.copyWith(color: AppTheme.textSecondary),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bgInput.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(children: [
            const SizedBox(width: 70),
            cellHeader(s.adminGrowthMessages),
            cellHeader(s.adminGrowthSignals),
            cellHeader(s.adminGrowthImages),
            cellHeader(s.adminGrowthRegistrations, count: true),
          ]),
          const SizedBox(height: 6),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 58,
                    child: Text(r.$1, style: AppText.caption),
                  ),
                  cellValue(fmtCell(r.$2 as Map, 'messages')),
                  cellValue(fmtCell(r.$2 as Map, 'signals')),
                  cellValue(fmtCell(r.$2 as Map, 'storage')),
                  cellValue(
                    fmtCell(r.$2 as Map, 'registrations', count: true),
                    strong: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Pie chart sederhana DB vs Storage (CustomPaint, tanpa dependency).
class AdminUsagePiePainter extends CustomPainter {
  final int dbBytes;
  final int storBytes;
  AdminUsagePiePainter(this.dbBytes, this.storBytes);

  @override
  void paint(Canvas canvas, Size size) {
    final total = dbBytes + storBytes;
    final paint = Paint()..style = PaintingStyle.fill;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Ring luar (track).
    paint.color = AppTheme.divider.withValues(alpha: 0.35);
    canvas.drawArc(rect.deflate(2), -pi / 2, pi * 2, true, paint);

    if (total > 0) {
      final dbFrac = dbBytes / total;
      paint.color = AppTheme.primary;
      canvas.drawArc(rect.deflate(8), -pi / 2, pi * 2 * dbFrac, true, paint);
      paint.color = AppTheme.accent;
      canvas.drawArc(rect.deflate(8), -pi / 2 + pi * 2 * dbFrac,
          pi * 2 * (1 - dbFrac), true, paint);
    }
  }

  @override
  bool shouldRepaint(AdminUsagePiePainter oldDelegate) =>
      oldDelegate.dbBytes != dbBytes || oldDelegate.storBytes != storBytes;
}
