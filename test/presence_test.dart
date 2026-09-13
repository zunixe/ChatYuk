import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/chat_service.dart';

String _ago(int minutes) => DateTime.now()
    .toUtc()
    .subtract(Duration(minutes: minutes))
    .toIso8601String();

void main() {
  group('ChatService.effectiveStatusOf', () {
    test('null status dianggap offline', () {
      expect(ChatService.effectiveStatusOf(null, _ago(0)), 'offline');
    });

    test('offline/invisible selalu offline walau last_seen segar', () {
      expect(ChatService.effectiveStatusOf('offline', _ago(0)), 'offline');
      expect(ChatService.effectiveStatusOf('invisible', _ago(0)), 'offline');
    });

    test('online segar tetap online', () {
      expect(ChatService.effectiveStatusOf('online', _ago(0)), 'online');
      expect(ChatService.effectiveStatusOf('online', _ago(29)), 'online');
    });

    test('online basi >30 menit dianggap offline', () {
      expect(ChatService.effectiveStatusOf('online', _ago(31)), 'offline');
      expect(ChatService.effectiveStatusOf('online', _ago(120)), 'offline');
    });

    test('idle segar tetap idle, basi jadi offline', () {
      expect(ChatService.effectiveStatusOf('idle', _ago(5)), 'idle');
      expect(ChatService.effectiveStatusOf('idle', _ago(60)), 'offline');
    });

    test('last_seen tak-terparse dianggap offline', () {
      expect(ChatService.effectiveStatusOf('online', null), 'offline');
      expect(ChatService.effectiveStatusOf('online', 'bukan-tanggal'), 'offline');
    });

    test('idle + last_seen basi → offline', () {
      expect(ChatService.effectiveStatusOf('idle', _ago(31)), 'offline');
    });

    test('idle + last_seen null → offline', () {
      expect(ChatService.effectiveStatusOf('idle', null), 'offline');
    });

    test('invisible + last_seen baru tetap offline', () {
      expect(ChatService.effectiveStatusOf('invisible', _ago(0)), 'offline');
    });

    test('status tidak dikenal + last_seen baru → kembalikan apa adanya', () {
      expect(ChatService.effectiveStatusOf('busy', _ago(1)), 'busy');
    });
  });
}
