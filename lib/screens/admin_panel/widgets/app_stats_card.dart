import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../config/theme.dart';

/// Ringkasan tipe akun (registered vs anonim) sebagai grafik pie + statistik
/// versi aplikasi (rata-rata + distribusi teratas). Data dari
/// `admin_stats_compute` (field `registered_users`, `anonymous_users`,
/// `app_versions`, `app_version_avg_scaled`, `app_version_count`).
///
/// Pie digambar sendiri (CustomPainter) — tanpa paket chart eksternal, agar
/// bundle tetap ringan dan konsisten gaya panel admin.
class AdminAppStatsCard extends StatelessWidget {
  const AdminAppStatsCard({super.key, required this.stats, required this.s});

  final Map<String, dynamic>? stats;
  final S s;

  int _int(String k) => (stats?[k] as num?)?.toInt() ?? 0;

  /// Pecah nilai scaled (major*10000+minor*100+patch) → "x.y.z".
  static String versionFromScaled(int scaled) {
    if (scaled <= 0) return '-';
    final major = scaled ~/ 10000;
    final minor = (scaled % 10000) ~/ 100;
    final patch = scaled % 100;
    return '$major.$minor.$patch';
  }

  @override
  Widget build(BuildContext context) {
    final reg = _int('registered_users');
    final anon = _int('anonymous_users');
    return Container(
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
              const Icon(Icons.pie_chart_outline,
                  size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(s.adminAppStatsTitle,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w800,
                  )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PieChart(
                segments: [
                  _PieSeg(reg.toDouble(), AppTheme.primary),
                  _PieSeg(anon.toDouble(), Colors.orange),
                ],
                size: 120,
                centerTop: '${reg + anon}',
                centerBottom: s.adminAppStatsUsers,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legend(Colors.orange, s.adminAppStatsAnon, anon, reg + anon),
                    const SizedBox(height: 10),
                    _legend(AppTheme.primary, s.adminAppStatsReg, reg, reg + anon),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 12),
          _versionBlock(),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label, int value, int total) {
    final pct = total > 0 ? (value * 100 / total) : 0.0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: AppText.bodySmall)),
        Text('$value', style: AppText.bodyStrong),
        const SizedBox(width: 6),
        Text('${pct.toStringAsFixed(0)}%',
            style: AppText.caption.copyWith(color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _versionBlock() {
    final avg = versionFromScaled(_int('app_version_avg_scaled'));
    final count = _int('app_version_count');
    final versions = (stats?['app_versions'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final maxDev = versions.isEmpty
        ? 1
        : versions
            .map((v) => (v['devices'] as num?)?.toInt() ?? 0)
            .reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.system_update_alt,
                size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(s.adminAppVersionAvg,
                style: AppText.caption.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                )),
            const Spacer(),
            Text(avg, style: AppText.bodyStrong.copyWith(color: AppTheme.primary)),
            const SizedBox(width: 6),
            Text('($count ${s.adminAppStatsDevices})',
                style: AppText.micro.copyWith(color: AppTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 10),
        if (versions.isEmpty)
          Text(s.adminAppVersionEmpty,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary))
        else
          for (final v in versions) _versionRow(v, maxDev),
      ],
    );
  }

  Widget _versionRow(Map<String, dynamic> v, int maxDev) {
    final ver = '${v['version'] ?? '?'}';
    final dev = (v['devices'] as num?)?.toInt() ?? 0;
    final frac = maxDev > 0 ? (dev / maxDev).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(ver, style: AppText.bodySmall),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                backgroundColor: AppTheme.bgInput,
                valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text('$dev',
                textAlign: TextAlign.right,
                style: AppText.caption.copyWith(color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _PieSeg {
  final double value;
  final Color color;
  const _PieSeg(this.value, this.color);
}

/// Pie chart donat sederhana (CustomPainter) + label tengah.
class _PieChart extends StatelessWidget {
  const _PieChart({
    required this.segments,
    required this.size,
    this.centerTop = '',
    this.centerBottom = '',
  });

  final List<_PieSeg> segments;
  final double size;
  final String centerTop;
  final String centerBottom;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PiePainter(segments),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(centerTop, style: AppText.titleEmphasis),
              Text(centerBottom,
                  style: AppText.micro.copyWith(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<_PieSeg> segments;
  _PiePainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (a, s) => a + s.value);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const stroke = 22.0;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppTheme.bgInput;
    canvas.drawCircle(center, radius - stroke / 2, bg);

    if (total <= 0) return;

    var start = -math.pi / 2;
    for (final seg in segments) {
      if (seg.value <= 0) continue;
      final sweep = (seg.value / total) * 2 * math.pi;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = seg.color;
      canvas.drawArc(rect, start, sweep, false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) =>
      old.segments != segments;
}
