import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../core/cache/media_disk_cache.dart';

/// Paket stiker bawaan "Emoji Art" (S11): Twemoji Twitter (CC-BY 4.0) via
/// CDN, 72px → di-upscale ke 512 PNG saat dikirim (pipeline impor biasa).
/// Tanpa API key / tanpa tabel baru. Tap → bytes → pemanggil proses+kirim.
///
/// Atribusi: Copyright Twitter, Inc. — CC-BY 4.0
/// (https://github.com/twitter/twemoji). Cantumkan di halaman Tentang bila ada.
class TwemojiPack {
  /// Codepoint HEX tunggal (tanpa varian) — nama file CDN pasti cocok.
  static const codes = [
    // Wajah populer.
    '1f600', '1f601', '1f602', '1f603', '1f604', '1f605', '1f606', '1f607',
    '1f608', '1f609', '1f60a', '1f60b', '1f60d', '1f60e', '1f610', '1f612',
    '1f613', '1f614', '1f616', '1f618', '1f61c', '1f61d', '1f61e', '1f620',
    '1f621', '1f622', '1f623', '1f625', '1f627', '1f628', '1f629', '1f62d',
    '1f630', '1f631', '1f632', '1f633', '1f634', '1f635', '1f637', '1f642',
    '1f643', '1f644', '1f910', '1f911', '1f912', '1f913', '1f914', '1f915',
    '1f917', '1f918', '1f919', '1f91a', '1f91b', '1f91c', '1f91d', '1f91e',
    '1f91f', '1f920', '1f921', '1f922', '1f923', '1f924', '1f925', '1f927',
    // Kucing.
    '1f638', '1f639', '1f63a', '1f63b', '1f63c', '1f63d', '1f63e', '1f63f',
    '1f640', '1f641',
    // Hati & simbol.
    '2764', '1f495', '1f496', '1f497', '1f498', '1f499', '1f49a', '1f49b',
    '1f49c', '1f49d', '1f49e', '1f49f', '2b50', '1f31f', '1f525', '1f4a9',
    // Tangan.
    '1f44d', '1f44e', '1f44f', '1f450', '1f64f', '1f64c', '270c', '270a',
  ];

  static String url(String code) =>
      'https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/$code.png';

  static String diskKey(String code) => 'twemoji:$code';
}

/// Grid Emoji Art: sel lazy-load (hanya yang terlihat yang diunduh),
/// cache mem + disk. Tap sel berisi → [onPick] dengan bytes 72px.
/// Atribusi CC-BY 4.0 tampil sebagai caption di bawah grid (lihat pemakai).
class TwemojiGrid extends StatelessWidget {
  final Future<void> Function(Uint8List pngBytes) onPick;
  const TwemojiGrid({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: TwemojiPack.codes.length,
      itemBuilder: (_, i) =>
          _TwemojiCell(code: TwemojiPack.codes[i], onPick: onPick),
    );
  }
}

class _TwemojiCell extends StatefulWidget {
  final String code;
  final Future<void> Function(Uint8List pngBytes) onPick;
  const _TwemojiCell({required this.code, required this.onPick});

  @override
  State<_TwemojiCell> createState() => _TwemojiCellState();
}

class _TwemojiCellState extends State<_TwemojiCell> {
  static final _mem = <String, Uint8List>{};
  Uint8List? _bytes;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final mem = _mem[widget.code];
    if (mem != null) {
      _bytes = mem;
      return;
    }
    final disk =
        MediaDiskCache.instance.readSync(TwemojiPack.diskKey(widget.code));
    if (disk != null && disk.isNotEmpty) {
      _mem[widget.code] = disk;
      _bytes = disk;
      return;
    }
    _fetch();
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final r = await http
          .get(Uri.parse(TwemojiPack.url(widget.code)))
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }
      final bytes = r.bodyBytes;
      if (_mem.length > 200) _mem.remove(_mem.keys.first);
      _mem[widget.code] = bytes;
      unawaited(
        MediaDiskCache.instance.write(TwemojiPack.diskKey(widget.code), bytes),
      );
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (_) {
      // Offline / jaringan gagal → tampilkan ikon retry (bukan sel kosong).
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    return GestureDetector(
      onTap: b == null ? (_failed ? _fetch : null) : () => widget.onPick(b),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(8),
        child: b != null
            ? Image.memory(b, fit: BoxFit.contain)
            : _loading
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _failed
                    ? const Center(
                        child: Icon(
                          Icons.refresh,
                          size: 18,
                          color: Colors.white54,
                        ),
                      )
                    : const SizedBox.shrink(),
      ),
    );
  }
}

/// Sub-tab GIPHY (S9/S10): cari GIF via GIPHY API → tap → dijadikan stiker
/// (webp/gif di-upload apa adanya; GIPHY kirim URL gambar, kita unduh bytes).
///
/// AKTIF hanya bila `--dart-define=GIPHY_API_KEY=...` diisi (lihat AppEnv).
/// Tanpa key → widget ini tak pernah ditampilkan (tab disembunyikan).
class GiphyTab extends StatefulWidget {
  final Future<void> Function(Uint8List bytes, String ext) onPick;
  const GiphyTab({super.key, required this.onPick});

  static bool get enabled => AppEnv.giphyEnabled;

  @override
  State<GiphyTab> createState() => _GiphyTabState();
}

class _GiphyTabState extends State<GiphyTab> {
  final _ctrl = TextEditingController();
  List<String> _urls = const [];
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final uri = Uri.parse(
        'https://api.giphy.com/v1/gifs/search'
        '?api_key=${AppEnv.giphyApiKey}&q=${Uri.encodeQueryComponent(q)}'
        '&limit=24&rating=pg-13&bundle=messaging_non_clips',
      );
      final r = await http.get(uri).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (r.statusCode != 200) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }
      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final data = (json['data'] as List?) ?? const [];
      final urls = <String>[
        for (final g in data)
          if ((g['images']?['fixed_height']?['url'] as String?) != null)
            g['images']['fixed_height']['url'] as String,
      ];
      setState(() {
        _urls = urls;
        _loading = false;
        _failed = urls.isEmpty;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _pick(String url) async {
    try {
      final r = await http.get(Uri.parse(url));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        final ext = url.contains('.webp') ? 'webp' : 'gif';
        await widget.onPick(r.bodyBytes, ext);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            controller: _ctrl,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'GIPHY…',
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _urls.isEmpty
                  ? Center(
                      child: Icon(
                        _failed ? Icons.wifi_off : Icons.gif_box_outlined,
                        color: Colors.white38,
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: _urls.length,
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => _pick(_urls[i]),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _urls[i],
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}
