import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/config/strings.dart';

/// Pembeda GRUP vs chat personal di daftar Pesan: label pill bilingual.
void main() {
  test('label grup bilingual', () {
    expect(S(isId: true).tabGroups, 'Grup');
    expect(S(isId: false).tabGroups, 'Groups');
  });

  test('label grup + jumlah anggota', () {
    expect(S(isId: true).groupMemberCountLabel(12), 'Grup · 12');
    expect(S(isId: false).groupMemberCountLabel(12), 'Group · 12');
    expect(S(isId: true).groupMemberCountLabel(1), 'Grup · 1');
  });
}
