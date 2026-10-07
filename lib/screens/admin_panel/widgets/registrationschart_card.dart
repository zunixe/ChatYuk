import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'registrations_sheet.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../providers/riverpod/admin_provider.dart';

/// Kartu "Registrasi Email" untuk Ringkasan admin — dirapikan supaya
/// informatif untuk CEO: KPI (total, baru bulan ini, konversi anon,
/// rata-rata/hari, aktif hari ini), tren 12 bulan, bar harian bulan
/// terpilih, dan pie sumber akuisisi.
///
/// Data:
///   - `admin_registration_kpis()`  → KPI
///   - `admin_registrations_monthly(12)` → tren bulanan
///   - `admin_registrations_daily(y,m)` → bar harian
///   - `admin_attribution_summary(0)`  → sumber (dipakai sheet)
class AdminRegistrationsChartCard extends ConsumerStatefulWidget {
  const AdminRegistrationsChartCard();
  @override
  ConsumerState<AdminRegistrationsChartCard> createState() =>
      AdminRegistrationsChartCardState();
}

class AdminRegistrationsChartCardState extends ConsumerState<AdminRegistrationsChartCard> {
  static const _barW = 16.0;
  static const _chartH = 96.0;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _fetch();
  }

  void _fetch() {
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    admin.fetchRegistrationsDaily(_month.year, _month.month);
    admin.fetchRegistrationInsights();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    // GRANULAR: data registrasi bagian dari domain STATS.
    ref.watch(adminProvider.select((p) => p.revStats));
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(s, admin),
          const SizedBox(height: 12),
          _kpiGrid(s, admin),
          const SizedBox(height: 16),
          _genderBreakdown(s, admin),
          const SizedBox(height: 16),
          _monthlyTrend(s, admin),
          const SizedBox(height: 16),
          _dailySection(s, admin),
        ],
      ),
    );
  }

  // ── Gender breakdown (bar horizontal bertumpuk + legend) ──
  Widget _genderBreakdown(S s, AdminProvider admin) {
    final k = admin.regKpis;
    if (k.isEmpty) return const SizedBox.shrink();
    final male = _i(k['male_total']);
    final female = _i(k['female_total']);
    final other = _i(k['other_gender_total']);
    final total = male + female + other;
    if (total <= 0) return const SizedBox.shrink();

    final rows = <_GenderRow>[
      _GenderRow(s.adminRegGenderMale, male, AppTheme.male),
      _GenderRow(s.adminRegGenderFemale, female, AppTheme.female),
      if (other > 0) _GenderRow(s.adminRegGenderOther, other, AppTheme.idle),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.people_alt_rounded,
                size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(s.adminRegGenderTitle,
                style: AppText.caption.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w800,
                )),
            const Spacer(),
            Text('$total', style: AppText.bodyStrong),
          ],
        ),
        const SizedBox(height: 10),
        // Bar bertumpuk proporsional.
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                for (final r in rows)
                  if (r.value > 0)
                    Expanded(
                      flex: r.value,
                      child: ColoredBox(color: r.color),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (final r in rows) ...[
          _genderLegend(r, total),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _genderLegend(_GenderRow r, int total) {
    final pct = total > 0 ? (r.value * 100 / total) : 0.0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: r.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(r.label, style: AppText.bodySmall)),
        Text('${r.value}', style: AppText.bodyStrong),
        const SizedBox(width: 6),
        SizedBox(
          width: 44,
          child: Text('${pct.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary)),
        ),
      ],
    );
  }

  // ── Header ──
  Widget _header(S s, AdminProvider admin) {
    return Row(
      children: [
        const Icon(Icons.insights_rounded, size: 16, color: AppTheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(s.adminRegTitle, style: AppText.bodyStrong)),
        TextButton(
          onPressed: () => _showRegistrationsSheet(context),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(s.adminRegListTitleShort,
              style: AppText.caption.copyWith(color: AppTheme.primary)),
        ),
      ],
    );
  }

  // ── KPI grid (2 kolom) ──
  Widget _kpiGrid(S s, AdminProvider admin) {
    final k = admin.regKpis;
    if (admin.regInsightLoading && k.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (k.isEmpty) {
      return Text(
        s.adminRegInsightError,
        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
      );
    }
    final regTotal = _i(k['registered_total']);
    final anonTotal = _i(k['anon_total']);
    final conv = _d(k['conversion_pct']);
    final newMonth = _i(k['new_this_month']);
    final newToday = _i(k['new_today']);
    final avgDay = _d(k['avg_per_day']);
    final activeToday = _i(k['active_today']);
    final bestDay = _i(k['best_day']);
    final bestCount = _i(k['best_day_count']);
    final momPct = k['mom_pct'] == null ? null : _d(k['mom_pct']);

    final tiles = <Widget>[
      _kpi(
        icon: Icons.how_to_reg_rounded,
        label: s.adminRegKpiTotal,
        value: '$regTotal',
        sub: '$anonTotal ${s.adminRegKpiAnonSuffix}',
        color: AppTheme.primary,
      ),
      _kpi(
        icon: Icons.trending_up_rounded,
        label: s.adminRegKpiNewMonth,
        value: '$newMonth',
        // MoM hanya bermakna kalau bulan lalu >= 10 (hindari +22900%).
        sub: (momPct != null && _i(k['new_prev_month']) >= 10)
            ? '${momPct >= 0 ? '+' : ''}${momPct.toStringAsFixed(0)}% ${s.adminRegVsPrevMonth}'
            : null,
        subColor: (momPct ?? 0) >= 0 ? AppTheme.online : AppTheme.danger,
        color: AppTheme.accent,
      ),
      _kpi(
        icon: Icons.percent_rounded,
        label: s.adminRegKpiConversion,
        value: '${conv.toStringAsFixed(0)}%',
        sub: '$regTotal / ${regTotal + anonTotal}',
        color: AppTheme.female,
      ),
      _kpi(
        icon: Icons.today_rounded,
        label: s.adminRegKpiToday,
        value: '$newToday',
        sub: '${s.adminRegKpiAvgDayShort}: ${avgDay.toStringAsFixed(1)}',
        color: AppTheme.primaryDark,
      ),
      _kpi(
        icon: Icons.bolt_rounded,
        label: s.adminRegKpiActiveToday,
        value: '$activeToday',
        color: AppTheme.online,
      ),
      _kpi(
        icon: Icons.emoji_events_rounded,
        label: s.adminRegKpiBestDay,
        value: bestDay > 0 ? '${bestDay}' : '-',
        sub: bestDay > 0 ? '$bestCount ${s.adminRegUsersSuffix}' : null,
        color: AppTheme.idle,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 8.0;
        final w = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles) SizedBox(width: w, height: _kpiH, child: t),
          ],
        );
      },
    );
  }

  /// Tinggi kartu KPI DIPAKU supaya semua kartu merata (6 kartu grid 2 kolom).
  /// Dihitung dari token: padding(10*2) + baris label(caption) + jarak + nilai
  /// (titleEmphasis) + jarak + baris sub(micro) + sedikit buffer (line-box
  /// Flutter bisa sedikit lebih tinggi dari fontSize*height).
  static final double _kpiH =
      20 + // padding vertikal atas+bawah
      AppText.caption.fontSize! * 1.35 + // baris label
      6 +
      AppText.titleEmphasis.fontSize! * 1.25 + // nilai
      2 +
      AppText.micro.fontSize! * 1.2 + // baris sub
      6; // buffer aman (anti overflow RenderFlex)

  Widget _kpi({
    required IconData icon,
    required String label,
    required String value,
    String? sub,
    Color? subColor,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: AppText.titleEmphasis.copyWith(color: color)),
          // Slot sub SELALU direservasi (walau kosong) supaya semua kartu
          // sama tinggi — kalau sub null, `Text('')` tetap memakan satu baris.
          const SizedBox(height: 2),
          SizedBox(
            height: AppText.micro.fontSize! * 1.2,
            child: Text(
              sub ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.micro.copyWith(
                color: subColor ?? AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tren 12 bulan ──
  Widget _monthlyTrend(S s, AdminProvider admin) {
    final list = admin.regMonthly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.show_chart_rounded,
                size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(s.adminRegTrendTitle,
                style: AppText.caption.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w800,
                )),
          ],
        ),
        const SizedBox(height: 10),
        if (admin.regInsightLoading && list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(s.adminRegTrendLoading,
                  style: AppText.bodySmall
                      .copyWith(color: AppTheme.textSecondary)),
            ),
          )
        else if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(s.adminRegEmpty,
                  style: AppText.bodySmall
                      .copyWith(color: AppTheme.textSecondary)),
            ),
          )
        else
          _MonthlyTrendBars(list: list, s: s),
      ],
    );
  }

  /// Opsi dropdown bulan: 12 bulan terakhir, **TERBARU di atas**
  /// (descending). Diurutkan eksplisit supaya tidak bergantung pada perilaku
  /// normalisasi `DateTime`.
  List<DateTime> _monthOptions() {
    final now = DateTime.now();
    final list = [
      for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i),
    ];
    list.sort((a, b) => b.compareTo(a)); // terbaru → terlama
    return list;
  }

  // ── Bar harian (bulan terpilih) ──
  Widget _dailySection(S s, AdminProvider admin) {
    final data = admin.regDaily;
    final months = _monthOptions();
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final maxCount =
        data.isEmpty ? 1 : data.values.reduce((a, b) => a > b ? a : b);
    final total = data.values.fold<int>(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bar_chart_rounded,
                size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(s.adminRegDailyTitle,
                style: AppText.caption.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w800,
                )),
            const Spacer(),
            Text('${s.adminRegTotal}: $total',
                style:
                    AppText.micro.copyWith(color: AppTheme.textSecondary)),
            const SizedBox(width: 8),
            DropdownButton<DateTime>(
              value: _month,
              isDense: true,
              underline: const SizedBox.shrink(),
              iconSize: 16,
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
                admin.fetchRegistrationsDaily(m.year, m.month);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (admin.regLoading && data.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 26),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          )
        else if (data.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Center(
              child: Text(s.adminRegEmpty,
                  style: AppText.bodySmall
                      .copyWith(color: AppTheme.textSecondary)),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var d = 1; d <= days; d++)
                  _bar(d, data[d] ?? 0, maxCount),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bar(int day, int count, int maxCount) {
    final h = count == 0
        ? 2.0
        : (count / maxCount * _chartH).clamp(3.0, _chartH);
    final isBest = count > 0 && count == maxCount;
    final showLabel = day == 1 || day % 5 == 0 || day == 31;
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            count > 0 ? '$count' : '',
            style: AppText.micro.copyWith(
              color: isBest ? AppTheme.textPrimary : AppTheme.textSecondary,
              fontWeight: isBest ? FontWeight.w700 : null,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: _barW,
            height: h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: isBest
                    ? [AppTheme.female.withValues(alpha: 0.5), AppTheme.female]
                    : [
                        AppTheme.primary.withValues(alpha: 0.45),
                        AppTheme.primary,
                      ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(3)),
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

  int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
  double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

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

/// Bar tren 12 bulan — CustomPaint (garis dasar + bar + label bulan,
/// highlight bulan terakhir). Digambar sendiri agar konsisten & tanpa
/// dependency chart eksternal.
class _MonthlyTrendBars extends StatelessWidget {
  const _MonthlyTrendBars({required this.list, required this.s});

  final List<Map<String, dynamic>> list;
  final S s;

  @override
  Widget build(BuildContext context) {
    final counts = [
      for (final m in list) _toInt(m['count']),
    ];
    final maxC = counts.isEmpty ? 1 : counts.reduce(math.max);
    final total = counts.fold<int>(0, (a, b) => a + b);
    final lastMonth = counts.isNotEmpty ? counts.last : 0;
    final prevMonth = counts.length >= 2 ? counts[counts.length - 2] : 0;
    final showDelta = prevMonth >= 10;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('$total', style: AppText.titleEmphasis),
            const SizedBox(width: 6),
            Text(s.adminRegTotalUsersSuffix,
                style:
                    AppText.caption.copyWith(color: AppTheme.textSecondary)),
            const Spacer(),
            if (showDelta)
              _deltaChip(lastMonth, prevMonth),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 118,
          child: CustomPaint(
            // WAJIB size: CustomPaint tanpa child default-nya Size.zero →
            // tak menggambar apa pun (grafik tren tampak KOSONG walau data
            // ada). size: Size.infinite → mengisi constraints SizedBox.
            size: Size.infinite,
            painter: _TrendPainter(
              counts: counts,
              maxCount: maxC <= 0 ? 1 : maxC,
              barColor: AppTheme.primary,
              highlightColor: AppTheme.primaryDark,
              gridColor: AppTheme.divider,
              textColor: AppTheme.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < list.length; i++)
              Expanded(
                child: Text(
                  _label(list[i]),
                  textAlign: TextAlign.center,
                  style: AppText.micro.copyWith(
                    color: i == list.length - 1
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                    fontWeight: i == list.length - 1 ? FontWeight.w700 : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _deltaChip(int last, int prev) {
    final pct = prev > 0 ? ((last - prev) * 100 / prev) : null;
    final up = (pct ?? 0) >= 0;
    final color = up ? AppTheme.online : AppTheme.danger;
    final txt = pct == null
        ? '—'
        : '${up ? '+' : ''}${pct.toStringAsFixed(0)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 12, color: color),
          const SizedBox(width: 3),
          Text(txt,
              style: AppText.caption
                  .copyWith(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text(s.adminRegVsPrevMonth,
              style: AppText.micro.copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  /// Angka dari RPC bisa datang sebagai num ATAU String (PostgREST mengirim
  /// `bigint` sebagai string bila > presisi int64 JSON). Tanpa handle string,
  /// `(m['count'] as num?)` = null → dianggap 0 → grafik tren tampak KOSONG.
  int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  String _label(Map<String, dynamic> m) {
    final month = _toInt(m['month']).clamp(1, 12);
    // Bulan terakhir pakai singkatan, sisanya titik (hemat ruang) — tapi
    // supaya jelas, tampilkan inisial bulan utk semua.
    return s.monthShort[(month - 1).clamp(0, 11)];
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.counts,
    required this.maxCount,
    required this.barColor,
    required this.highlightColor,
    required this.gridColor,
    required this.textColor,
  });

  final List<int> counts;
  final int maxCount;
  final Color barColor;
  final Color highlightColor;
  final Color gridColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (counts.isEmpty) return;
    // Ruang label angka di ATAS bar tertinggi. Bar digambar dari garis
    // dasar (chartH) ke atas; tinggi maksimum dibatasi supaya label
    // tertinggi TIDAK keluar dari area (dulu: bar setinggi penuh → label
    // di atasnya negatif = nembus keluar grafik).
    const labelH = 14.0;
    final chartH = size.height - labelH;
    final n = counts.length;
    final slot = size.width / n;
    final barW = math.min(slot * 0.55, 22.0);

    // Garis grid horizontal (3 baris).
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var g = 1; g <= 3; g++) {
      final y = chartH - (chartH * g / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Bar tertinggi = chartH - labelH (sisakan ruang label di atasnya).
    final maxBarH = chartH - labelH;

    for (var i = 0; i < n; i++) {
      final c = counts[i];
      final h = c == 0
          ? 2.0
          : (c / maxCount * maxBarH).clamp(2.0, maxBarH);
      final cx = slot * i + slot / 2;
      final left = cx - barW / 2;
      final top = chartH - h;
      final isLast = i == n - 1;
      final paint = Paint()
        ..color = isLast ? highlightColor : barColor.withValues(alpha: 0.85);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barW, h),
        const Radius.circular(3),
      );
      canvas.drawRRect(rrect, paint);

      // Angka di atas bar — hanya bila > 0 (0 = bar tipis, label berisik).
      if (c > 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$c',
            style: TextStyle(
              color: isLast ? highlightColor : textColor,
              fontSize: AppGlyph.nano,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final tx = (cx - tp.width / 2).clamp(0.0, size.width - tp.width);
        // Posisi Y label: tepat di atas bar, tapi di-clamp agar tak pernah
        // negatif (nembus atas) walau bar setinggi maksimum.
        final labelY = (top - tp.height - 1).clamp(0.0, chartH);
        tp.paint(canvas, Offset(tx, labelY));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.counts != counts || old.maxCount != maxCount;
}

/// Satu baris data gender untuk bar bertumpuk + legend.
class _GenderRow {
  final String label;
  final int value;
  final Color color;
  const _GenderRow(this.label, this.value, this.color);
}
