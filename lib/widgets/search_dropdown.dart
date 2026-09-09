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

  const SearchDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.labels,
    required this.onChanged,
  });

  @override
  State<SearchDropdown> createState() => _SearchDropdownState();
}

class _SearchDropdownState extends State<SearchDropdown> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  Size _fieldSize = Size.zero;
  double _fieldLeft = 0;

  void _togglePanel() {
    if (_portal.isShowing) {
      _portal.hide();
      return;
    }
    final rb = context.findRenderObject() as RenderBox;
    _fieldSize = rb.size;
    _fieldLeft = rb.localToGlobal(Offset.zero).dx;
    _portal.show();
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
                onTap: () => _portal.hide(),
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
                      for (int i = 0; i < widget.items.length; i++)
                        InkWell(
                          onTap: () {
                            widget.onChanged(widget.items[i]);
                            _portal.hide();
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
                                      color: widget.items[i] == widget.value
                                          ? AppTheme.primary
                                          : AppTheme.textPrimary,
                                      fontWeight:
                                          widget.items[i] == widget.value
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                if (widget.items[i] == widget.value)
                                  const Icon(Icons.check,
                                      size: 16, color: AppTheme.primary),
                              ],
                            ),
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
}
