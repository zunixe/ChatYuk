import 'package:chatyuk/core/admin_trim_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AdminTrimRegistry: run tanpa terdaftar = no-op, tak melempar', () {
    AdminTrimRegistry.run(); // tak ada callback → aman
    expect(AdminTrimRegistry.count, 0);
  });

  test('register/unregister + run memanggil callback; exception ditelan', () {
    var calls = 0;
    void a() => calls++;
    void bad() => throw StateError('boom');
    AdminTrimRegistry.register(a);
    AdminTrimRegistry.register(a); // idempoten
    AdminTrimRegistry.register(bad);
    expect(AdminTrimRegistry.count, 2);
    AdminTrimRegistry.run(); // bad melempar → harus ditelan, a tetap jalan
    expect(calls, greaterThanOrEqualTo(1));
    AdminTrimRegistry.unregister(a);
    AdminTrimRegistry.unregister(bad);
    expect(AdminTrimRegistry.count, 0);
  });
}
