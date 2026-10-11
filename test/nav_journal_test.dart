import 'dart:io';

import 'package:chatyuk/core/nav_journal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavJournal.redact', () {
    test('samarkan id chat/room/user', () {
      expect(
        NavJournal.redact('push private-chat:abc123 depth=2'),
        'push private-chat depth=2',
      );
      expect(
        NavJournal.redact('pop room:xyz-99 depth=1'),
        'pop room depth=1',
      );
      expect(
        NavJournal.redact('back veto selection=3'),
        'back veto selection=3',
      );
    });
  });

  group('NavJournal.log', () {
    test('ring dibatasi + tulis file (direktori test)', () async {
      final dir = await Directory.systemTemp.createTemp('navjournal');
      NavJournal.testSetDir(dir);
      for (var i = 0; i < 310; i++) {
        NavJournal.log('push private-chat:u$i depth=1');
      }
      expect(NavJournal.ringForTest.length, 300);
      // Tunggu flush async ke file.
      for (var i = 0; i < 50; i++) {
        final f = File('${dir.path}/nav_journal.txt');
        if (await f.exists()) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final content = await File('${dir.path}/nav_journal.txt').readAsString();
      expect(content, contains('push private-chat depth=1'));
      expect(content, isNot(contains('private-chat:u1 ')));
      // Tulis serial (rantai Future) mungkin masih berjalan → beri waktu,
      // lalu hapus toleran (dir bisa terisi lagi di antara cek & delete).
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (var i = 0; i < 5; i++) {
        try {
          await dir.delete(recursive: true);
          break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    });
  });

  group('tulis serial', () {
    test('log beruntun: semua mendarat berurutan (anti-interleave)', () async {
      final dir = await Directory.systemTemp.createTemp('navjournal2');
      NavJournal.testSetDir(dir);
      for (var i = 0; i < 50; i++) {
        NavJournal.log('evt $i');
      }
      var content = '';
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final f = File('${dir.path}/nav_journal.txt');
        if (await f.exists()) {
          content = await f.readAsString();
          if ('evt 49'.allMatches(content).isNotEmpty) break;
        }
      }
      final lines =
          content.split('\n').where((l) => l.contains('evt ')).toList();
      expect(lines.length, 50);
      var prev = -1;
      for (final l in lines) {
        final n = int.parse(l.split('evt ').last.trim());
        expect(n, greaterThan(prev));
        prev = n;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (var i = 0; i < 5; i++) {
        try {
          await dir.delete(recursive: true);
          break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    });
  });

  group('BackVetoGuard', () {    test('veto basi pertama NO-OP (jangan escape), berulang baru escape', () {
      final g = BackVetoGuard();
      expect(g.shouldEscape('pcl:clean'), isFalse);
      expect(g.shouldEscape('pcl:clean'), isTrue);
    });
    test('reset mengulang hitungan dari nol', () {
      final g = BackVetoGuard();
      expect(g.shouldEscape('pcl:clean'), isFalse);
      g.reset();
      expect(g.shouldEscape('pcl:clean'), isFalse);
      expect(g.shouldEscape('pcl:clean'), isTrue);
    });
  });
}
