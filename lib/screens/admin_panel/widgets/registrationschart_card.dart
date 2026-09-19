import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'registrations_sheet.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';

class AdminRegistrationsChartCard extends StatefulWidget {
  const AdminRegistrationsChartCard();
  @override
  State<AdminRegistrationsChartCard> createState() =>
      AdminRegistrationsChartCardState();
}

class AdminRegistrationsChartCardState extends State<AdminRegistrationsChartCard> {
  static const _barW = 18.0;
  static const _chartH = 110.0;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _fetch();
  }

  void _fetch() {
    context.read<AdminProvider>().fetchRegistrationsDaily(
      _month.year,
      _month.month,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final admin = context.watch<AdminProvider>();
    final data = admin.regDaily;
    final now = DateTime.now();
    final months = [
      for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i),
    ];
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final maxCount = data.isEmpty
        ? 1
        : data.values.reduce((a, b) => a > b ? a : b);
    final total = data.values.fold<int>(0, (a, b) => a + b);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showRegistrationsSheet(context),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bar_chart_rounded,
                size: 16,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Text(s.adminRegTitle, style: AppText.bodyStrong),
              const Spacer(),
              DropdownButton<DateTime>(
                value: _month,
                isDense: true,
                underline: const SizedBox.shrink(),
                iconSize: 18,
                style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
                items: [
                  for (final m in months)
                    DropdownMenuItem(
                      value: m,
                      child: Text('${s.monthShort[m.month - 1]} ${m.year}'),
                    ),
                ],
                onChanged: (m) {
                  if (m == null) return;
                  setState(() => _month = m);
                  _fetch();
                },
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${s.adminRegPerDay} · ${s.adminRegTotal}: $total',
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          if (admin.regLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (data.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  s.adminRegEmpty,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var d = 1; d <= days; d++)
                    _bar(d, data[d] ?? 0, maxCount, s),
                ],
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _bar(int day, int count, int maxCount, S s) {
    final h = count == 0
        ? 2.0
        : (count / maxCount * _chartH).clamp(3.0, _chartH);
    final showLabel = day == 1 || day % 5 == 0 || day == 31;
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            count > 0 ? '$count' : '',
            style: AppText.micro.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 2),
          Container(
            width: _barW,
            height: h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  AppTheme.primary.withValues(alpha: 0.45),
                  AppTheme.primary,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 12,
            child: showLabel
                ? Text(
                    '$day',
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  /// Bottom sheet daftar user yang registrasi (email + tanggal).
  Future<void> _showRegistrationsSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.bgScreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => const AdminRegistrationsSheet(),
    );
  }
}

/// Avatar lazy per-baris di list Users admin (Ringkasan): fetch avatar
/// hanya saat baris tampil (sheet memakai ListView.builder) + cache
/// RAM/disk via AvatarB64Service. Tap → zoom besar. Tanpa foto → inisial.
