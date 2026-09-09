import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Dropdown single-select TERANCUNG (menempel di bawah field) dengan
/// pencarian live — dipakai filter negara (online) & negara (Global Room).
/// 141 negara tak muat di DropdownButton biasa.
class SearchDropdown extends StatefulWidget {
  final String value;
  final String label;
  final IconData icon;
  final List<String> items;
  final List<String> labels;
  final ValueChanged<String> onChanged;
  // Kalau null → field cari disembunyikan (cocok utk pilihan sedikit).
  final String? searchHint;
  final String? emptyText;

  const SearchDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.labels,
    required this.onChanged,
    this.searchHint,
    this.emptyText,
  });

  @override
  State<SearchDropdown> createState() => _SearchDropdownState();
}

class _SearchDropdownState extends State<SearchDropdown> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Size _fieldSize = Size.zero;
  double _fieldLeft = 0;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _togglePanel() {
    if (_portal.isShowing) {
      _portal.hide();
      return;
    }
    final rb = context.findRenderObject() as RenderBox;
    _fieldSize = rb.size;
    _fieldLeft = rb.localToGlobal(Offset.zero).dx;
    setState(() {
      _query = '';
      _searchCtrl.clear();
    });
    _portal.show();
    // Fokus field cari setelah panel terpasang supaya keyboard langsung naik.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _portal.isShowing) _searchFocus.requestFocus();
    });
  }

  void _hidePanel() {
    _searchFocus.unfocus();
    _portal.hide();
  }

  List<int> get _filtered {
    if (_query.isEmpty) {
      return List<int>.generate(widget.items.length, (i) => i);
    }
    final q = _query.toLowerCase();
    final out = <int>[];
    for (int i = 0; i < widget.items.length; i++) {
      if (widget.labels[i].toLowerCase().contains(q) ||
          widget.items[i].toLowerCase().contains(q)) {
        out.add(i);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayCtx) {
        final screenW = MediaQuery.of(overlayCtx).size.width;
        final availW = screenW - _fieldLeft - 8;
        final panelW = _fieldSize.width.clamp(0.0, availW).toDouble();
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _hidePanel,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 4),
              showWhenUnlinked: false,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: panelW,
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
                      if (widget.searchHint != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                          child: TextField(
                            controller: _searchCtrl,
                            focusNode: _searchFocus,
                            onChanged: (v) =>
                                setState(() => _query = v.trim()),
                            style: AppText.bodySmall.copyWith(
                                color: AppTheme.textPrimary),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: widget.searchHint,
                              hintStyle: AppText.bodySmall.copyWith(
                                  color: AppTheme.textSecondary),
                              prefixIcon: Icon(Icons.search,
                                  size: 18, color: AppTheme.textSecondary),
                              prefixIconConstraints: const BoxConstraints(
                                  minWidth: 32, minHeight: 0),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                          ),
                        ),
                      Flexible(
                        child: _buildItemList(),
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
              prefixIcon: Icon(widget.icon,
                  size: 20, color: AppTheme.textSecondary),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 36, minHeight: 0),
              labelText: widget.label,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            child: Text(
              widget.labels[widget.items
                  .indexOf(widget.value)
                  .clamp(0, widget.labels.length - 1)],
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
            ),
          ),
        ),
      ),
    );
  }

  /// Daftar item terfilter + scroll (141 negara tak muat satu layar).
  Widget _buildItemList() {
    final idx = _filtered;
    if (idx.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Text(
          widget.emptyText ?? '',
          style:
              AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: idx.length,
        itemBuilder: (_, k) {
          final i = idx[k];
          final selected = widget.items[i] == widget.value;
          return InkWell(
            onTap: () {
              widget.onChanged(widget.items[i]);
              _hidePanel();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.labels[i],
                      style: AppText.bodySmall.copyWith(
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textPrimary,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check,
                        size: 16, color: AppTheme.primary),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
