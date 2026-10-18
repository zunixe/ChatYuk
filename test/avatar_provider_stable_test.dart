import 'dart:typed_data';

import 'package:chatyuk/widgets/user_avatar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('avatarImageProviderFor: instance STABIL per-uid (anti decode ulang)', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final p1 = avatarImageProviderFor('uid-a', bytes);
    final p2 = avatarImageProviderFor('uid-a', Uint8List.fromList([9, 9]));
    // uid sama -> instance SAMA walau bytes beda (identitas stabil menang).
    expect(identical(p1, p2), isTrue);
    // uid beda -> instance beda.
    final p3 = avatarImageProviderFor('uid-b', bytes);
    expect(identical(p1, p3), isFalse);
  });

  test('avatarImageProviderFor: uid/bytes kosong -> null', () {
    expect(avatarImageProviderFor('', Uint8List.fromList([1])), isNull);
    expect(avatarImageProviderFor('uid', Uint8List(0)), isNull);
  });
}
