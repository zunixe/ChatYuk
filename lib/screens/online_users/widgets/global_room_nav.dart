import 'package:flutter/material.dart';

/// Buka chat room DENGAN menu Global Room di bawahnya, sehingga tumpukan:
/// `Online → Menu Global Room → Chat Room`.
///
/// Permintaan user (2026-10-18): dari ikon Global Room di halaman Online,
/// BACK di chat room harus kembali ke MENU GLOBAL ROOM, bukan ke Online.
/// Dulu jalur utama mendorong chat room LANGSUNG di atas Online.
///
/// Menu didorong TANPA animasi masuk (hanya satu animasi yang terlihat:
/// chat room masuk), tetapi animasi KELUAR-nya normal saat user kembali
/// dari menu ke Online.
Future<void> openRoomWithMenuBelow(
  NavigatorState nav, {
  required WidgetBuilder menu,
  required WidgetBuilder room,
}) {
  nav.push(_InstantInRoute<void>(builder: menu));
  return nav.push(MaterialPageRoute<void>(builder: room));
}

class _InstantInRoute<T> extends MaterialPageRoute<T> {
  _InstantInRoute({required super.builder});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration =>
      const Duration(milliseconds: 300);
}
