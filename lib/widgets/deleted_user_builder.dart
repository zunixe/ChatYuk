import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/riverpod/deleted_users_provider.dart';

/// Bangun [builder] dengan status "akun dihapus" milik [uid]. Cek di-batch
/// lewat [deletedUsersProvider]; rebuild hanya saat status uid INI berubah.
class DeletedUserBuilder extends ConsumerStatefulWidget {
  const DeletedUserBuilder({
    super.key,
    required this.uid,
    required this.builder,
  });

  final String uid;
  final Widget Function(BuildContext context, bool deleted) builder;

  @override
  ConsumerState<DeletedUserBuilder> createState() => _DeletedUserBuilderState();
}

class _DeletedUserBuilderState extends ConsumerState<DeletedUserBuilder> {
  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(covariant DeletedUserBuilder old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _ensure();
  }

  void _ensure() {
    final uid = widget.uid;
    if (uid.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(deletedUsersProvider.notifier).ensureChecked(uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final deleted = ref.watch(
      deletedUsersProvider.select((s) => s.contains(widget.uid)),
    );
    return widget.builder(context, deleted);
  }
}
