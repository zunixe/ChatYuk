import 'package:chatyuk/services/topup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playAccountHash = SHA-256 hex (sama dgn crypto.subtle di edge fn)', () {
    expect(
      playAccountHash('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(playAccountHash(null), isNull);
  });
}
