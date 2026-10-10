import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../providers/riverpod/locale_provider.dart';

/// Multi-select negara — panel TERANCUNG menempel di bawah field (bukan
/// bottom sheet): search live + checklist + footer Reset/Terapkan.
/// Kosong = Semua. Commit hanya saat Terapkan (tap luar = batal).
class FilterDropdown extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<String> items;
  final List<String> labels;
  final List<String> selected;
  final String Function(int n) countText;
  final ValueChanged<List<String>> onChanged;

  const FilterDropdown({
    super.key,
    required this.label,
    required this.icon,
    required this.items,
    required this.labels,
    required this.selected,
    required this.countText,
    required this.onChanged,
  });

  @override
  State<FilterDropdown> createState() => _FilterDropdownState();
}

class _FilterDropdownState extends State<FilterDropdown>
    with WidgetsBindingObserver {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  Set<String> _temp = {};
  Size _fieldSize = Size.zero;
  double _fieldLeft = 0;

  /// Tinggi keyboard MENTAH — `MediaQuery.of(context).viewInsets.bottom`
  /// selalu 0 di body Scaffold (di-mask `resizeToAvoidBottomInset`).
  double get _keyboardH => MediaQueryData.fromView(
    WidgetsBinding.instance.platformDispatcher.views.first,
  ).viewInsets.bottom;

  @override
  void initState() {
    super.initState();
    // Keyboard buka/tutup TIDAK memicu rebuild OverlayPortal
    // (_OverlayPortalState.didChangeDependencies hanya set flag, tanpa
    // setState) → panel tertinggal di posisi lama & tertutup keyboard.
    // Observer ini yang memaksa panel reposisi. (User: "pas keyboard keatas
    // dropdownnya ga ilang")
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    if (_portal.isShowing && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fieldText() {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final n = widget.selected.length;
    if (n == 0) return s.filterAll;
    if (n == 1) {
      final idx = widget.items
          .indexOf(widget.selected.first)
          .clamp(0, widget.labels.length - 1);
      return widget.labels[idx];
    }
    return widget.countText(n);
  }

  void _togglePanel() {
    if (_portal.isShowing) {
      _portal.hide();
      return;
    }
    final rb = context.findRenderObject() as RenderBox;
    _fieldSize = rb.size;
    _fieldLeft = rb.localToGlobal(Offset.zero).dx;
    _temp = widget.selected.toSet();
    _searchCtrl.clear();
    _query = '';
    _portal.show();
  }

  void _apply() {
    widget.onChanged(widget.items.where(_temp.contains).toList());
    _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayCtx) {
        final mq = MediaQuery.of(overlayCtx);
        // Lebar: field + 96px ke kanan, clamp ke tepi layar (field kanan).
        final screenW = mq.size.width;

        // Panel hidup di Overlay → TIDAK ikut resize saat keyboard naik.
        // Hitung sendiri ruang terlihat + posisi field TERBARU, lalu buka ke
        // ATAS bila ruang bawah tidak layak (bug "pilihan negara ilang saat
        // keyboard naik" di tab Online).
        final visibleBottom = mq.size.height - mq.padding.bottom - _keyboardH;
        final rb = context.findRenderObject() as RenderBox?;
        double fieldTop = 0, fieldBottom = 0, fieldLeft = _fieldLeft;
        if (rb != null && rb.hasSize) {
          final origin = rb.localToGlobal(Offset.zero);
          fieldTop = origin.dy;
          fieldBottom = fieldTop + rb.size.height;
          fieldLeft = origin.dx;
        }
        final availW = screenW - fieldLeft - 8;
        final panelW = (_fieldSize.width + 96).clamp(0.0, availW).toDouble();

        const gap = 4.0;
        const maxPanel = 340.0;
        final spaceBelow = visibleBottom - fieldBottom - gap;
        // Selalu buka ke BAWAH — field negara ada di atas layar, panel
        // harus menempel di bawah field dan menyesuaikan tinggi terhadap
        // ruang tersisa (keyboard buka → panel mengecil, bukan pindah).
        final panelMaxH = spaceBelow.clamp(120.0, maxPanel);

        final filtered = [
          for (int i = 0; i < widget.items.length; i++)
            if (_query.isEmpty || widget.labels[i].toLowerCase().contains(_query))
              i,
        ];
        return Stack(
          children: [
            // Penutup: tap di luar = batal (tanpa commit).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _portal.hide(),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, gap),
              showWhenUnlinked: false,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: panelW,
                  constraints: BoxConstraints(maxHeight: panelMaxH),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.divider),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                        // Tinggi 40 — sama seperti form cari nama di AppBar.
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            controller: _searchCtrl,
                            autofocus: false,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textPrimary,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 18),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 0,
                              ),
                              hintText: s.searchCountry,
                              hintStyle: AppText.bodySmall.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: AppTheme.divider),
                              ),
                            ),
                            onChanged: (q) =>
                                setState(() => _query = q.trim().toLowerCase()),
                          ),
                        ),
                      ),
                      Flexible(
                        child: filtered.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  '-',
                                  style: AppText.bodySmall.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final idx = filtered[i];
                                  final checked = _temp.contains(
                                    widget.items[idx],
                                  );
                                  return CheckboxListTile(
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    value: checked,
                                    title: Text(
                                      widget.labels[idx],
                                      style: AppText.bodySmall.copyWith(
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.trailing,
                                    activeColor: AppTheme.primary,
                                    checkboxShape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _temp.add(widget.items[idx]);
                                        } else {
                                          _temp.remove(widget.items[idx]);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                      Divider(height: 1, color: AppTheme.divider),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => setState(() => _temp = {}),
                              icon: const Icon(
                                Icons.filter_alt_off_outlined,
                                size: 16,
                              ),
                              label: Text(s.filterReset),
                              // Tinggi 40 — sama dengan field cari & Terapkan.
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.textSecondary,
                                textStyle: AppText.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Tinggi dikunci 40 — sama persis dengan field cari negara.
                            SizedBox(
                              height: 40,
                              child: FilledButton.icon(
                                onPressed: _apply,
                                icon: const Icon(Icons.check, size: 16),
                                label: Text(
                                  '${s.filterApply} (${_temp.length})',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  textStyle: AppText.bodySmall.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: GestureDetector(
          onTap: _togglePanel,
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(
                widget.icon,
                size: 20,
                color: AppTheme.textSecondary,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 0,
              ),
              labelText: widget.label,
              contentPadding:
                  // Sama dengan SearchDropdown (gender) → tinggi identik.
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 0,
              ),
              suffixIcon: widget.selected.isEmpty
                  ? Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: AppTheme.textSecondary,
                    )
                  : GestureDetector(
                      onTap: () => widget.onChanged(const []),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: AppTheme.textSecondary,
                      ),
                    ),
            ),
            child: Text(
              _fieldText(),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
