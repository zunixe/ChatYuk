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

  test('migrateViewOnceState: pending → id server (anti-blink)', () {
    viewOnceStates.clear();
    final t = ViewOnceTick();
    t.decoded = null;
    putViewOnceState('pending-123', t);

    migrateViewOnceState('pending-123', '999');

    expect(viewOnceStates.containsKey('pending-123'), isFalse);
    expect(identical(viewOnceStates['999'], t), isTrue);
    viewOnceStates.clear();
  });

  test('migrateViewOnceState: target sudah ada → decoded diwarisi', () {
    viewOnceStates.clear();
    final pendingTick = ViewOnceTick();
    putViewOnceState('pending-1', pendingTick);
    final serverTick = ViewOnceTick();
    putViewOnceState('555', serverTick);

    migrateViewOnceState('pending-1', '555');

    // Target tetap dipakai (tidak ditimpa) → state tampilan tak reset.
    expect(identical(viewOnceStates['555'], serverTick), isTrue);
    expect(viewOnceStates.containsKey('pending-1'), isFalse);
    viewOnceStates.clear();
  });

  test('migrateViewOnceState: id sama / kosong → no-op', () {
    viewOnceStates.clear();
    final t = ViewOnceTick();
    putViewOnceState('x', t);
    migrateViewOnceState('x', 'x');
    migrateViewOnceState('', 'y');
    expect(identical(viewOnceStates['x'], t), isTrue);
    viewOnceStates.clear();
  });
}
