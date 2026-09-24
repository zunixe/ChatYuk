import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/points_provider.dart';
import 'panel_card.dart';

/// Ringkasan rata-rata & total poin.
class PointStatsCard extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final S s;
  const PointStatsCard({super.key, required this.stats, required this.s});

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        s.statsAvg,
        '${stats?['avg_points'] ?? '-'}',
        Icons.trending_up,
        Colors.amber.shade700,
      ),
      (
        s.statsTotal,
        '${stats?['total_points'] ?? '-'}',
        Icons.monetization_on_outlined,
        Colors.pink,
      ),
    ];
    Widget cell(int i) {
      return Expanded(
        child: Material(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 76,
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(items[i].$3, size: 15, color: items[i].$4),
                SizedBox(height: 5),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      items[i].$2,
                      style: AppText.titleEmphasis.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  items[i].$1,
                  style: AppText.micro.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [cell(0), const SizedBox(width: 8), cell(1)]),
      ],
    );
  }
}

/// Peringkat peraih poin tertinggi + peringatan user macet.
class TopEarnersCard extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final S s;
  const TopEarnersCard({super.key, required this.stats, required this.s});

  @override
  Widget build(BuildContext context) {
    final earners = (stats?['top_earners'] as List?) ?? [];
    return PanelCard(s.adminTopEarners, Icons.emoji_events_outlined, Colors.amber, [
      if (earners.isEmpty)
        Text(
          s.adminNoUsers,
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
      for (var i = 0; i < earners.length && i < 5; i++)
        Padding(
          padding: EdgeInsets.only(bottom: 5),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '${i + 1}',
                  style: AppText.caption.copyWith(
                    color: i == 0 ? Colors.amber : AppTheme.textSecondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${earners[i]['nickname'] ?? '?'}',
                  style: AppText.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${earners[i]['points'] ?? 0} pts',
                  style: AppText.caption.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      if ((stats?['stuck_users'] ?? 0) > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: AppTheme.danger,
              ),
              const SizedBox(width: 4),
              Text(
                '${stats!['stuck_users']} ${s.adminStuckUsers}',
                style: AppText.caption.copyWith(color: AppTheme.danger),
              ),
            ],
          ),
        ),
    ]);
  }
}

/// Toggle sistem poin (jalan/jeda) + sinkron ke PointsProvider.
class PointsSystemCard extends StatelessWidget {
  final AdminProvider admin;
  final S s;
  const PointsSystemCard({super.key, required this.admin, required this.s});

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      s.adminPointsSystem,
      Icons.toggle_on_outlined,
      AppTheme.primary,
      [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (admin.pointsEnabled ? Colors.green : AppTheme.danger)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: admin.pointsEnabled ? Colors.green : AppTheme.danger,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    admin.pointsEnabled ? s.adminRunning : s.adminPaused,
                    style: AppText.bodySmall.copyWith(
                      color: admin.pointsEnabled
                          ? Colors.green
                          : AppTheme.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Switch(
              value: admin.pointsEnabled,
              onChanged: (v) {
                admin.togglePointsSystem(v);
                context.read<PointsProvider>().refreshEnabled();
              },
              activeColor: AppTheme.primary,
            ),
          ],
        ),
        SizedBox(height: 2),
        Text(
          s.adminRealtimeDesc,
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

/// Form nominal semua pengaturan poin + tombol simpan.
/// Controller & status milik screen (stateful) — widget ini murni tampil.
class PointSettingsCard extends StatelessWidget {
  final S s;
  final bool loaded;
  final TextEditingController shareCtrl;
  final List<(String, String)> fields;
  final Map<String, TextEditingController> ctrls;
  final bool saving;
  final Future<void> Function() onSave;
  const PointSettingsCard({
    super.key,
    required this.s,
    required this.loaded,
    required this.shareCtrl,
    required this.fields,
    required this.ctrls,
    required this.saving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return PanelCard(s.adminPointSettings, Icons.tune, Colors.indigo, [
      if (!loaded)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ),
          ),
        )
      else ...[
        TextField(
          controller: shareCtrl,
          keyboardType: TextInputType.url,
          style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            labelText: s.adminShareLinkLabel,
            isDense: true,
            filled: true,
            fillColor: AppTheme.bgInput,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Klik link share user → redirect ke link ini. Ganti ke Google Play nanti.',
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
        ),
        SizedBox(height: 10),
        for (final f in fields)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    f.$2,
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: ctrls[f.$1],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: AppText.bodyStrong,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(s.adminSavePointSettings),
          ),
        ),
      ],
    ]);
  }
}

/// Bonus massal ke semua user terdaftar.
class MassBonusCard extends StatelessWidget {
  final S s;
  final TextEditingController bonusCtrl;
  final AdminProvider admin;
  final void Function(String msg) onToast;
  const MassBonusCard({
    super.key,
    required this.s,
    required this.bonusCtrl,
    required this.admin,
    required this.onToast,
  });

  @override
  Widget build(BuildContext context) {
    return PanelCard(s.adminMassBonus, Icons.card_giftcard, Colors.amber, [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: bonusCtrl,
              keyboardType: TextInputType.number,
              style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: s.pointsBalance,
                isDense: true,
                filled: true,
                fillColor: AppTheme.bgInput,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: () async {
              final amount = int.tryParse(bonusCtrl.text) ?? 0;
              if (amount <= 0) return;
              final result = await admin.massBonus(amount);
              if (result != null) {
                onToast('+$amount → ${result['affected']} users');
              }
            },
            icon: Icon(Icons.send_rounded, size: 16),
            label: Text(s.btnSend),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
      SizedBox(height: 4),
      Text(
        s.adminRegisteredOnly,
        style: AppText.caption.copyWith(color: AppTheme.textSecondary),
      ),
    ]);
  }
}
