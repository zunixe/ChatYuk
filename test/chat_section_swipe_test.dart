import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/screens/chats_screen.dart';
import 'package:chatyuk/widgets/chat_yuk_chat_header.dart';

/// Mengunci urutan geser di halaman Chat: Private → Grup → Global Room
/// (Grup kini TAB di dalam section Pesan) dan sebaliknya.
void main() {
  test('geser KIRI: Private → Grup → Room', () {
    expect(
      chatSwipeTarget(
          section: ChatSection.messages, tab: ChatTab.private, velocity: -800),
      (section: ChatSection.messages, tab: ChatTab.groups),
    );
    expect(
      chatSwipeTarget(
          section: ChatSection.messages, tab: ChatTab.groups, velocity: -800),
      (section: ChatSection.rooms, tab: ChatTab.groups),
    );
  });

  test('geser KANAN: Room → Grup → Private', () {
    expect(
      chatSwipeTarget(
          section: ChatSection.rooms, tab: ChatTab.groups, velocity: 800),
      (section: ChatSection.messages, tab: ChatTab.groups),
    );
    expect(
      chatSwipeTarget(
          section: ChatSection.messages, tab: ChatTab.groups, velocity: 800),
      (section: ChatSection.messages, tab: ChatTab.private),
    );
  });

  test('di ujung → tidak berpindah', () {
    expect(
      chatSwipeTarget(
          section: ChatSection.messages, tab: ChatTab.private, velocity: 800),
      isNull,
    );
    expect(
      chatSwipeTarget(
          section: ChatSection.rooms, tab: ChatTab.groups, velocity: -800),
      isNull,
    );
  });

  test('geseran pelan (< ambang) diabaikan', () {
    expect(
      chatSwipeTarget(
          section: ChatSection.messages, tab: ChatTab.private, velocity: -100),
      isNull,
    );
  });
}
