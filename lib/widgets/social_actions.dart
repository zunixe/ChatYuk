import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/locale_provider.dart';
import '../providers/social_provider.dart';

/// Aksi sosial bersama (putus teman / batalkan permintaan teman) — satu
/// sumber kebenaran supaya dialog & snackbar konsisten di semua layar
/// (profil, leaderboard, daftar online, daftar chat).
///
/// Catatan: "putus teman" = `unfollow`, karena server (`unfollow_user`)
/// menghapus `follows` DAN `friend_requests` kedua arah → benar-benar putus.

/// Dialog konfirmasi putus pertemanan. Return true bila user menekan
/// "Putus Teman".
Future<bool> confirmUnfriend(BuildContext context, S s, String name) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.unfriendConfirmTitle),
      content: Text(s.unfriendConfirmBody(name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s.btnCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            s.btnUnfriend,
            style: const TextStyle(color: AppTheme.danger),
          ),
        ),
      ],
    ),
  );
  return res == true;
}

/// Dialog konfirmasi batalkan permintaan teman yang sudah dikirim.
Future<bool> confirmCancelRequest(
  BuildContext context,
  S s,
  String name,
) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.cancelRequestConfirmTitle),
      content: Text(s.cancelRequestConfirmBody(name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s.btnCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(s.btnCancelRequest),
        ),
      ],
    ),
  );
  return res == true;
}

/// Putus pertemanan ([targetUid]) via `SocialProvider.unfollow`.
Future<bool> doUnfriend(SocialProvider sp, String targetUid) =>
    sp.unfollow(targetUid);

/// Batalkan permintaan teman terkirim ke [targetUid]. Ambil `id` dari outbox
/// (RPC `my_social_status` tidak mengembalikan id), lalu cancel.
Future<bool> cancelFriendRequestFor(
  SocialProvider sp,
  String targetUid,
) async {
  try {
    final outbox = await sp.friendRequestOutbox();
    final req = outbox.firstWhere(
      (e) => '${e['uid']}' == targetUid,
      orElse: () => const {},
    );
    final id = (req['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return false;
    return await sp.cancelFriendRequest(id, targetUid: targetUid);
  } catch (_) {
    return false;
  }
}

/// Aksi putus teman lengkap: konfirmasi → unfollow → snackbar. Return true
/// bila berhasil. Dipakai oleh tombol di leaderboard/online/daftar chat.
Future<bool> runUnfriend(
  BuildContext context,
  SocialProvider sp,
  String targetUid,
  String name,
) async {
  final s = context.read<LocaleProvider>().s;
  if (!await confirmUnfriend(context, s, name)) return false;
  final ok = await doUnfriend(sp, targetUid);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? s.unfriendDone : s.errGeneric)),
    );
  }
  return ok;
}

/// Aksi batalkan permintaan lengkap: konfirmasi → cancel → snackbar.
Future<bool> runCancelRequest(
  BuildContext context,
  SocialProvider sp,
  String targetUid,
  String name,
) async {
  final s = context.read<LocaleProvider>().s;
  if (!await confirmCancelRequest(context, s, name)) return false;
  final ok = await cancelFriendRequestFor(sp, targetUid);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? s.cancelRequestDone : s.errGeneric)),
    );
  }
  return ok;
}
