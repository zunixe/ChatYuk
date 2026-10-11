import 'package:chatyuk/widgets/message/view_once_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('viewOnceStates dibatasi cap FIFO (R4/R6)', () {
    viewOnceStates.clear();
    for (var i = 0; i < 130; i++) {
      putViewOnceState('msg-$i', ViewOnceTick());
    }
    expect(viewOnceStates.length, lessThanOrEqualTo(viewOnceStatesMax));
    // Entri tertua terbuang, terbaru ada.
    expect(viewOnceStates.containsKey('msg-0'), isFalse);
    expect(viewOnceStates.containsKey('msg-129'), isTrue);
    // Id yang sudah ada mengembalikan objek SAMA (bukan menimpa).
    final a = putViewOnceState('msg-129', ViewOnceTick());
    expect(identical(a, viewOnceStates['msg-129']), isTrue);
    viewOnceStates.clear();
  });
}
