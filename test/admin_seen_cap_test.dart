import 'package:chatyuk/providers/admin_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('_boundedAdd cap 500 FIFO (R6)', () {
    final set = <String>{};
    // Akses via refleksi tak perlu — uji perilaku lewat ekspos test di base.
    AdminBaseTestHook.boundedAdd(set, 'first');
    for (var i = 0; i < 600; i++) {
      AdminBaseTestHook.boundedAdd(set, 'id-$i');
    }
    expect(set.length, lessThanOrEqualTo(AdminBaseTestHook.seenMax));
    expect(set.contains('first'), isFalse);
    expect(set.contains('id-599'), isTrue);
  });
}
