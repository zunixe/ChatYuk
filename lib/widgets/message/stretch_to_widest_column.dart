import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Kolom yang lebarnya = anak TERLEBAR, lalu SEMUA anak dibentangkan
/// selebar itu (kutipan balasan selebar bubble ala WhatsApp).
///
/// Pengganti `IntrinsicWidth` + `CrossAxisAlignment.stretch`: anak bubble
/// teks memakai `LayoutBuilder` (MessageTextWithTime) yang TIDAK mendukung
/// intrinsic dimension. Di sini anak di-layout BIASA dua kali (longgar →
/// ukur terlebar; ketat → bentang), jadi aman untuk LayoutBuilder.
class StretchToWidestColumn extends MultiChildRenderObjectWidget {
  const StretchToWidestColumn({super.key, super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStretchToWidest();
}

class _StwParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderStretchToWidest extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _StwParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _StwParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StwParentData) {
      child.parentData = _StwParentData();
    }
  }

  @override
  void performLayout() {
    final maxW = constraints.maxWidth;
    // 1) Longgar: cari anak terlebar.
    var widest = constraints.minWidth;
    var c = firstChild;
    while (c != null) {
      c.layout(BoxConstraints(maxWidth: maxW), parentUsesSize: true);
      widest = math.max(widest, c.size.width);
      c = childAfter(c);
    }
    widest = math.min(widest, maxW);
    // 2) Ketat selebar terlebar: bentang + tumpuk vertikal.
    var y = 0.0;
    c = firstChild;
    while (c != null) {
      c.layout(BoxConstraints.tightFor(width: widest), parentUsesSize: true);
      (c.parentData! as _StwParentData).offset = Offset(0, y);
      y += c.size.height;
      c = childAfter(c);
    }
    size = constraints.constrain(Size(widest, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
