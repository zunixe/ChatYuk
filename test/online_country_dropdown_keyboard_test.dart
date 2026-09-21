import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/config/regions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reproduce online country dropdown with keyboard on 1920x1080 screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final allCountries = kotaByNegara.keys.toList();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            toolbarHeight: 56,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(146),
              child: Container(height: 146, color: Colors.blue),
            ),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: TestMultiDropdown(
                        label: 'Negara',
                        icon: Icons.public,
                        items: allCountries,
                        labels: allCountries,
                        selected: const [],
                        countText: (n) => '$n negara',
                        onChanged: (v) {},
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(height: 48, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: 20,
                  itemBuilder: (_, i) => ListTile(title: Text('User $i')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    print('Tapping Negara field...');
    await tester.tap(find.text('Semua'));
    await tester.pumpAndSettle();

    print('\nSimulating keyboard opening (height = 320dp)...');
    tester.view.viewInsets = const FakeViewPadding(bottom: 880); // 880 / 2.75 = 320dp
    await tester.pumpAndSettle();

    print('\nAfter keyboard:');
    print('TextField found? ${find.byType(TextField).evaluate().isNotEmpty}');
    if (find.byType(TextField).evaluate().isNotEmpty) {
      print('TextField position: ${tester.getTopLeft(find.byType(TextField))}');
      print('TextField size: ${tester.getSize(find.byType(TextField))}');
    }

    // Now test: typing in the text field!
    print('\nTyping into TextField: "Indo"');
    await tester.enterText(find.byType(TextField), 'Indo');
    await tester.pumpAndSettle();

    print('Checking if Indonesia is visible...');
    print('Indonesia found? ${find.text('Indonesia').evaluate().isNotEmpty}');
  });
}

class TestMultiDropdown extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<String> items;
  final List<String> labels;
  final List<String> selected;
  final String Function(int n) countText;
  final ValueChanged<List<String>> onChanged;

  const TestMultiDropdown({
    super.key,
    required this.label,
    required this.icon,
    required this.items,
    required this.labels,
    required this.selected,
    required this.countText,
    required this.onChanged,
  });

  @override
  State<TestMultiDropdown> createState() => _TestMultiDropdownState();
}

class _TestMultiDropdownState extends State<TestMultiDropdown>
    with WidgetsBindingObserver {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  Size _fieldSize = Size.zero;
  double _fieldLeft = 0;

  double get _keyboardH => MediaQueryData.fromView(
        WidgetsBinding.instance.platformDispatcher.views.first,
      ).viewInsets.bottom;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    if (_portal.isShowing && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  String _fieldText() {
    final n = widget.selected.length;
    if (n == 0) return 'Semua';
    if (n == 1) {
      final idx = widget.items
          .indexOf(widget.selected.first)
          .clamp(0, widget.labels.length - 1);
      return widget.labels[idx];
    }
    return widget.countText(n);
  }

  void _togglePanel() {
    if (_portal.isShowing) {
      _portal.hide();
      return;
    }
    final rb = context.findRenderObject() as RenderBox;
    _fieldSize = rb.size;
    _fieldLeft = rb.localToGlobal(Offset.zero).dx;
    _searchCtrl.clear();
    _query = '';
    _portal.show();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayCtx) {
        final mq = MediaQuery.of(overlayCtx);
        final screenW = mq.size.width;

        final visibleBottom = mq.size.height - mq.padding.bottom - _keyboardH;
        final rb = context.findRenderObject() as RenderBox?;
        double fieldTop = 0, fieldBottom = 0, fieldLeft = _fieldLeft;
        if (rb != null && rb.hasSize) {
          final origin = rb.localToGlobal(Offset.zero);
          fieldTop = origin.dy;
          fieldBottom = fieldTop + rb.size.height;
          fieldLeft = origin.dx;
        }
        final availW = screenW - fieldLeft - 8;
        final panelW = (_fieldSize.width + 96).clamp(0.0, availW).toDouble();

        const gap = 4.0;
        const minUseful = 160.0;
        const maxPanel = 340.0;
        final spaceBelow = visibleBottom - fieldBottom - gap;
        final spaceAbove = fieldTop - mq.padding.top - gap;
        final openAbove = spaceBelow < minUseful && spaceAbove > spaceBelow;
        final panelMaxH =
            (openAbove ? spaceAbove : spaceBelow).clamp(minUseful, maxPanel);

        print('\n--- OVERLAY CALC ---');
        print('screenW: $screenW, screenH: ${mq.size.height}, _keyboardH: $_keyboardH');
        print('fieldTop: $fieldTop, fieldBottom: $fieldBottom');
        print('visibleBottom: $visibleBottom');
        print('spaceBelow: $spaceBelow, spaceAbove: $spaceAbove');
        print('openAbove: $openAbove, panelMaxH: $panelMaxH');

        final filtered = [
          for (int i = 0; i < widget.items.length; i++)
            if (_query.isEmpty ||
                widget.labels[i].toLowerCase().contains(_query))
              i,
        ];
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  print('BACKGROUND TAPPED -> HIDING PORTAL');
                  _portal.hide();
                },
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor:
                  openAbove ? Alignment.topLeft : Alignment.bottomLeft,
              followerAnchor:
                  openAbove ? Alignment.bottomLeft : Alignment.topLeft,
              offset: Offset(0, openAbove ? -gap : gap),
              showWhenUnlinked: false,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: panelW,
                  constraints: BoxConstraints(maxHeight: panelMaxH),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            controller: _searchCtrl,
                            autofocus: true,
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 18),
                              hintText: 'Cari negara...',
                            ),
                            onChanged: (q) =>
                                setState(() => _query = q.trim().toLowerCase()),
                          ),
                        ),
                      ),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => ListTile(
                            title: Text(widget.labels[filtered[i]]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: GestureDetector(
          onTap: _togglePanel,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: widget.label,
            ),
            child: Text(_fieldText()),
          ),
        ),
      ),
    );
  }
}
