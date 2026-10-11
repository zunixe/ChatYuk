import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LinkPreviewData {
  final String url;
  final String title;
  final String description;
  final String image;
  final String siteName;
  LinkPreviewData({required this.url, this.title = '', this.description = '', this.image = '', this.siteName = ''});
}

class LinkPreviewService {
  LinkPreviewService._();
  static final instance = LinkPreviewService._();

  // BOUNDED (R6): preview per URL unik. Dulu tumbuh tanpa batas seumur
  // proses (tiap link baru di chat menambah entri). Cap FIFO 50 — link lama
  // dibuang; bila dibuka lagi cukup fetch ulang (5s, murah). LRU tak perlu:
  // preview kecil & tak sering dibuka ulang.
  static const int _maxEntries = 50;
  final _cache = <String, LinkPreviewData>{};

  /// Jumlah entri cache (uji batas).
  @visibleForTesting
  int get cacheLength => _cache.length;

  void _put(String url, LinkPreviewData data) {
    if (_cache.length >= _maxEntries && !_cache.containsKey(url)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = data;
  }

  static final _urlRegex = RegExp(r'https?:\/\/[^\s]+', caseSensitive: false);

  String? extractUrl(String text) {
    final m = _urlRegex.firstMatch(text);
    return m?.group(0);
  }

  Future<LinkPreviewData?> fetch(String url) async {
    if (_cache.containsKey(url)) return _cache[url];
    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
      final html = res.body;
      String getMeta(String prop) {
        final r1 = RegExp('<meta[^>]+property=["\']$prop["\'][^>]+content=["\']([^"\']+)["\']', caseSensitive: false);
        final m1 = r1.firstMatch(html);
        if (m1 != null) return m1.group(1)!.trim();
        final r2 = RegExp('<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']$prop["\']', caseSensitive: false);
        final m2 = r2.firstMatch(html);
        return m2?.group(1)?.trim() ?? '';
      }
      String getName(String name) {
        final r = RegExp('<meta[^>]+name=["\']$name["\'][^>]+content=["\']([^"\']+)["\']', caseSensitive: false);
        return r.firstMatch(html)?.group(1)?.trim() ?? '';
      }
      String title = getMeta('og:title');
      if (title.isEmpty) {
        final t = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(html);
        title = t?.group(1)?.trim() ?? '';
      }
      if (title.isEmpty) title = Uri.tryParse(url)?.host ?? url;
      final desc = getMeta('og:description').isNotEmpty ? getMeta('og:description') : getName('description');
      final img = getMeta('og:image');
      final site = getMeta('og:site_name');
      final data = LinkPreviewData(url: url, title: title, description: desc, image: img, siteName: site.isNotEmpty ? site : Uri.tryParse(url)?.host ?? '');
      _put(url, data);
      return data;
    } catch (_) {
      final host = Uri.tryParse(url)?.host ?? url;
      final fallback = LinkPreviewData(url: url, title: host, siteName: host);
      _put(url, fallback);
      return fallback;
    }
  }
}
