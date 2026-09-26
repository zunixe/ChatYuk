import 'dart:async';

import 'package:flutter/widgets.dart';

/// Pemicu paginasi saat scroll mendekati bawah, dengan debounce.
///
/// Menggantikan `_onScroll` yang disalin di tiap tab admin (ambang 300,
/// tanpa debounce) dan layar user (ambang 100, debounce 500ms) — ambang &
/// jeda kini parameter.
class ScrollPagination {
  final ScrollController controller;
  final VoidCallback onLoadMore;
  final double threshold;
  final Duration debounce;

  Timer? _timer;

  ScrollPagination({
    required this.controller,
    required this.onLoadMore,
    this.threshold = 300,
    this.debounce = const Duration(milliseconds: 250),
  }) {
    controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!controller.hasClients) return;
    final pos = controller.position;
    if (pos.pixels < pos.maxScrollExtent - threshold) return;
    if (_timer?.isActive ?? false) return;
    _timer = Timer(debounce, onLoadMore);
  }

  void dispose() {
    _timer?.cancel();
    controller.removeListener(_onScroll);
  }
}
