import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;

import '../../config/strings.dart';
import '../../config/strings_admin.dart';
import '../../config/strings_docs.dart';
import '../../config/theme.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../admin_attribution_tab.dart';
import '../admin_chat_list_screen.dart';
import '../admin_contact_tab.dart';
import '../admin_deleted_tab.dart';
import '../admin_devices_tab.dart';
import '../admin_docs_tab.dart';
import '../admin_dummy_tab.dart';
import '../admin_global_setting_tab.dart';
import '../admin_kyc_tab.dart';
import '../admin_marketing_tab.dart';
import '../admin_moderation_tab.dart';
import '../admin_room_list_screen.dart';
import '../admin_room_sessions_tab.dart';
import '../admin_story_tab.dart';
import '../admin_timeline_tab.dart';
import '../admin_withdraw_tab.dart';
import 'admin_overview_page.dart';
import 'admin_point_page.dart';

/// Kategori di halaman utama panel admin. Urutan enum = urutan section.
enum AdminMenuCategory { stats, monitor, users, coin, system }

/// Identitas tiap menu panel admin — SATU sumber untuk label, ikon, kategori
/// dan isi (semua lewat `switch` lengkap di bawah). Dulu label & body ditulis
/// sebagai dua daftar terpisah dan bisa bergeser (insiden: "Timeline"
/// menampilkan Dokumentasi). Dengan enum ini mustahil tidak sinkron.
/// Urutan enum = urutan ikon dalam kategorinya.
enum AdminMenu {
  globalSetting,
  overview,
  point,
  withdraw,
  chatMonitor,
  roomMonitor,
  roomSessions,
  dummy,
  contact,
  device,
  deleted,
  attribution,
  story,
  timeline,
  docs,
  moderation,
  kyc,
  marketing,
}

String adminMenuLabel(AdminMenu m, S s) => switch (m) {
      AdminMenu.globalSetting => s.adminGlobalSettingTab,
      AdminMenu.overview => s.adminOverview,
      AdminMenu.point => s.adminPointTab,
      AdminMenu.withdraw => s.adminWithdrawTab,
      AdminMenu.chatMonitor => s.adminChatMonitor,
      AdminMenu.roomMonitor => s.adminRoomMonitor,
      AdminMenu.roomSessions => s.adminRoomSessionsTab,
      AdminMenu.dummy => s.adminDummyTab,
      AdminMenu.contact => s.adminContactTab,
      AdminMenu.device => s.adminDeviceTab,
      AdminMenu.deleted => s.adminDeletedTab,
      AdminMenu.attribution => s.adminAttributionTab,
      AdminMenu.story => s.adminStoryTab,
      AdminMenu.timeline => s.adminTimelineTab,
      AdminMenu.docs => s.adminDocsTab,
      AdminMenu.moderation => s.adminModerationTab,
      AdminMenu.kyc => s.adminKycTab,
      AdminMenu.marketing => s.adminMarketingTab,
    };

IconData adminMenuIcon(AdminMenu m) => switch (m) {
      AdminMenu.globalSetting => Icons.tune_rounded,
      AdminMenu.overview => Icons.dashboard_rounded,
      AdminMenu.point => Icons.monetization_on_rounded,
      AdminMenu.withdraw => Icons.account_balance_wallet_rounded,
      AdminMenu.chatMonitor => Icons.forum_rounded,
      AdminMenu.roomMonitor => Icons.groups_rounded,
      AdminMenu.roomSessions => Icons.event_available_rounded,
      AdminMenu.dummy => Icons.smart_toy_rounded,
      AdminMenu.contact => Icons.contact_mail_rounded,
      AdminMenu.device => Icons.phone_android_rounded,
      AdminMenu.deleted => Icons.delete_sweep_rounded,
      AdminMenu.attribution => Icons.insights_rounded,
      AdminMenu.story => Icons.amp_stories_rounded,
      AdminMenu.timeline => Icons.timeline_rounded,
      AdminMenu.docs => Icons.menu_book_rounded,
      AdminMenu.moderation => Icons.gavel_rounded,
      AdminMenu.kyc => Icons.badge_rounded,
      AdminMenu.marketing => Icons.campaign_rounded,
    };

AdminMenuCategory adminMenuCategory(AdminMenu m) => switch (m) {
      AdminMenu.overview => AdminMenuCategory.stats,
      AdminMenu.attribution => AdminMenuCategory.stats,
      AdminMenu.timeline => AdminMenuCategory.stats,
      AdminMenu.chatMonitor => AdminMenuCategory.monitor,
      AdminMenu.roomMonitor => AdminMenuCategory.monitor,
      AdminMenu.roomSessions => AdminMenuCategory.monitor,
      AdminMenu.story => AdminMenuCategory.monitor,
      AdminMenu.moderation => AdminMenuCategory.monitor,
      AdminMenu.dummy => AdminMenuCategory.users,
      AdminMenu.contact => AdminMenuCategory.users,
      AdminMenu.device => AdminMenuCategory.users,
      AdminMenu.deleted => AdminMenuCategory.users,
      AdminMenu.point => AdminMenuCategory.coin,
      AdminMenu.withdraw => AdminMenuCategory.coin,
      AdminMenu.kyc => AdminMenuCategory.coin,
      AdminMenu.globalSetting => AdminMenuCategory.system,
      AdminMenu.marketing => AdminMenuCategory.system,
      AdminMenu.docs => AdminMenuCategory.system,
    };

/// Urutan tampil dalam satu kategori (bukan urutan enum, supaya menu utama
/// tiap kategori ada di depan).
const Map<AdminMenuCategory, List<AdminMenu>> adminMenuLayout = {
  AdminMenuCategory.stats: [
    AdminMenu.overview,
    AdminMenu.attribution,
    AdminMenu.timeline,
  ],
  AdminMenuCategory.monitor: [
    AdminMenu.chatMonitor,
    AdminMenu.roomMonitor,
    AdminMenu.roomSessions,
    AdminMenu.story,
    AdminMenu.moderation,
  ],
  AdminMenuCategory.users: [
    AdminMenu.dummy,
    AdminMenu.contact,
    AdminMenu.device,
    AdminMenu.deleted,
  ],
  AdminMenuCategory.coin: [
    AdminMenu.point,
    AdminMenu.withdraw,
    AdminMenu.kyc,
  ],
  AdminMenuCategory.system: [
    AdminMenu.globalSetting,
    AdminMenu.marketing,
    AdminMenu.docs,
  ],
};

String adminCategoryLabel(AdminMenuCategory c, S s) => switch (c) {
      AdminMenuCategory.stats => s.adminCatStats,
      AdminMenuCategory.monitor => s.adminCatMonitor,
      AdminMenuCategory.users => s.adminCatUsers,
      AdminMenuCategory.coin => s.adminCatCoin,
      AdminMenuCategory.system => s.adminCatSystem,
    };

Color adminCategoryColor(AdminMenuCategory c) => switch (c) {
      AdminMenuCategory.stats => AppTheme.primary,
      AdminMenuCategory.monitor => Colors.teal,
      AdminMenuCategory.users => Colors.deepOrange,
      AdminMenuCategory.coin => Colors.amber.shade800,
      AdminMenuCategory.system => Colors.blueGrey,
    };

/// Isi halaman tiap menu. Dibangun hanya saat menu dibuka (lazy).
Widget adminMenuBody(AdminMenu m) => switch (m) {
      AdminMenu.globalSetting => const AdminGlobalSettingTab(),
      AdminMenu.overview => const AdminOverviewPage(),
      AdminMenu.point => const AdminPointPage(),
      AdminMenu.withdraw => const AdminWithdrawTab(),
      AdminMenu.chatMonitor => const AdminChatListScreen(),
      AdminMenu.roomMonitor => const AdminRoomListScreen(),
      AdminMenu.roomSessions => const AdminRoomSessionsTab(),
      AdminMenu.dummy => const AdminDummyTab(),
      AdminMenu.contact => const AdminContactTab(),
      AdminMenu.device => const AdminDevicesTab(),
      AdminMenu.deleted => const AdminDeletedTab(),
      AdminMenu.attribution => const AdminAttributionTab(),
      AdminMenu.story => const AdminStoryTab(),
      AdminMenu.timeline => const AdminTimelineTab(),
      AdminMenu.docs => const AdminDocsTab(),
      AdminMenu.moderation => const AdminModerationTab(),
      AdminMenu.kyc => const AdminKycTab(),
      AdminMenu.marketing => const AdminMarketingTab(),
    };

/// Halaman satu menu admin (route sendiri, dengan tombol back).
class AdminMenuPage extends ConsumerWidget {
  final AdminMenu menu;
  const AdminMenuPage({super.key, required this.menu});

  static Future<void> open(BuildContext context, AdminMenu menu) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AdminMenuPage(menu: menu)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(title: Text(adminMenuLabel(menu, s))),
      body: adminMenuBody(menu),
    );
  }
}
