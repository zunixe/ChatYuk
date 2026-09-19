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
}
