import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../core/media/native_image.dart';
import '../providers/riverpod/locale_provider.dart';

/// Ukuran kerja stiker (px). Sama seperti impor galeri (512, format Telegram).
const int _kStickerSize = 512;

/// Satu teks overlay di stiker. Posisi fraksional 0..1 terhadap sisi stiker.
class StickerTextItem {
  String text;
  Color color;
  Offset center;
  StickerTextItem({
    required this.text,
    required this.color,
    required this.center,
  });
}

/// Halaman EDIT stiker ala WA: preview besar + tambah teks (drag) + toggle
/// hapus latar + kirim. Dipakai setelah impor galeri, SEBELUM kirim.
/// Tutup dengan bytes final (siap upload) atau null bila batal.
class StickerEditorPage extends ConsumerStatefulWidget {
  /// PNG 512px hasil impor (cut-out bila ML tersedia).
  final Uint8List cutout;

  /// Bytes foto ASLI (untuk varian berlatar saat toggle dimatikan).
  final Uint8List raw;

  const StickerEditorPage({
    super.key,
    required this.cutout,
    required this.raw,
  });

  @override
  ConsumerState<StickerEditorPage> createState() => _StickerEditorPageState();
}

class _StickerEditorPageState extends ConsumerState<StickerEditorPage> {
  /// false = pakai cut-out (default ala WA); true = tampilkan latar asli.
  bool _withBackground = false;
  Uint8List? _square;
  bool _loadingSquare = false;

  final List<StickerTextItem> _texts = [];
  int _selected = -1;
  bool _sending = false;

  Uint8List get _preview =>
      _withBackground ? (_square ?? widget.cutout) : widget.cutout;

  static const _colors = [
    Colors.white,
    Colors.yellow,
    Colors.cyan,
    Colors.pinkAccent,
    Colors.lightGreenAccent,
    Colors.orange,
  ];

  Future<void> _toggleBackground() async {
    if (_withBackground) {
      if (mounted) setState(() => _withBackground = false);
      return;
    }
    if (_square != null) {
      if (mounted) setState(() => _withBackground = true);
      return;
    }
    if (mounted) setState(() => _loadingSquare = true);
    try {
      final b64 = await NativeImage.processStickerPng(
        widget.raw,
        size: _kStickerSize,
        removeBackground: false,
      );
      if (!mounted) return;
      if (b64 == null || b64.isEmpty) return;
      setState(() {
        _square = Uint8List.fromList(
          Uri.parse('data:image/png;base64,$b64').data!.contentAsBytes(),
        );
        _withBackground = true;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSquare = false);
    }
  }

  Future<void> _addOrEditText({int index = -1}) async {
    final s = ref.read(localeProvider).s;
    final ctrl = TextEditingController(
      text: index >= 0 ? _texts[index].text : '',
    );
    var color = index >= 0 ? _texts[index].color : Colors.white;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(s.stickerEditTextTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 60,
                decoration: InputDecoration(hintText: s.stickerEditTextHint),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in _colors)
                    GestureDetector(
                      onTap: () => setDlg(() => color = c),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == c
                                ? AppTheme.primary
                                : Colors.grey,
                            width: color == c ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            if (index >= 0)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('delete'),
                child: Text(s.btnDelete),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(s.btnCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: Text(s.btnSave),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'delete' && index >= 0) {
      setState(() {
        _texts.removeAt(index);
        _selected = -1;
      });
      return;
    }
    if (action != 'save') return;
    final t = ctrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      if (index >= 0) {
        _texts[index].text = t;
        _texts[index].color = color;
      } else {
        _texts.add(
          StickerTextItem(
            text: t,
            color: color,
            center: const Offset(0.5, 0.5),
          ),
        );
        _selected = _texts.length - 1;
      }
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final out = _texts.isEmpty
          ? _preview
          : await renderStickerWithTexts(_preview, _texts);
      if (!mounted) return;
      Navigator.of(context).pop(out);
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    // Preview ~300px; overlay diskala dari koordinat 512.
    const previewPx = 300.0;
    const scale = previewPx / _kStickerSize;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.stickerEditTitle),
        actions: [
          if (_sending)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: _send,
              tooltip: s.stickerEditSend,
              icon: const Icon(Icons.send),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SizedBox(
                width: previewPx,
                height: previewPx,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.memory(_preview, fit: BoxFit.contain),
                    ),
                    for (var i = 0; i < _texts.length; i++)
                      Positioned(
                        left: _texts[i].center.dx * previewPx - 110,
                        top: _texts[i].center.dy * previewPx - 24,
                        child: GestureDetector(
                          onPanUpdate: (d) {
                            setState(() {
                              final c = _texts[i].center +
                                  Offset(
                                    d.delta.dx / previewPx,
                                    d.delta.dy / previewPx,
                                  );
                              _texts[i].center = Offset(
                                c.dx.clamp(0.15, 0.85),
                                c.dy.clamp(0.08, 0.92),
                              );
                              _selected = i;
                            });
                          },
                          onTap: () {
                            setState(() => _selected = i);
                            _addOrEditText(index: i);
                          },
                          child: Container(
                            width: 220,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: _selected == i
                                ? BoxDecoration(
                                    border: Border.all(
                                      color: AppTheme.primary,
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  )
                                : null,
                            child: Text(
                              _texts[i].text,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 44 * scale,
                                fontWeight: FontWeight.w800,
                                color: _texts[i].color,
                                shadows: const [
                                  Shadow(
                                    offset: Offset(1.5, 1.5),
                                    blurRadius: 3,
                                    color: Colors.black87,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addOrEditText(),
                      icon: const Icon(Icons.text_fields, size: 18),
                      label: Text(s.stickerEditAddText),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _loadingSquare ? null : _toggleBackground,
                      icon: _loadingSquare
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _withBackground
                                  ? Icons.person_outline
                                  : Icons.person,
                              size: 18,
                            ),
                      label: Text(
                        _withBackground
                            ? s.stickerEditBgOn
                            : s.stickerEditBgOff,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gabung teks ke PNG stiker (outline hitam + isi warna, tengah).
/// Jalan di main isolate (dart:ui); 512px < 100ms.
Future<Uint8List> renderStickerWithTexts(
  Uint8List stickerPng,
  List<StickerTextItem> texts,
) async {
  final codec = await ui.instantiateImageCodec(stickerPng);
  final frame = await codec.getNextFrame();
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawImage(frame.image, ui.Offset.zero, ui.Paint());
  for (final t in texts) {
    void draw(Color color, {bool stroke = false}) {
      final pb = ui.ParagraphBuilder(
        ui.ParagraphStyle(textAlign: TextAlign.center),
      );
      pb.pushStyle(
        ui.TextStyle(
          fontSize: 44,
          fontWeight: ui.FontWeight.w800,
          foreground: ui.Paint()
            ..color = color
            ..style =
                stroke ? ui.PaintingStyle.stroke : ui.PaintingStyle.fill
            ..strokeWidth = 7
            ..strokeJoin = ui.StrokeJoin.round,
        ),
      );
      pb.addText(t.text);
      final p = pb.build();
      p.layout(const ui.ParagraphConstraints(width: 480));
      canvas.drawParagraph(
        p,
        ui.Offset(
          _kStickerSize / 2 - p.maxIntrinsicWidth / 2,
          (t.center.dy * _kStickerSize - p.height / 2)
              .clamp(0, (_kStickerSize - p.height).toDouble()),
        ),
      );
    }

    draw(const Color(0xFF000000), stroke: true);
    draw(t.color);
  }
  final pic = rec.endRecording();
  final out = await pic.toImage(_kStickerSize, _kStickerSize);
  final data =
      await out.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
