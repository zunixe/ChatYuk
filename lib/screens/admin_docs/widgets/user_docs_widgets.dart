import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import '../../../config/theme.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../providers/riverpod/theme_provider.dart';
import '../../admin_panel/widgets/panel_card.dart';
import '../../../config/strings_docs.dart' show SDocsX;

/// Daftar dokumentasi PENGGUNA — semua fitur ChatYuk dengan bahasa sederhana.
class UserDocsList extends ConsumerWidget {
  final String query;
  const UserDocsList({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeProvider);
    final s = ref.watch(localeProvider).s;
    final sections = <_DocSection>[
      _DocSection(s.docsUserAuthTitle, s.docsUserAuthBody, Icons.login, Colors.green),
      _DocSection(s.docsUserOnboardTitle, s.docsUserOnboardBody, Icons.flag_outlined, Colors.lightGreen),
      _DocSection(s.docsUserOnlineTitle, s.docsUserOnlineBody, Icons.online_prediction, Colors.red),
      _DocSection(s.docsUserPrivateTitle, s.docsUserPrivateBody, Icons.chat_bubble_outline, Colors.blue),
      _DocSection(s.docsUserOrganizeTitle, s.docsUserOrganizeBody, Icons.inventory_2_outlined, Colors.blueGrey),
      _DocSection(s.docsUserPhotoPayTitle, s.docsUserPhotoPayBody, Icons.lock_outline, Colors.pink),
      _DocSection(s.docsUserRoomsTitle, s.docsUserRoomsBody, Icons.meeting_room_outlined, Colors.teal),
      _DocSection(s.docsUserRoomLiveTitle, s.docsUserRoomLiveBody, Icons.mic_none_outlined, Colors.deepPurple),
      _DocSection(s.docsUserGroupTitle, s.docsUserGroupBody, Icons.group_outlined, Colors.indigo),
      _DocSection(s.docsUserCallTitle, s.docsUserCallBody, Icons.call_outlined, Colors.green),
      _DocSection(s.docsUserStoryTitle, s.docsUserStoryBody, Icons.photo_camera_outlined, Colors.purple),
      _DocSection(s.docsUserTimelineTitle, s.docsUserTimelineBody, Icons.dynamic_feed_outlined, Colors.deepOrange),
      _DocSection(s.docsUserNearbyTitle, s.docsUserNearbyBody, Icons.near_me_outlined, Colors.orange),
      _DocSection(s.docsUserSocialTitle, s.docsUserSocialBody, Icons.diversity_3_outlined, Colors.brown),
      _DocSection(s.docsUserMissionsTitle, s.docsUserMissionsBody, Icons.emoji_events_outlined, Colors.amber),
      _DocSection(s.docsUserTopupTitle, s.docsUserTopupBody, Icons.monetization_on_outlined, Colors.yellow),
      _DocSection(s.docsUserCoinFxTitle, s.docsUserCoinFxBody, Icons.auto_awesome_outlined, Colors.yellowAccent),
      _DocSection(s.docsUserProfileTitle, s.docsUserProfileBody, Icons.person_outline, Colors.blueGrey),
      _DocSection(s.docsUserPrivacyTitle, s.docsUserPrivacyBody, Icons.shield_outlined, Colors.cyan),
      _DocSection(s.docsUserSettingsTitle, s.docsUserSettingsBody, Icons.settings_outlined, Colors.grey),
      _DocSection(s.docsUserDonateTitle, s.docsUserDonateBody, Icons.favorite_outline, Colors.pinkAccent),
      _DocSection(s.docsUserHelpTitle, s.docsUserHelpBody, Icons.help_outline, Colors.lightBlue),
    ];
    final q = query.trim().toLowerCase();
    final shown = q.isEmpty
        ? sections
        : sections
            .where((e) =>
                e.title.toLowerCase().contains(q) ||
                e.body.toLowerCase().contains(q))
            .toList();
    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            s.adminDocsEmpty,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          PanelCard(
            shown[i].title,
            shown[i].icon,
            shown[i].color,
            [
              Text(
                shown[i].body,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          if (i < shown.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _DocSection {
  final String title;
  final String body;
  final IconData icon;
  final Color color;
  const _DocSection(this.title, this.body, this.icon, this.color);
}
