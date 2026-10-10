import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/nav_guard.dart';
import '../../../models/message_model.dart';
import '../../../providers/riverpod/auth_provider.dart';
import '../../../providers/riverpod/chat_provider.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../widgets/chat_info_snack.dart';
import '../../../widgets/person_avatar.dart';
import '../../../widgets/social_counts_line.dart';
import '../../../widgets/chat_route.dart';
import '../../user_info_screen.dart';
import 'room_widgets.dart';

/// Sheet aksi user di room chat: buka profil, chat pribadi, blokir, laporkan.
///
/// Murni tampilan + navigasi. Callback [onSheetClosed] dipanggil saat sheet
/// ditutup (untuk mereset guard `_sheetOpen` di layar induk); [onReport]
/// membuka dialog lapor.
void showRoomUserActionSheet(
  BuildContext context, {
  required MessageModel msg,
  required AuthNotifier auth,
  required VoidCallback onSheetClosed,
  required void Function(String reportedId, String reportedName) onReport,
}) {
  final s = ProviderScope.containerOf(context, listen: false)
      .read(localeProvider).s;

  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                // Tutup sheet lalu buka halaman profil user.
                final navKey = navKeyUser(msg.senderId);
                if (!tryClaimNav(navKey)) return;
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UserInfoScreen(
                      userId: msg.senderId,
                      fallbackName: msg.senderName,
                    ),
                  ),
                ).then((_) => releaseNav(navKey));
              },
              child: Row(
                children: [
                  // PersonAvatar = standar yang sama persis dengan Pengguna
                  // Online (foto + latar tint + ring warna gender).
                  PersonAvatar(
                    uid: msg.senderId,
                    name: msg.senderName,
                    gender: msg.senderGender,
                    size: 40,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(msg.senderName, style: AppText.bodyStrong),
                        Text(
                          msg.senderGender == 'male'
                              ? s.genderMale
                              : msg.senderGender == 'female'
                              ? s.genderFemale
                              : s.genderOther,
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        // Jumlah follower & teman (gaya IG) — di bawah
                        // gender, hanya bila ada.
                        SocialCountsLine(uid: msg.senderId),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: RoomSheetIcon(
              icon: Icons.chat_rounded,
              color: AppTheme.primary,
            ),
            title: Text(
              s.titlePrivateChat,
              style: TextStyle(color: AppTheme.textPrimary),
            ),
            onTap: () async {
              final chat = ProviderScope.containerOf(context, listen: false)
                  .read(chatProvider.notifier);
              final locale = ProviderScope.containerOf(context, listen: false)
                  .read(localeProvider);
              // User sudah dihapus (akun tidak ada) → jangan buka chat,
              // policy RLS menolak insert chat dengan participant yang hilang.
              final active = await chat.isUserActive(msg.senderId);
              if (!context.mounted) return;
              if (!active) {
                showChatSnack(context, locale.s.errUserNotFound);
                return;
              }
              // Pakai context screen (bukan context sheet) — context sheet
              // sudah deactivated setelah pop, sehingga Navigator.push
              // gagal diam-diam kalau startPrivateChat > animasi pop.
              final navigator = Navigator.of(context);
              final screenContext = context;
              navigator.pop();
              try {
                final chatId = await chat.startPrivateChat(
                  myUid: auth.uid!,
                  otherUid: msg.senderId,
                  myName: auth.profile!.nickname,
                  otherName: msg.senderName,
                  myGender: auth.profile!.gender,
                  otherGender: msg.senderGender,
                  myAge: auth.profile!.age,
                );
                if (screenContext.mounted) {
                  final navKey = navKeyChat(chatId);
                  if (tryClaimNav(navKey)) {
                    Navigator.of(screenContext).push(
                      chatRoute(
                        chatId: chatId,
                        otherName: msg.senderName,
                        otherUid: msg.senderId,
                        otherGender: msg.senderGender,
                        otherRegistered: msg.isRegistered,
                      ),
                    ).then((_) => releaseNav(navKey));
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  final s2 = ProviderScope.containerOf(context, listen: false)
                      .read(localeProvider).s;
                  showChatSnack(context, s2.errGeneric);
                }
              }
            },
          ),
          ListTile(
            leading: const RoomSheetIcon(
              icon: Icons.block_rounded,
              color: AppTheme.danger,
            ),
            title: Text(
              s.btnBlock,
              style: const TextStyle(color: AppTheme.danger),
            ),
            onTap: () async {
              Navigator.of(context).pop();
              await ProviderScope.containerOf(context, listen: false)
                  .read(chatProvider.notifier)
                  .blockUser(auth.uid!, msg.senderId);
              if (context.mounted) {
                showChatSnack(context, s.blockSuccess);
              }
            },
          ),
          ListTile(
            leading: const RoomSheetIcon(
              icon: Icons.flag_rounded,
              color: Colors.orange,
            ),
            title: Text(
              s.btnReport,
              style: const TextStyle(color: Colors.orange),
            ),
            onTap: () {
              Navigator.of(context).pop();
              onReport(msg.senderId, msg.senderName);
            },
          ),
        ],
      ),
    ),
  ).whenComplete(onSheetClosed);
}
