import 'package:shared_preferences/shared_preferences.dart';

class NotificationPrefsService {
  static const _prefix = 'notif_type_';

  static const types = [
    'call',
    'chat',
    'online',
    'timeline',
    'follower',
    'following',
    'friend',
  ];

  static String _key(String type) => '$_prefix$type';

  static Future<bool> isEnabled(String type) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(type)) ?? true;
  }

  static Future<Map<String, bool>> allPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final t in types) t: prefs.getBool(_key(t)) ?? true,
    };
  }

  static Future<void> setEnabled(String type, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(type), enabled);
  }

  static Future<bool> shouldShowForFcmType(String? fcmType) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notif_enabled') ?? true)) return false;
    bool get(String t) => prefs.getBool(_key(t)) ?? true;
    switch (fcmType) {
      case 'call':
      case 'call_ended':
      case 'call_canceled':
      case 'active_call':
        return get('call');
      case 'message':
        return get('chat');
      case 'online':
        return get('online');
      case 'timeline_post':
      case 'room':
        return get('timeline');
      case 'follow':
        return get('follower');
      case 'subscribe':
        return get('following');
      case 'friend_request':
        return get('friend');
      default:
        return true;
    }
  }
}
