import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;

import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../widgets/sheet_drag_handle.dart';
import '../../../providers/riverpod/admin_provider.dart';

/// Kartu "Sebaran Negara" untuk Ringkasan admin: bar horizontal negara
/// dengan user terbanyak. Ketuk negara → sheet daftar kota + jumlahnya.
class AdminGeoStatsCard extends ConsumerStatefulWidget {
  const AdminGeoStatsCard();
  @override
  ConsumerState<AdminGeoStatsCard> createState() => _AdminGeoStatsCardState();
}

class _AdminGeoStatsCardState extends ConsumerState<AdminGeoStatsCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ProviderScope.containerOf(context, listen: false).read(adminProvider).fetchCountryStats();
    });
  }

  int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final admin = ref.watch(adminProvider);
    final list = admin.countryStats;

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
              const Icon(Icons.public_rounded, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.adminGeoTitle, style: AppText.bodyStrong),
              ),
              if (list.isNotEmpty)
                Text(
                  '${list.length}',
                  style: AppText.bodyStrong.copyWith(color: AppTheme.primary),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            s.adminGeoSubtitle,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          if (admin.geoLoading && list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            )
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  s.adminGeoEmpty,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            )
          else
            _countryBars(s, list),
        ],
      ),
    );
  }

  Widget _countryBars(S s, List<Map<String, dynamic>> list) {
    // Tampilkan maks 10 negara teratas (list sudah terurut desc dari server).
    final top = list.take(10).toList();
    final maxC = top.isEmpty
        ? 1
        : top.map((e) => _i(e['count'])).reduce((a, b) => a > b ? a : b);
    final total = list.fold<int>(0, (a, e) => a + _i(e['count']));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in top) ...[
          _bar(
            s,
            label: '${e['country'] ?? '?'}',
            count: _i(e['count']),
            registered: _i(e['registered']),
            maxC: maxC <= 0 ? 1 : maxC,
            onTap: () => _openCities(context, s, '${e['country'] ?? '?'}'),
          ),
          const SizedBox(height: 8),
        ],
        const Divider(height: 18),
        Row(
          children: [
            Text(
              s.adminRegTotal,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
            const Spacer(),
            Text('$total ${s.adminGeoUserSuffix}', style: AppText.bodyStrong),
          ],
        ),
      ],
    );
  }

  Widget _bar(
    S s, {
    required String label,
    required int count,
    required int registered,
    required int maxC,
    required VoidCallback onTap,
  }) {
    final frac = (count / maxC).clamp(0.04, 1.0);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppText.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: AppText.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Track + fill proporsional.
            LayoutBuilder(
              builder: (_, c) {
                return Stack(
                  children: [
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppTheme.bgInput,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    Container(
                      height: 10,
                      width: c.maxWidth * frac,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.accent],
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 3),
            Text(
              '$registered ${s.adminGeoRegisteredSuffix}',
              style: AppText.micro.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCities(
    BuildContext context,
    S s,
    String country,
  ) async {
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgScreen,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _CitySheet(
        s: s,
        country: country,
        loader: () => admin.fetchCityStats(country),
      ),
    );
  }
}

class _CitySheet extends StatefulWidget {
  final S s;
  final String country;
  final Future<List<Map<String, dynamic>>> Function() loader;
  const _CitySheet({
    required this.s,
    required this.country,
    required this.loader,
  });

  @override
  State<_CitySheet> createState() => _CitySheetState();
}

class _CitySheetState extends State<_CitySheet> {
  List<Map<String, dynamic>>? _cities;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.loader();
    if (mounted) setState(() => _cities = list);
  }

  int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final cities = _cities;
    final total = (cities ?? const []).fold<int>(0, (a, e) => a + _i(e['count']));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                children: [
                  const Icon(Icons.location_city_rounded,
                      size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.adminGeoCityTitle(widget.country),
                      style: AppText.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (cities != null)
                    Text('$total', style: AppText.bodyStrong),
                ],
              ),
            ),
            Expanded(
              child: cities == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : cities.isEmpty
                      ? Center(
                          child: Text(
                            s.adminGeoEmpty,
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            4,
                            16,
                            MediaQuery.of(context).padding.bottom + 20,
                          ),
                          itemCount: cities.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final e = cities[i];
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${e['city'] ?? '?'}',
                                      style: AppText.body,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${_i(e['registered'])} ${s.adminGeoRegisteredSuffix}',
                                    style: AppText.micro.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      '${_i(e['count'])}',
                                      textAlign: TextAlign.right,
                                      style: AppText.bodyStrong
                                          .copyWith(color: AppTheme.primary),
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
