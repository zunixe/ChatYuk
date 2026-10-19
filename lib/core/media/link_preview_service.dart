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

  /// Ikon situs (favicon) — `<link rel=…icon>` atau `/favicon.ico` domain.
  /// Ditampilkan di ujung kanan baris domain (ala WhatsApp).
  final String icon;

  /// True bila di-cache/fetch SUDAH FINAL (bukan hasil fallback sementara).
  final bool ok;

  const LinkPreviewData({
    required this.url,
    this.title = '',
    this.description = '',
    this.image = '',
    this.siteName = '',
    this.icon = '',
    this.ok = true,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'description': description,
        'image': image,
        'siteName': siteName,
        'icon': icon,
        'ok': ok,
      };

  static LinkPreviewData fromJson(Map<String, dynamic> j) => LinkPreviewData(
        url: '${j['url'] ?? ''}',
        title: '${j['title'] ?? ''}',
        description: '${j['description'] ?? ''}',
        image: '${j['image'] ?? ''}',
        siteName: '${j['siteName'] ?? ''}',
        icon: '${j['icon'] ?? ''}',
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

  /// Cache RAM rasio ASLI foto preview (`w/h`) per URL gambar.
  ///
  /// PERF: kartu link butuh rasio untuk menghitung lebarnya. Dulu diambil dari
  /// bytes di disk via `MediaDiskCache.readSync` — itu **I/O disk sinkron di
  /// UI thread seukuran file gambar**, dieksekusi tiap bubble link di-mount
  /// (scroll chat lama jadi tersendat). Sekarang: rasio dihitung SEKALI saat
  /// bytes didapat (di `LinkPreviewImage`, off build) lalu disimpan di sini →
  /// pembaca berikutnya murni RAM, nol disk.
  final _aspectCache = <String, double>{};

  /// Rasio tersimpan untuk [imageUrl] (RAM saja, tanpa I/O). null = belum tahu.
  double? peekAspect(String imageUrl) =>
      imageUrl.isEmpty ? null : _aspectCache[imageUrl];

  /// Simpan rasio hasil decode. Bounded FIFO sederhana (pola sama `_cache`).
  void putAspect(String imageUrl, double aspect) {
    if (imageUrl.isEmpty || !aspect.isFinite || aspect <= 0) return;
    if (_aspectCache.length >= _maxEntries &&
        !_aspectCache.containsKey(imageUrl)) {
      _aspectCache.remove(_aspectCache.keys.first);
    }
    _aspectCache[imageUrl] = aspect;
  }

  @visibleForTesting
  void seedAspectForTest(String imageUrl, double aspect) =>
      putAspect(imageUrl, aspect);

  /// Test-only: isi cache RAM tanpa IO (untuk uji layout kartu).
  @visibleForTesting
  void seedForTest(String url, LinkPreviewData data) => _put(url, data);

  @visibleForTesting
  void resetForTest() {
    _cache.clear();
    _inflight.clear();
    _aspectCache.clear();
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

  /// URL TANPA skema (hasil copy-paste umum: `www.tokopedia.com/x`,
  /// `shopee.co.id/y`). Hanya TLD yang dikenal supaya kalimat seperti
  /// "file.txt" / "v1.2.3" TIDAK dianggap link.
  static final _schemeLessRe = RegExp(
    r'(?<![-@\w.])'
    // Bukan bagian dari skema lain (ftp://, magnet://, …) — jangan jadikan
    // domain di dalamnya sebagai link web tanpa skema.
    r'(?<!:\/\/)'
    r'(?:www\.)?'
    r'(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+'
    r'(?:com|net|org|id|io|co|me|app|dev|xyz|site|shop|store|link|ly|be|tv|'
    r'info|biz|online|tech|club|pro|edu|gov|ac|sch|web|top|live|news|blog|'
    r'page|cloud|ai|my|sg|us|uk|jp|kr|de|fr|au|ca|in|cn|hk|tw|th|vn|ph)'
    r'(?::\d+)?'
    r'(?:\/[^\s]*)?',
    caseSensitive: false,
  );

  /// Buang tanda baca penutup kalimat di ujung URL (titik/koma/kurung).
  static String _trimUrlTail(String u) {
    var out = u;
    const tail = '.,!?;:)]}\'"';
    while (out.isNotEmpty && tail.contains(out[out.length - 1])) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }

  /// Entri cache (disk/RAM) layak dipakai TANPA re-fetch?
  /// Hanya hasil FINAL (`ok`) dengan judul nyata. Entri gagal/fallback
  /// (ok:false / title kosong) TIDAK boleh "membeku" selamanya — dulu
  /// `_fetchInner` mengembalikan cache disk apa adanya, jadi URL yang pernah
  /// gagal tak pernah punya kartu.
  static bool isUsableCachedPreview(LinkPreviewData d) =>
      d.ok && d.title.trim().isNotEmpty;

  /// Ambil preview dari RAM SINKRON (bila sudah ada) — dipakai widget supaya
  /// frame pertama tanpa spinner saat scroll balik (LP-A). Null bila belum ada.
  LinkPreviewData? peek(String url) => _cache[url];

  String? extractUrl(String text) {
    var url = _urlRegex.firstMatch(text)?.group(0);
    // Copy-paste sering TANPA skema → normalisasi ke https:// untuk fetch
    // (teks pesan tetap seperti aslinya).
    if (url == null) {
      final m = _schemeLessRe.firstMatch(text);
      if (m == null) return null;
      url = 'https://${m.group(0)}';
    }
    url = _trimUrlTail(url);
    // Normalisasi SKEMA ke huruf kecil: copy-paste kadang "Https://…" →
    // cache key & fetch harus konsisten (hindari entri ganda).
    final sm = RegExp(r'^(https?)', caseSensitive: false).firstMatch(url);
    if (sm != null) {
      url = url.replaceRange(0, sm.end, sm.group(1)!.toLowerCase());
    }
    if (url.isEmpty) return null;
    if (!isPreviewCandidate(url)) {
      urlSkipCount++;
      return null;
    }
    return url;
  }

  /// true bila [text] hanya berisi URL (boleh huruf besar/kecil, boleh tanpa
  /// skema) + spasi di sekitarnya — dipakai untuk menyembunyikan teks URL di
  /// bawah kartu preview. TIDAK boleh pakai `text.replaceAll(url, '')` karena
  /// [extractUrl] menormalkan skema ke huruf kecil ("Https://" → "https://")
  /// sehingga replaceAll gagal → URL muncul lagi di bubble.
  bool isUrlOnly(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    final m = _urlRegex.firstMatch(t) ?? _schemeLessRe.firstMatch(t);
    if (m == null) return false;
    return t.substring(0, m.start).trim().isEmpty &&
        t.substring(m.end).trim().isEmpty;
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

  // v3 (2026-10-18): + ikon situs. v2: fetch kini memakai UA pengambil-preview (lihat
  // [_fetchNetwork]) + dekode entitas HTML. Preview lama di disk (mis. link
  // pendek Shopee yang tersimpan sebagai BERANDA Shopee) diabaikan → diambil
  // ulang sekali dengan benar.
  String _diskKey(String url) => 'linkpreview3:$url';

  /// UA pengambil preview ala WhatsApp. Terukur 2026-10-18 (curl, IP rumah):
  /// link pendek Shopee hanya memberi metadata PRODUK ke UA ini (UA browser
  /// = halaman pengalih JS ber-metadata BERANDA); TikTok & Instagram kosong
  /// untuk UA browser tapi lengkap untuk UA ini; YouTube/Kompas/GitHub/
  /// Tokopedia sama baiknya.
  static const String previewUserAgent = 'WhatsApp/2.23.20.0 A';
  static const String browserUserAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120 Mobile Safari/537.36';

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
        // Gagal/fallback → JANGAN dipakai; lanjut fetch ulang.
        if (isUsableCachedPreview(d)) {
          _put(url, d);
          return d;
        }
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
    // UA pengambil-preview DULU (metadata halaman tujuan, mis. produk), lalu
    // UA browser sebagai cadangan bila situs menolak bot.
    for (final ua in const [previewUserAgent, browserUserAgent]) {
      try {
        final res = await http
            .get(Uri.parse(url), headers: {
              'User-Agent': ua,
              'Accept-Language': 'id,en-US;q=0.9,en;q=0.8',
            })
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final d = parseHtml(url, res.body);
          // Ada metadata nyata (bukan cuma host)? → pakai.
          if (d.image.isNotEmpty || d.description.isNotEmpty) return d;
          device ??= d;
        }
      } catch (_) {}
    }
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
    final icon = findIcon(url, html);
    return LinkPreviewData(
      url: url,
      title: decodeHtmlEntities(title),
      description: decodeHtmlEntities(desc),
      // URL gambar juga bisa ber-`&amp;` (query string) → wajib didekode.
      image: decodeHtmlEntities(img),
      siteName: decodeHtmlEntities(site.isNotEmpty ? site : host),
      icon: icon,
    );
  }

  static final _linkTagRe = RegExp(r'<link\b[^>]*>', caseSensitive: false);
  static final _relRe = RegExp(r'''rel\s*=\s*["']([^"']+)["']''', caseSensitive: false);
  static final _hrefRe = RegExp(r'''href\s*=\s*["']([^"']+)["']''', caseSensitive: false);

  /// URL ikon situs: `apple-touch-icon` → `icon`/`shortcut icon` (bukan
  /// `mask-icon` SVG) → cadangan `https://<host>/favicon.ico` (pola
  /// WhatsApp; terukur ada di Shopee/YouTube/Kompas/GitHub). Relatif
  /// diselesaikan terhadap URL halaman. Murni & testable.
  static String findIcon(String pageUrl, String html) {
    final base = Uri.tryParse(pageUrl);
    if (base == null || base.host.isEmpty) return '';
    String? touch;
    String? plain;
    for (final m in _linkTagRe.allMatches(html)) {
      final tag = m.group(0)!;
      final rel = _relRe.firstMatch(tag)?.group(1)?.toLowerCase() ?? '';
      final href = _hrefRe.firstMatch(tag)?.group(1)?.trim() ?? '';
      if (href.isEmpty || rel.contains('mask-icon')) continue;
      if (rel.contains('apple-touch-icon')) {
        touch ??= href;
      } else if (rel.split(RegExp(r'\s+')).contains('icon')) {
        plain ??= href;
      }
    }
    final pick = touch ?? plain;
    if (pick != null) {
      final r = Uri.tryParse(decodeHtmlEntities(pick));
      if (r != null) return base.resolveUri(r).toString();
    }
    return '${base.scheme.isEmpty ? 'https' : base.scheme}://${base.host}/favicon.ico';
  }

  static const Map<String, String> _namedEntities = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'ndash': '–',
    'mdash': '—',
    'hellip': '…',
    'bull': '•',
    'middot': '·',
    'laquo': '«',
    'raquo': '»',
    'copy': '©',
    'reg': '®',
    'trade': '™',
  };
  static final _entityRe = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

  /// Dekode entitas HTML (`&amp;`, `&#064;`, `&#x2022;`, …) di metadata.
  /// Dulu judul tampil mentah "Terlengkap &amp; Terpercaya". Murni & testable.
  static String decodeHtmlEntities(String s) {
    if (!s.contains('&')) return s;
    return s.replaceAllMapped(_entityRe, (m) {
      final e = m.group(1)!;
      int? code;
      if (e.startsWith('#x') || e.startsWith('#X')) {
        code = int.tryParse(e.substring(2), radix: 16);
      } else if (e.startsWith('#')) {
        code = int.tryParse(e.substring(1));
      } else {
        return _namedEntities[e] ?? m.group(0)!;
      }
      if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
      return String.fromCharCode(code);
    });
  }
}
