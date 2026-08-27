import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../services/notification_prefs_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  Map<String, bool> _prefs = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await NotificationPrefsService.allPrefs();
    if (mounted) setState(() { _prefs = m; _loading = false; });
  }

  Future<void> _toggle(String type, bool v) async {
    await NotificationPrefsService.setEnabled(type, v);
    if (mounted) setState(() => _prefs[type] = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final masterOn = context.watch<AuthProvider>().notificationsEnabled;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(s.notifDetailTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final items = [
      _Item(s.notifTypeCall, s.notifTypeCallDesc, Icons.call_outlined, 'call'),
      _Item(s.notifTypeChat, s.notifTypeChatDesc, Icons.chat_bubble_outline, 'chat'),
      _Item(s.notifTypeOnline, s.notifTypeOnlineDesc, Icons.circle_outlined, 'online'),
      _Item(s.notifTypeTimeline, s.notifTypeTimelineDesc, Icons.view_list_outlined, 'timeline'),
      _Item(s.notifTypeFollower, s.notifTypeFollowerDesc, Icons.person_add_outlined, 'follower'),
      _Item(s.notifTypeFollowing, s.notifTypeFollowingDesc, Icons.favorite_border, 'following'),
      _Item(s.notifTypeFriend, s.notifTypeFriendDesc, Icons.people_outline, 'friend'),
    ];
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(title: Text(s.notifDetailTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(s.notifDetailHint, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
          if (!masterOn) ...[SizedBox(height: 8), Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)), child: Row(children: [Icon(Icons.notifications_off_outlined, size: 16, color: Colors.orange.shade700), SizedBox(width: 8), Expanded(child: Text(s.notifEnabledDesc, style: AppText.bodySmall.copyWith(color: Colors.orange.shade700)))]))],
          SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  _Tile(
                    icon: items[i].icon,
                    title: items[i].title,
                    subtitle: items[i].desc,
                    value: masterOn ? (_prefs[items[i].key] ?? true) : false,
                    onChanged: masterOn ? (v) => _toggle(items[i].key, v) : null,
                  ),
                  if (i != items.length - 1) Divider(height: 1, indent: 52),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Item {
  final String title, desc;
  final IconData icon;
  final String key;
  _Item(this.title, this.desc, this.icon, this.key);
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(icon, color: AppTheme.primary, size: 18),
      ),
      title: Text(title, style: AppText.bodyStrong),
      subtitle: Text(subtitle, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
      trailing: Switch(value: value, onChanged: onChanged, activeThumbColor: AppTheme.primary),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}
