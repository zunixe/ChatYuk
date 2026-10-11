import 'package:chatyuk/core/app_foreground.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppForeground.isForeground.value = true);

  test('resumed -> foreground true; paused/inactive -> false', () {
    AppForeground.set(AppLifecycleState.resumed);
    expect(AppForeground.now, isTrue);
    AppForeground.set(AppLifecycleState.paused);
    expect(AppForeground.now, isFalse);
    AppForeground.set(AppLifecycleState.inactive);
    expect(AppForeground.now, isFalse);
    AppForeground.set(AppLifecycleState.resumed);
    expect(AppForeground.now, isTrue);
  });
}
