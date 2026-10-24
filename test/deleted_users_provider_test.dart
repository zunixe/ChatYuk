import 'package:chatyuk/providers/riverpod/deleted_users_provider.dart';
import 'package:chatyuk/services/chat_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeChat extends ChatService {
  _FakeChat(this.deleted, {this.fail = false});
  final Set<String> deleted;
  bool fail;
  final calls = <List<String>>[];

  @override
  Future<Set<String>?> missingProfileUids(List<String> uids) async {
    calls.add(uids);
    if (fail) return null;
    return uids.where(deleted.contains).toSet();
  }
}

ProviderContainer _container(_FakeChat fake) => ProviderContainer(
  overrides: [
    deletedUsersProvider.overrideWith(
      () => DeletedUsersNotifier(service: fake),
    ),
  ],
);

void main() {
  test('cek di-batch jadi satu query & hanya uid hilang yang ditandai', () async {
    final fake = _FakeChat({'b'});
    final c = _container(fake);
    addTearDown(c.dispose);
    final n = c.read(deletedUsersProvider.notifier);
    n.ensureChecked('a');
    n.ensureChecked('b');
    n.ensureChecked('a');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(fake.calls, hasLength(1));
    expect(fake.calls.single.toSet(), {'a', 'b'});
    expect(c.read(deletedUsersProvider), {'b'});
    n.ensureChecked('b');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(fake.calls, hasLength(1));
  });

  test('query gagal: tidak ada yang ditandai & boleh dicek ulang', () async {
    final fake = _FakeChat({'x'}, fail: true);
    final c = _container(fake);
    addTearDown(c.dispose);
    final n = c.read(deletedUsersProvider.notifier);
    n.ensureChecked('x');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(c.read(deletedUsersProvider), isEmpty);
    fake.fail = false;
    n.ensureChecked('x');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(c.read(deletedUsersProvider), {'x'});
  });

  test('markDeleted menandai langsung', () {
    final c = _container(_FakeChat({}));
    addTearDown(c.dispose);
    c.read(deletedUsersProvider.notifier).markDeleted('z');
    expect(c.read(deletedUsersProvider), {'z'});
  });
}
