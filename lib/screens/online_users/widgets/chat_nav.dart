import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/nav_guard.dart';
import '../../../models/user_model.dart';
import '../../../providers/riverpod/auth_provider.dart';
import '../../../providers/riverpod/call_provider.dart';
import '../../../providers/riverpod/chat_provider.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../private_chat_screen.dart';

/// Buka private chat dengan [user] dari daftar Online — deterministik (tanpa
/// network saat push), prefetch pesan sebelum push, guard double-push, dan
/// validasi/upsert tertunda setelah layar terbuka.
///
/// [onBeforeNav] dipanggil SEBELUM navigasi (mis. membuang overlay unread yang
/// transparannya tidak boleh nyangkut jadi penghalang di halaman chat).
Future<void> startPrivateChatFromOnline(
  BuildContext context,
  UserModel user, {
  required VoidCallback onBeforeNav,
}) async {
  // Buang bubble unread overlay (kalau ada) SEBELUM navigasi — overlay
  // transparannya tak boleh ikut ke halaman chat / nyangkut jadi penghalang.
  onBeforeNav();
  final auth = ProviderScope.containerOf(context, listen: false)
      .read(authProvider.notifier);
  final chat = ProviderScope.containerOf(context, listen: false)
      .read(chatProvider.notifier);
  final s = ProviderScope.containerOf(context, listen: false)
      .read(localeProvider).s;
  final myUid = auth.uid;
  final myName = auth.profile?.nickname ?? 'Anon';
  if (myUid == null || user.uid == myUid) return;

  // Hitung chatId lokal (deterministik, tanpa network) → navigate instant.
  final ids = [myUid, user.uid]..sort();
  final chatId = '${ids[0]}_${ids[1]}';
  // Guard double-push: tap 2× cepat saat transisi push menumpuk 2 route
  // identik → 1× back tampak "tidak bereaksi" (scroll jalan). Lihat
  // docs/PERFORMANCE.md §18.
  final navKey = navKeyChat(chatId);
  if (!tryClaimNav(navKey)) return;
  // Prefetch pesan ke memori SEBELUM push (di-await) → frame pertama chat
  // langsung terisi (peekMessages hit), bukan layar kosong dulu.
  await ProviderScope.containerOf(context, listen: false)
      .read(chatProvider.notifier)
      .prefetchPrivateChat(chatId);
  if (!context.mounted) {
    releaseNav(navKey);
    return;
  }
  Navigator.push(
    context,
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      settings: RouteSettings(name: privateChatRoute(chatId)),
      pageBuilder: (_, __, ___) => PrivateChatScreen(
        chatId: chatId,
        otherName: user.nickname,
        otherUid: user.uid,
        otherGender: user.gender,
        otherCountry: user.country,
        otherCity: user.city,
        otherAge: user.age,
        otherRegistered: user.isRegistered,
      ),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        // Slide + Fade (halus, tutupi celah raster saat slide full-screen).
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
    // WAJIB release klaim nav saat route di-pop (aturan nav_guard §18).
    // Dulu jalur ini LUPA `.then(releaseNav)` → klaim `navKeyChat` nyangkut
    // → tap kartu user YANG SAMA diulang tak nyahut dalam window 2 dtk.
  ).then((_) => releaseNav(navKey));

  // Validasi + upsert di background setelah screen sudah terbuka — DITUNDA
  // ~400ms supaya 2 RPC (isUserActive + startPrivateChat) tidak jatuh di
  // frame transisi buka chat ("klik card Online terasa berat"). Sebelumnya
  // jalan langsung setelah push → ikut frame animasi.
  unawaited(Future<void>.delayed(const Duration(milliseconds: 400), () async {
    if (!context.mounted) return;
    try {
      final active = await chat.isUserActive(user.uid);
      if (!active) {
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.errUserNotFound)));
        }
        return;
      }
      await chat.startPrivateChat(
        myUid: myUid,
        otherUid: user.uid,
        myName: myName,
        otherName: user.nickname,
        myGender: auth.profile?.gender ?? '',
        otherGender: user.gender,
        myCountry: auth.profile?.country ?? '',
        otherCountry: user.country,
        myAge: auth.profile?.age ?? 0,
        otherAge: user.age,
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('23503') ||
          msg.contains('foreign key') ||
          msg.contains('42501')) {
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(s.errUserNotFound)));
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
      }
    }
  })); // akhir unawaited(delayed)
}
