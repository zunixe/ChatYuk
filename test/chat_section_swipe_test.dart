import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/screens/chats_screen.dart';
import 'package:chatyuk/widgets/chat_yuk_chat_header.dart';

/// Mengunci logika swipe section chat (Pesan ⇄ Global Room) ala Timeline.
/// Grup BUKAN section — grup tampil sebagai ITEM di daftar Pesan.
void main() {
  test('geser KIRI → Room', () {
    expect(chatSectionAfterSwipe(ChatSection.messages, -800),
        ChatSection.rooms);
  });

  test('geser KANAN → Pesan', () {
    expect(chatSectionAfterSwipe(ChatSection.rooms, 800),
        ChatSection.messages);
  });

  test('di ujung → tidak berpindah', () {
    expect(chatSectionAfterSwipe(ChatSection.messages, 800), isNull);
    expect(chatSectionAfterSwipe(ChatSection.rooms, -800), isNull);
  });

  test('geseran pelan (< ambang) diabaikan', () {
    expect(chatSectionAfterSwipe(ChatSection.messages, -100), isNull);
  });
}
