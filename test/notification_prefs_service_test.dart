import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/services/notification_prefs_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shouldShowForFcmType', () {
    test('default: mention mengikuti chat (true)', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await NotificationPrefsService.shouldShowForFcmType('mention'),
          isTrue);
      expect(await NotificationPrefsService.shouldShowForFcmType('message'),
          isTrue);
    });

    test('master switch off → semua false', () async {
      SharedPreferences.setMockInitialValues({'notif_enabled': false});
      expect(await NotificationPrefsService.shouldShowForFcmType('mention'),
          isFalse);
      expect(await NotificationPrefsService.shouldShowForFcmType('message'),
          isFalse);
    });

    test('chat off → mention juga false', () async {
      SharedPreferences.setMockInitialValues({'notif_type_chat': false});
      expect(await NotificationPrefsService.shouldShowForFcmType('mention'),
          isFalse);
      expect(await NotificationPrefsService.shouldShowForFcmType('message'),
          isFalse);
    });

    test('chat on → mention true', () async {
      SharedPreferences.setMockInitialValues({'notif_type_chat': true});
      expect(await NotificationPrefsService.shouldShowForFcmType('mention'),
          isTrue);
    });

    test('tipe tak dikenal → default true', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
          await NotificationPrefsService.shouldShowForFcmType('halo_baru'),
          isTrue);
    });

    test('timeline_post & timeline mengikuti toggle timeline', () async {
      SharedPreferences.setMockInitialValues({'notif_type_timeline': false});
      expect(await NotificationPrefsService.shouldShowForFcmType('timeline_post'),
          isFalse);
      expect(await NotificationPrefsService.shouldShowForFcmType('timeline'),
          isFalse);
    });

    test('timeline on → keduanya true', () async {
      SharedPreferences.setMockInitialValues({'notif_type_timeline': true});
      expect(await NotificationPrefsService.shouldShowForFcmType('timeline_post'),
          isTrue);
      expect(await NotificationPrefsService.shouldShowForFcmType('timeline'),
          isTrue);
    });
  });

  group('mute per-chat', () {
    test('set → isChatMuted true, id lain false', () async {
      SharedPreferences.setMockInitialValues({});
      await NotificationPrefsService.setChatMuted('r1', true);
      expect(await NotificationPrefsService.isChatMuted('r1'), isTrue);
      expect(await NotificationPrefsService.isChatMuted('r2'), isFalse);
    });

    test('unmute → isChatMuted false', () async {
      SharedPreferences.setMockInitialValues({});
      await NotificationPrefsService.setChatMuted('r1', true);
      await NotificationPrefsService.setChatMuted('r1', false);
      expect(await NotificationPrefsService.isChatMuted('r1'), isFalse);
    });

    test('chatId kosong tidak pernah termute', () async {
      SharedPreferences.setMockInitialValues({});
      await NotificationPrefsService.setChatMuted('', true);
      expect(await NotificationPrefsService.isChatMuted(''), isFalse);
    });
  });

  group('isOnlineHidden (gate notif "X online")', () {
    test('uid ada di daftar sembunyi akun aktif → true', () async {
      SharedPreferences.setMockInitialValues({
        'current_uid': 'me',
        'hidden_online_me': ['u1', 'u2'],
      });
      expect(await NotificationPrefsService.isOnlineHidden('u1'), isTrue);
    });

    test('uid TIDAK di daftar → false (notif tetap muncul)', () async {
      SharedPreferences.setMockInitialValues({
        'current_uid': 'me',
        'hidden_online_me': ['u1'],
      });
      expect(await NotificationPrefsService.isOnlineHidden('u9'), isFalse);
    });

    test('daftar milik akun LAIN tidak bocor', () async {
      SharedPreferences.setMockInitialValues({
        'current_uid': 'me',
        'hidden_online_other': ['u1'],
      });
      expect(await NotificationPrefsService.isOnlineHidden('u1'), isFalse);
    });

    test('tanpa sesi (current_uid kosong) → false', () async {
      SharedPreferences.setMockInitialValues({
        'hidden_online_me': ['u1'],
      });
      expect(await NotificationPrefsService.isOnlineHidden('u1'), isFalse);
    });

    test('uid kosong → false', () async {
      SharedPreferences.setMockInitialValues({'current_uid': 'me'});
      expect(await NotificationPrefsService.isOnlineHidden(''), isFalse);
    });
  });
}
