import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../providers/riverpod/social_provider.dart';
import '../../widgets/social_actions.dart';

/// Tombol add friend di list pesan untuk user yang terdaftar (registered).
/// Status dibaca dari SocialNotifier (set global, ter-load saat app start +
/// cache disk) — TANPA RPC per-item (dulu: my_social_status per tombol =
/// N+1 RPC, spinner berjejak saat jaringan lambat).
class FriendButton extends ConsumerStatefulWidget {
  final String otherUid;
  final String name;
  const FriendButton({required this.otherUid, required this.name});

  @override
  ConsumerState<FriendButton> createState() => FriendButtonState();
}

class FriendButtonState extends ConsumerState<FriendButton> {
  bool _busy = false;
  double _scale = 1.0;

  Future<void> _onTap(bool isFriend, bool pending) async {
    if (_busy) return;
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final social = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(socialProvider.notifier);
    // Putus teman / batalkan lewat helper bersama (dialog + snackbar).
    if (isFriend) {
      setState(() => _busy = true);
      await runUnfriend(context, social, widget.otherUid, widget.name);
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (pending) {
      setState(() => _busy = true);
      await runCancelRequest(context, social, widget.otherUid, widget.name);
      if (mounted) setState(() => _busy = false);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final res = await social.sendFriendRequest(widget.otherUid);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res == 'pending' || res == 'friends') {
      // Pop sukses: membesar sesaat lalu kembali (tanpa controller).
      setState(() => _scale = 1.3);
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      setState(() => _scale = 1.0);
      messenger.showSnackBar(
        SnackBar(content: Text(s.friendRequestSentMutual)),
      );
    } else {
      // Gagal (anon/target tak terdaftar/jaringan) → jangan bilang sukses.
      messenger.showSnackBar(SnackBar(content: Text(s.errGeneric)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final (:isFriend, :pending) = ref.watch(
      socialProvider.select(
        (s) => (
          isFriend: s.isFriend(widget.otherUid),
          pending: s.isPendingFriendRequest(widget.otherUid),
        ),
      ),
    );
    final icon = isFriend
        ? Icons.group_remove_rounded
        : (pending ? Icons.cancel_rounded : Icons.person_add_alt_rounded);
    final tip = isFriend
        ? s.btnUnfriend
        : (pending
              ? s.btnCancelRequest
              : '${s.btnAddFriend} · ${s.sheetFriendDesc}');
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: _busy ? null : () => _onTap(isFriend, pending),
        onTapDown: _busy ? null : (_) => setState(() => _scale = 0.8),
        onTapUp: _busy ? null : (_) => setState(() => _scale = 1.0),
        onTapCancel: () => setState(() => _scale = 1.0),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: SizedBox(
            width: 32,
            height: 32,
            child: _busy
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: AppTheme.primary,
                    ),
                  )
                : Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
