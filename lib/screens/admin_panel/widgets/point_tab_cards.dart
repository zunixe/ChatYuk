import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/riverpod/points_provider.dart';
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
        s.adminAvgBalance,
        '${stats?['avg_points'] ?? '-'}',
        Icons.trending_up,
        Colors.amber.shade700,
      ),
      (
        s.adminTotalBalance,
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    items[i].$1,
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
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
                  s.adminCoinAmount(
                    (earners[i]['points'] as num?)?.toInt() ?? 0,
                  ),
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
                ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier).refreshEnabled();
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
  final Map<String, bool> flags;
  final void Function(String key, bool value) onFlagChanged;
  final bool saving;
  final Future<void> Function() onSave;
  const PointSettingsCard({
    super.key,
    required this.s,
    required this.loaded,
    required this.shareCtrl,
    required this.fields,
    required this.ctrls,
    required this.flags,
    required this.onFlagChanged,
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
          s.adminShareLinkHint,
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
        ),
        SizedBox(height: 10),
        // Toggle booleans (Switch) — fitur on/off.
        if (flags.containsKey('yukcoin_v2_enabled'))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.adminYukcoinV2,
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Switch(
                  value: flags['yukcoin_v2_enabled'] ?? false,
                  onChanged: saving
                      ? null
                      : (v) => onFlagChanged('yukcoin_v2_enabled', v),
                  activeColor: AppTheme.primary,
                ),
              ],
            ),
          ),
        // Status ringkas YukCoin v2 (konteks di sebelah toggle-nya).
        if (flags.containsKey('yukcoin_v2_enabled'))
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              (flags['yukcoin_v2_enabled'] ?? false)
                  ? s.adminYukcoinV2On
                  : s.adminYukcoinV2Off,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ),
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
                onToast(s.adminMassBonusDone(
                  amount,
                  (result['affected'] as num?)?.toInt() ?? 0,
                ));
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

/// Kartu "Publish Fitur" — toggle published per fitur berbayar baru.
/// Fitur dibangun & diuji di build adminProd (admin selalu lolos gate),
/// lalu dipublish global dari sini (tanpa rebuild app).
class FeaturePublishCard extends StatefulWidget {
  final S s;
  final void Function(String msg) onToast;
  const FeaturePublishCard({super.key, required this.s, required this.onToast});

  @override
  State<FeaturePublishCard> createState() => _FeaturePublishCardState();
}

class _FeaturePublishCardState extends State<FeaturePublishCard> {
  Map<String, dynamic> _flags = {};
  bool _loaded = false;
  bool _saving = false;

  List<(String, String)> get _items => [
    ('call_billing', widget.s.adminFlagCallBilling),
    ('gender_filter_paid', widget.s.adminFlagGenderFilter),
    ('nearby_paid', widget.s.adminFlagNearby),
    ('play_topup', widget.s.adminFlagPlayTopup),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await context.read<AdminProvider>().getFeatureFlags();
      if (mounted) setState(() { _flags = res; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  bool _isPublished(String f) =>
      (_flags[f] is Map) && ((_flags[f] as Map)['published'] == true);

  Future<void> _toggle(String feature, bool v) async {
    setState(() => _saving = true);
    try {
      final res = await context.read<AdminProvider>().setFeatureFlag(feature, v);
      final pp = ProviderScope.containerOf(context, listen: false).read(pointsProvider.notifier);
      await pp.refreshMeteredPricing();
      if (mounted) {
        setState(() => _flags = res);
        widget.onToast(
          v ? widget.s.adminFeaturePublished : widget.s.adminFeatureHidden,
        );
      }
    } catch (e) {
      if (mounted) widget.onToast('${widget.s.errGeneric}$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      widget.s.adminPublishTitle,
      Icons.rocket_launch_outlined,
      Colors.teal,
      [
      Text(
        widget.s.adminPublishDesc,
        style: AppText.caption.copyWith(color: AppTheme.textSecondary),
      ),
      const SizedBox(height: 8),
      if (!_loaded)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
          ),
        )
      else
        for (final it in _items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(it.$2, style: AppText.bodySmall),
                ),
                Switch(
                  value: _isPublished(it.$1),
                  onChanged: _saving ? null : (v) => _toggle(it.$1, v),
                  activeColor: AppTheme.primary,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
