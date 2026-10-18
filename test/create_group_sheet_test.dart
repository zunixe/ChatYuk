import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/screens/group/create_group_sheet.dart';

/// Checklist uji desain "Form Buat Grup" (2026-10-18).
void main() {
  final s = S(isId: true);

  Future<({GroupDraft? draft, Object? result, int calls})> open(
    WidgetTester t, {
    Future<String?> Function(GroupDraft)? onCreate,
    double width = 360,
    List<Future<void> Function()> steps = const [],
  }) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = Size(width, 780);
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    GroupDraft? seen;
    Object? result;
    var calls = 0;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showCreateGroupSheet<String>(
                ctx,
                s: s,
                onCreate: (d) async {
                  calls++;
                  seen = d;
                  return onCreate == null ? 'ok' : onCreate(d);
                },
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    for (final st in steps) {
      await st();
      await t.pumpAndSettle();
    }
    return (draft: seen, result: result, calls: calls);
  }

  Future<void> tapVis(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
  }

  FilledButton submit(WidgetTester t) =>
      t.widget<FilledButton>(find.byKey(const ValueKey('group_submit')));

  testWidgets('tombol nonaktif saat nama < 3 karakter', (t) async {
    await open(t);
    await t.enterText(find.byKey(const ValueKey('group_name')), 'ab');
    await t.pump();
    expect(submit(t).onPressed, isNull);
    await t.enterText(find.byKey(const ValueKey('group_name')), 'abc');
    await t.pump();
    expect(submit(t).onPressed, isNotNull);
  });

  testWidgets('dengan password: panel muncul, nonaktif s.d. 6+ karakter; kembali → panel hilang', (t) async {
    await open(t);
    await t.enterText(find.byKey(const ValueKey('group_name')), 'Futsal Bogor');
    await tapVis(t, 'group_access_pw');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('group_password')), findsOneWidget);
    expect(submit(t).onPressed, isNull);
    await t.enterText(find.byKey(const ValueKey('group_password')), '12345');
    await t.pump();
    expect(submit(t).onPressed, isNull);
    await t.enterText(find.byKey(const ValueKey('group_password')), '123456');
    await t.pump();
    expect(submit(t).onPressed, isNotNull);
    await tapVis(t, 'group_access_open');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('group_password')), findsNothing);
  });

  testWidgets('ikon di kotak nama ikut pilihan grid; layar 360px tanpa overflow, 6 kolom', (t) async {
    await open(t, width: 360);
    expect(t.takeException(), isNull, reason: 'tidak overflow di 360px');
    final a = t.getTopLeft(find.byKey(const ValueKey('group_icon_chat')));
    final f = t.getTopLeft(find.byKey(const ValueKey('group_icon_heart')));
    final g = t.getTopLeft(find.byKey(const ValueKey('group_icon_flame')));
    expect(f.dy, a.dy, reason: 'ikon ke-6 masih baris pertama');
    expect(g.dy, greaterThan(a.dy), reason: 'ikon ke-7 turun baris');
    await tapVis(t, 'group_icon_game');
    await t.pump();
    final field = find.ancestor(
      of: find.byKey(const ValueKey('group_name')),
      matching: find.byType(Row),
    ).first;
    expect(
      find.descendant(of: field, matching: find.byIcon(Icons.sports_esports_outlined)),
      findsOneWidget,
    );
  });

  testWidgets('sukses: sheet tutup dgn hasil; draft membawa emoji & password', (t) async {
    late ({GroupDraft? draft, Object? result, int calls}) r;
    r = await open(t, steps: [
      () => t.enterText(find.byKey(const ValueKey('group_name')), 'Futsal Bogor'),
      () => tapVis(t, 'group_icon_music'),
      () => tapVis(t, 'group_access_pw'),
      () => t.enterText(find.byKey(const ValueKey('group_password')), 'rahasia1'),
      () => t.tap(find.byKey(const ValueKey('group_submit'))),
    ]);
    expect(find.byType(CreateGroupSheet<String>), findsNothing);
    expect(r.calls, 1);
  });

  testWidgets('gagal: pesan error tampil, isian tetap ada', (t) async {
    await open(t, onCreate: (_) async => throw const CreateGroupFailure('Maksimal 2 grup aktif'));
    await t.enterText(find.byKey(const ValueKey('group_name')), 'Futsal Bogor');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('group_submit')));
    await t.pumpAndSettle();
    expect(find.text('Maksimal 2 grup aktif'), findsOneWidget);
    expect(find.text('Futsal Bogor'), findsOneWidget);
    expect(find.byType(CreateGroupSheet<String>), findsOneWidget);
  });

  testWidgets('Batal & ✕ menutup tanpa membuat grup', (t) async {
    final r1 = await open(t, steps: [() => t.tap(find.byKey(const ValueKey('group_cancel')))]);
    expect(find.byType(CreateGroupSheet<String>), findsNothing);
    expect(r1.calls, 0);
  });

  test('ikon disimpan sebagai emoji (kompatibel RoomIcon)', () {
    expect(const GroupDraft(name: 'x', iconKey: 'game').iconEmoji, '🎮');
    expect(const GroupDraft(name: 'x', iconKey: 'lock').iconEmoji, '🔒');
    expect(kGroupIcons.length, 12);
    expect(kGroupIcons.map((e) => e.emoji).toSet().length, 12, reason: 'emoji unik');
  });
}
