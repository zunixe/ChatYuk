import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Helper subscribe/unsubscribe FCM Topic untuk fan-out 1→N ringan.
/// Dipakai online, timeline, room. Cache subs di prefs biar tidak re-subscribe.
class PushTopicService {
  PushTopicService._();
  static final PushTopicService instance = PushTopicService._();

  static const _prefPrefix = 'topic_sub_';

  Future<void> subscribe(String topic) async {
    // Jangan subscribe topic diri sendiri (mis. online-$myUid) — cegah self-notif
    final myUid = Supabase.instance.client.auth.currentUser?.id;
    if (myUid != null && topic == 'online-$myUid') return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('$_prefPrefix$topic') == true) return;
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      await prefs.setBool('$_prefPrefix$topic', true);
    } catch (_) {}
  }

  Future<void> unsubscribe(String topic) async {
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefPrefix$topic');
    } catch (_) {}
  }

  Future<void> subscribeOnline(String uid) => subscribe('online-$uid');
  Future<void> unsubscribeOnline(String uid) => unsubscribe('online-$uid');

  Future<void> subscribeTimeline() => subscribe('timeline-all');
  Future<void> subscribeRoom(String roomId) => subscribe('room-$roomId');
  Future<void> unsubscribeRoom(String roomId) => unsubscribe('room-$roomId');
}
