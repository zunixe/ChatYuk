import 'dart:async';

import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils.dart';

/// Atribusi sumber user — "user datang dari link mana".
///
/// Sumber data (Android only):
///   - Play Install Referrer: string mentah `utm_source=...&utm_campaign=...`
///     yang ditempel platform iklan pada link Play Store (FB/IG/TikTok) atau
///     otomatis oleh Google Ads (gclid).
///   - Deep link `chatyuk://referral?u=<uid>` (share antar-user) — di-set oleh
///     jalur referral yang sudah ada; service ini hanya membacanya sebagai
///     fallback source.
///
/// Alur: baca SEKALI saat first-launch → simpan mentah ke SharedPreferences
/// (tahan offline & dibaca berkali-kali) → [attributionParams] dipakai
/// DeviceInfoService.syncToServer() untuk mengisi kolom user_devices.
///
/// Idempotent & murah: setelah nilai tersimpan, panggilan berikutnya tidak
/// menyentuh plugin native.
class AttributionService {
  AttributionService._();
  static final AttributionService instance = AttributionService._();

  // ── SharedPreferences keys ──
  static const _kReferrerRaw = 'attr_referrer_raw';
  static const _kSource = 'attr_source';
  static const _kUtmSource = 'attr_utm_source';
  static const _kUtmMedium = 'attr_utm_medium';
  static const _kUtmCampaign = 'attr_utm_campaign';
  static const _kUtmContent = 'attr_utm_content';
  static const _kReadAt = 'attr_read_at';

  bool _done = false;

  /// Baca Install Referrer sekali (first-launch). Fire-and-forget, tidak
  /// boleh menggagalkan bootstrap. Aman dipanggil berkali-kali.
  Future<void> readOnce() async {
    if (_done) return;
    _done = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Sudah pernah dibaca & tersimpan → tidak perlu sentuh native lagi.
      // (Install Referrer hanya valid ~90 hari & tidak berubah; sekali cukup.)
      final existing = prefs.getString(_kReadAt);
      if (existing != null && existing.isNotEmpty) return;

      String raw = '';
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          final details = await AndroidPlayInstallReferrer.installReferrer;
          raw = (details.installReferrer ?? '').trim();
        } catch (e) {
          // iOS / tanpa Play Services / device non-Play → fallback referral.
          dlog('[ATTR] installReferrer tidak tersedia: $e');
        }
      }

      // Fallback: deep link referral (share antar-user) bila referrer kosong.
      final referralUid = prefs.getString('pending_referrer_uid');
      final hasReferral = referralUid != null && referralUid.isNotEmpty;

      final parsed = parseReferrer(raw);
      final source = normalize(
        utmSource: parsed.utmSource,
        gclid: parsed.gclid,
        ttclid: parsed.ttclid,
        hasReferral: hasReferral,
      );

      await prefs.setString(_kReferrerRaw, raw);
      await prefs.setString(_kSource, source);
      await prefs.setString(_kUtmSource, parsed.utmSource);
      await prefs.setString(_kUtmMedium, parsed.utmMedium);
      await prefs.setString(_kUtmCampaign, parsed.utmCampaign);
      await prefs.setString(_kUtmContent, parsed.utmContent);
      await prefs.setString(_kReadAt, DateTime.now().toIso8601String());
      dlog('[ATTR] referrer="$raw" → source="$source" campaign="${parsed.utmCampaign}"');

      // Firebase Analytics (Q1b) — cross-check dashboard Google.
      await _logToFirebase(source, parsed);
    } catch (e) {
      dlog('[ATTR] readOnce gagal: $e');
    }
  }

  Future<void> _logToFirebase(String source, ReferrerParse p) async {
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: 'install_attribution',
        parameters: <String, Object>{
          'source': source,
          if (p.utmSource.isNotEmpty) 'utm_source': p.utmSource,
          if (p.utmMedium.isNotEmpty) 'utm_medium': p.utmMedium,
          if (p.utmCampaign.isNotEmpty) 'utm_campaign': p.utmCampaign,
        },
      );
    } catch (e) {
      dlog('[ATTR] Firebase logEvent gagal: $e');
    }
  }

  /// Param siap kirim ke RPC `upsert_device` (dari cache prefs). Bila belum
  /// ada → semua string kosong (server menyimpan NULL, tulis-sekali aman).
  Future<Map<String, String>> attributionParams() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'p_attr_source': prefs.getString(_kSource) ?? '',
        'p_utm_source': prefs.getString(_kUtmSource) ?? '',
        'p_utm_medium': prefs.getString(_kUtmMedium) ?? '',
        'p_utm_campaign': prefs.getString(_kUtmCampaign) ?? '',
        'p_utm_content': prefs.getString(_kUtmContent) ?? '',
        'p_referrer_raw': prefs.getString(_kReferrerRaw) ?? '',
      };
    } catch (_) {
      return const {};
    }
  }

  /// Normalisasi nama sumber dari berbagai bentuk utm_source / token iklan.
  /// Murni (tanpa I/O) → mudah di-unit-test.
  static String normalize({
    String utmSource = '',
    String gclid = '',
    String ttclid = '',
    bool hasReferral = false,
    String referrerRaw = '',
  }) {
    final s = utmSource.trim().toLowerCase();
    final raw = referrerRaw.trim().toLowerCase();

    // Google Ads: gclid otomatis (tanpa utm_source) — deteksi dari token.
    if (gclid.trim().isNotEmpty && s.isEmpty) return 'google';

    switch (s) {
      case 'fb':
      case 'facebook':
      case 'meta':
      case 'facebook_ads':
      case 'fb_ads':
        return 'facebook';
      case 'ig':
      case 'instagram':
      case 'instagram_ads':
        return 'instagram';
      case 'google':
      case 'adwords':
      case 'googleads':
      case 'google_ads':
      case 'youtube':
        return 'google';
      case 'tiktok':
      case 'tt':
      case 'tiktok_ads':
        return 'tiktok';
      case 'referral':
      case 'referrer':
      case 'invite':
      case 'share':
        return 'referral';
      case '':
        break;
      default:
        return s; // kanal lain (twitter/x, snapchat, dst) — apa adanya.
    }

    // utm_source kosong → cek token publik lain di referrer mentah.
    if (ttclid.trim().isNotEmpty || raw.contains('ttclid=')) return 'tiktok';
    if (raw.contains('gclid=')) return 'google';
    if (raw.contains('fbclid=')) return 'facebook';

    // Deep link referral (share antar-user) sebagai fallback terakhir.
    if (hasReferral) return 'referral';

    return 'organic';
  }

  /// Parse string referrer mentah (`utm_source=x&utm_medium=y&...`) →
  /// field terstruktur. Tahan terhadap nilai ter-encode & tanpa skema.
  static ReferrerParse parseReferrer(String raw) {
    if (raw.trim().isEmpty) return const ReferrerParse();
    Map<String, String> q;
    try {
      // Referrer Play TIDAK selalu punya skema — jadikan query eksplisit.
      final normalized = raw.contains('?') || raw.contains('://')
          ? raw
          : 'https://x/?$raw';
      q = Uri.parse(normalized).queryParameters;
    } catch (_) {
      // Fallback parser manual sederhana.
      q = {
        for (final part in raw.split('&'))
          if (part.contains('='))
            part.split('=')[0]: part.split('=').sublist(1).join('='),
      };
    }
    String g(String k) => (q[k] ?? '').trim();
    return ReferrerParse(
      utmSource: g('utm_source'),
      utmMedium: g('utm_medium'),
      utmCampaign: g('utm_campaign'),
      utmContent: g('utm_content'),
      gclid: g('gclid'),
      ttclid: g('ttclid'),
    );
  }

  /// Terjemahkan link/referrer mentah menjadi penjelasan manusiawi untuk
  /// admin — "link apa yang membawa user ke sini". Murni (tanpa I/O) →
  /// mudah di-unit-test. Tidak mengubah data, hanya memberi konteks.
  ///
  /// Contoh keluaran:
  ///   `utm_source=google-play&utm_medium=organic`
  ///     → 'Install organik — cari sendiri di Play Store (bukan iklan)'
  ///   `gclid=CjwKCA...`
  ///     → 'Google Ads (klik iklan)'
  ///   `` (kosong) → 'Tidak ada referrer'
  static String describeReferrer({
    String referrerRaw = '',
    String source = '',
    String utmSource = '',
    String utmMedium = '',
    String utmCampaign = '',
  }) {
    final raw = referrerRaw.trim().toLowerCase();
    final src = source.trim().toLowerCase();
    final us = utmSource.trim().toLowerCase();

    // Referrer default Play/Android = install organik (bukan iklan).
    if (us == 'google-play' || src == 'google-play') {
      return 'Install organik — cari sendiri di Play Store (bukan iklan)';
    }
    if (raw.contains('gclid=') || src == 'google') {
      return utmCampaign.isNotEmpty
          ? 'Google Ads — kampanye "$utmCampaign"'
          : 'Google Ads (klik iklan)';
    }
    if (raw.contains('fbclid=') || src == 'facebook') {
      return utmCampaign.isNotEmpty
          ? 'Facebook Ads — kampanye "$utmCampaign"'
          : 'Facebook Ads (klik iklan)';
    }
    if (src == 'instagram') {
      return utmCampaign.isNotEmpty
          ? 'Instagram Ads — kampanye "$utmCampaign"'
          : 'Instagram Ads (klik iklan)';
    }
    if (raw.contains('ttclid=') || src == 'tiktok') {
      return utmCampaign.isNotEmpty
          ? 'TikTok Ads — kampanye "$utmCampaign"'
          : 'TikTok Ads (klik iklan)';
    }
    if (src == 'referral') {
      return 'Referral — dari link share user lain';
    }
    if (src == 'organic' || (raw.isEmpty && us.isEmpty)) {
      return 'Organik / tanpa link iklan';
    }
    // Ada utm_source lain (twitter/x, snapchat, dst) — tampilkan apa adanya.
    if (us.isNotEmpty) {
      return 'Utm source: $us'
          '${utmMedium.isNotEmpty ? ' · medium: $utmMedium' : ''}';
    }
    return 'Kanal tidak dikenal — tidak ada data link';
  }
}

/// Hasil parse referrer mentah.
class ReferrerParse {
  final String utmSource;
  final String utmMedium;
  final String utmCampaign;
  final String utmContent;
  final String gclid;
  final String ttclid;

  const ReferrerParse({
    this.utmSource = '',
    this.utmMedium = '',
    this.utmCampaign = '',
    this.utmContent = '',
    this.gclid = '',
    this.ttclid = '',
  });
}
