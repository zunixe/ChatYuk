import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Helper subscribe/unsubscribe FCM Topic untuk fan-out 1→N ringan.
/// Dipakai online, timeline, room. Cache subs di prefs biar tidak re-subscribe.
class PushTopicService {
  final SupabaseClient _sb;

  /// Client opsional supaya test menyuntik client palsu (produksi: singleton).
  PushTopicService._([SupabaseClient? sb])
      : _sb = sb ?? Supabase.instance.client;

  static PushTopicService instance = PushTopicService._();

  /// Test-only: bangun service dengan client palsu / ganti singleton.
  @visibleForTesting
  factory PushTopicService.forTest(SupabaseClient sb) =>
      PushTopicService._(sb);

  @visibleForTesting
  static void overrideInstance(PushTopicService s) => instance = s;

  @visibleForTesting
  static void restoreInstance() => instance = PushTopicService._();

  static const _prefPrefix = 'topic_sub_';

  Future<void> subscribe(String topic) async {
    // Jangan subscribe topic diri sendiri (mis. online-$myUid) — cegah self-notif
    final myUid = _sb.auth.currentUser?.id;
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
