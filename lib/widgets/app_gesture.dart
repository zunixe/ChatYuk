import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';

/// `GestureDetector` dengan long-press dipercepat (lihat [AppTiming]).
///
/// Dipakai di titik yang tahan-lama: tahan pesan untuk memunculkan toolbar
/// reaksi/seleksi, tahan kartu chat untuk mode seleksi.
///
/// `GestureDetector` bawaan Flutter tidak mengekspos durasi long-press, jadi
/// dipakai [RawGestureDetector] dengan [LongPressGestureRecognizer] yang
/// durasinya di-set [AppTiming.longPress] (default Flutter 500ms).
///
/// Tap TIDAK ikut diperlambat: app ini tidak punya double-tap-to-zoom maupun
/// `DoubleTapGestureRecognizer`, jadi `TapGestureRecognizer` langsung
/// menembak (tanpa menunggu jendela double-tap).
class AppGestureDetector extends StatelessWidget {
  final Widget child;
  final GestureTapCallback? onTap;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCancelCallback? onTapCancel;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressCallback? onLongPress;
  final GestureLongPressEndCallback? onLongPressEnd;
  final HitTestBehavior behavior;
  final bool excludeFromSemantics;

  const AppGestureDetector({
    super.key,
    required this.child,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.onLongPressStart,
    this.onLongPress,
    this.onLongPressEnd,
    this.behavior = HitTestBehavior.deferToChild,
    this.excludeFromSemantics = false,
  });

  @override
  Widget build(BuildContext context) {
    final gestures = <Type, GestureRecognizerFactory>{};

    if (onTap != null ||
        onTapDown != null ||
        onTapUp != null ||
        onTapCancel != null) {
      gestures[TapGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        () => TapGestureRecognizer(),
        (r) {
          r.onTap = onTap;
          r.onTapDown = onTapDown;
          r.onTapUp = onTapUp;
          r.onTapCancel = onTapCancel;
        },
      );
    }

    if (onLongPressStart != null || onLongPress != null) {
      gestures[LongPressGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
        () => LongPressGestureRecognizer(duration: AppTiming.longPress),
        (r) {
          r.onLongPressStart = onLongPressStart;
          r.onLongPress = onLongPress;
          r.onLongPressEnd = onLongPressEnd;
        },
      );
    }

    return RawGestureDetector(
      gestures: gestures,
      behavior: behavior,
      excludeFromSemantics: excludeFromSemantics,
      child: child,
    );
  }
}
