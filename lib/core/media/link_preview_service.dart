import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../cache/media_disk_cache.dart';

/// Metadata link preview (kartu saat kirim link) — mirip Telegram WebPage.
class LinkPreviewData {
  final String url;
  final String title;
  final String description;
  final String image;
  final String siteName;

  /// True bila di-cache/fetch SUDAH FINAL (bukan hasil fallback sementara).
  final bool ok;

  const LinkPreviewData({
    required this.url,
    this.title = '',
    this.description = '',
    this.image = '',
    this.siteName = '',
    this.ok = true,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'description': description,
        'image': image,
        'siteName': siteName,
        'ok': ok,
      };

  static LinkPreviewData fromJson(Map<String, dynamic> j) => LinkPreviewData(
        url: '${j['url'] ?? ''}',
        title: '${j['title'] ?? ''}',
        description: '${j['description'] ?? ''}',
        image: '${j['image'] ?? ''}',
        siteName: '${j['siteName'] ?? ''}',
        ok: j['ok'] != false,
      );
}

/// Service link preview: RAM → DISK (persist lintas sesi) → network (device
/// lalu Edge Function bila tersedia).
///
/// Telegram menyimpan webPage PER PESAN + fetch di server. Padanan ChatYuk:
/// cache URL di disk (persist) + simpan ke pesan (lihat MessageModel.linkPreview)
/// + opsi fetch via Edge Function (LP-F).
/// Semaphore sederhana: batasi fetch link preview paralel. Tanpa ini, chat
/// padat URL (mis. balasan AI penuh tautan unik) memicu ledakan HTTP GET
/// serentak saat dibuka. Pola sama `_Semaphore` di chat_stream_session.
class _LpSemaphore {
  _LpSemaphore(this.max);
  final int max;
  int _count = 0;
  final _waiters = <Completer<void>>[];
  Future<void> acquire() async {
    if (_count < max) {
      _count++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void release() {
    _count--;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
      _count++;
    }
  }

  Future<T> run<T>(Future<T> Function() fn) async {
    await acquire();
    try {
      return await fn();
    } finally {
      release();
    }
  }
}

class LinkPreviewService {
  LinkPreviewService._();
  static final instance = LinkPreviewService._();

  /// Batas fetch jaringan PARALEL (device + edge function). 3 cukup untuk
  /// mengisi viewport tanpa membebani radio/HTTP pool saat chat padat URL.
  static const int _maxConcurrentFetches = 3;
  final _fetchGate = _LpSemaphore(_maxConcurrentFetches);

  /// Cache RAM link preview. Dinaikkan 50 → 200 (LRU) supaya scroll bolak-balik
  /// di percakapan panjang (banyak URL) tidak memicu fetch ulang.
  static const int _maxEntries = 200;
  final _cache = <String, LinkPreviewData>{};
  final _inflight = <String, Future<LinkPreviewData?>>{};

  /// Injektor fetch SERVER-SIDE (LP-F) — di-wire di main.dart ke Edge Function.
  /// Null → langsung pakai fetch device. Return null bila function gagal →
  /// fallback ke fetch device.
  static Future<LinkPreviewData?> Function(String url)? serverFetch;

  /// Hitung panggilan fetch JARINGAN (device/function) — untuk verifikasi
  /// "scroll balik tak fetch ulang" (target: 1× per URL per sesi).
  @visibleForTesting
  int networkFetchCount = 0;

  /// Hitung berapa kali URL yang diekstrak DILEWATI (bukan kandidat preview,
  /// mis. tautan gambar/aset) — instrumen Fase 0 untuk mengukur berapa banyak
  /// fetch yang berhasil dihindari pada chat padat URL (khas balasan AI).
  @visibleForTesting
  int urlSkipCount = 0;

  @visibleForTesting
  int get cacheLength => _cache.length;

  @visibleForTesting
  void resetForTest() {
    _cache.clear();
    _inflight.clear();
    networkFetchCount = 0;
    urlSkipCount = 0;
  }

  void _put(String url, LinkPreviewData data) {
    if (_cache.length >= _maxEntries && !_cache.containsKey(url)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = data;
  }

  static final _urlRegex = RegExp(r'https?:\/\/[^\s]+', caseSensitive: false);

  /// Ambil preview dari RAM SINKRON (bila sudah ada) — dipakai widget supaya
  /// frame pertama tanpa spinner saat scroll balik (LP-A). Null bila belum ada.
  LinkPreviewData? peek(String url) => _cache[url];

  String? extractUrl(String text) {
    final m = _urlRegex.firstMatch(text);
    final url = m?.group(0);
    if (url == null) return null;
    if (!isPreviewCandidate(url)) {
      urlSkipCount++;
      return null;
    }
    return url;
  }

  /// Pola URL yang BUKAN kandidat kartu preview: tautan gambar/aset langsung
  /// (bukan halaman web ber-metadata). Chat yang dipenuhi balasan AI sering
  /// menyisipkan URL gambar (pollinations/mermaid.ink/ekstensi media) — fetch
  /// HTML-nya sia-sia (og:title kosong) dan hanya membuang jaringan/CPU.
  static final _skipHostRe = RegExp(
    r'(^|\.)((pollinations\.ai)|(mermaid\.ink)|(quickchart\.io)|(placehold\.co))$',
    caseSensitive: false,
  );
  static final _imageExtRe = RegExp(
    r'\.(png|jpe?g|gif|webp|svg|bmp|ico|avif)(\?|#|$)',
    caseSensitive: false,
  );

  /// True bila [url] layak dijadikan kartu preview (halaman web, bukan aset).
  /// Murni + static supaya bisa di-unit-test tanpa network.
  static bool isPreviewCandidate(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    if (_skipHostRe.hasMatch(host)) return false;
    // Path berakhiran ekstensi gambar → aset, bukan halaman.
    if (_imageExtRe.hasMatch(uri.path.toLowerCase())) return false;
    return true;
  }

  String _diskKey(String url) => 'linkpreview:$url';

  /// Ambil preview: RAM → disk → network. Dedupe in-flight (banyak bubble
  /// dengan URL sama tak fetch berkali-kali).
  Future<LinkPreviewData?> fetch(String url) async {
    final mem = _cache[url];
    if (mem != null) return mem;

    final running = _inflight[url];
    if (running != null) return running;

    final fut = _fetchInner(url);
    _inflight[url] = fut;
    try {
      return await fut;
    } finally {
      _inflight.remove(url);
    }
  }

  Future<LinkPreviewData?> _fetchInner(String url) async {
    // DISK dulu (persist lintas sesi) — nol network bila sudah ada.
    try {
      final disk = await MediaDiskCache.instance.read(_diskKey(url));
      if (disk != null && disk.isNotEmpty) {
        final d = LinkPreviewData.fromJson(
          jsonDecode(utf8.decode(disk)) as Map<String, dynamic>,
        );
        _put(url, d);
        return d;
      }
    } catch (_) {}

    // NETWORK: server-side (LP-F) dulu, lalu fallback device.
    // Semaphore: batasi fetch paralel supaya chat padat URL (khas balasan AI)
    // tidak memicu ledakan HTTP serentak saat dibuka.
    final data = await _fetchGate.run(() => _fetchNetwork(url));
    if (data != null) {
      _put(url, data);
      // Simpan ke disk (fire-and-forget) — preview kecil (JSON).
      unawaited(_persist(url, data));
    }
    return data;
  }

  Future<void> _persist(String url, LinkPreviewData d) async {
    try {
      await MediaDiskCache.instance.write(
        _diskKey(url),
        Uint8List.fromList(utf8.encode(jsonEncode(d.toJson()))),
      );
    } catch (_) {}
  }

  Future<LinkPreviewData?> _fetchNetwork(String url) async {
    // URUTAN (terukur 2026-10-13): DEVICE dulu. Dari IP rumah, YouTube dkk
    // BERHASIL (og:title+image); dari IP server Supabase justru **429 / bot
    // challenge** (datacenter IP dibatasi). Jadi device = jalur utama.
    networkFetchCount++;
    LinkPreviewData? device;
    try {
      final res = await http
          .get(Uri.parse(url), headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9,id;q=0.8',
          })
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final d = parseHtml(url, res.body);
        // Ada metadata nyata (bukan cuma host)? → pakai.
        if (d.image.isNotEmpty || d.description.isNotEmpty) return d;
        device = d;
      }
    } catch (_) {}
    // FALLBACK (LP-F): Edge Function — untuk kasus device gagal/DNS-block.
    final srv = serverFetch;
    if (srv != null) {
      try {
        final d = await srv(url).timeout(const Duration(seconds: 8));
        if (d != null && (d.image.isNotEmpty || d.description.isNotEmpty)) {
          return d;
        }
      } catch (_) {}
    }
    // Hasil device apa adanya (judul=host bila semua gagal) — jangan
    // sembunyikan kartu total.
    if (device != null) return device;
    final host = Uri.tryParse(url)?.host ?? url;
    return LinkPreviewData(url: url, title: host, siteName: host, ok: false);
  }

  /// Parse HTML → [LinkPreviewData] (og:* → <title> → host). Dipisah supaya
  /// bisa diuji tanpa network & dipakai Edge Function payload.
  static LinkPreviewData parseHtml(String url, String html) {
    String getMeta(String prop) {
      final r1 = RegExp(
        '<meta[^>]+property=["\']$prop["\'][^>]+content=["\']([^"\']+)["\']',
        caseSensitive: false,
      );
      final m1 = r1.firstMatch(html);
      if (m1 != null) return m1.group(1)!.trim();
      final r2 = RegExp(
        '<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']$prop["\']',
        caseSensitive: false,
      );
      final m2 = r2.firstMatch(html);
      return m2?.group(1)?.trim() ?? '';
    }

    String getName(String name) {
      final r = RegExp(
        '<meta[^>]+name=["\']$name["\'][^>]+content=["\']([^"\']+)["\']',
        caseSensitive: false,
      );
      return r.firstMatch(html)?.group(1)?.trim() ?? '';
    }

    String title = getMeta('og:title');
    if (title.isEmpty) {
      final t = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false)
          .firstMatch(html);
      title = t?.group(1)?.trim() ?? '';
    }
    final host = Uri.tryParse(url)?.host ?? url;
    if (title.isEmpty) title = host;
    final desc = getMeta('og:description').isNotEmpty
        ? getMeta('og:description')
        : getName('description');
    final img = getMeta('og:image');
    final site = getMeta('og:site_name');
    return LinkPreviewData(
      url: url,
      title: title,
      description: desc,
      image: img,
      siteName: site.isNotEmpty ? site : host,
    );
  }
}
