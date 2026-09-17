import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Registry font aplikasi — dipilih admin dari panel (Global Setting) dan
/// berlaku untuk SELURUH tipografi secara global via realtime app_settings.
///
/// Key khusus [defaultKey] = 'default' berarti "jangan override": token
/// judul/CTA tetap Poppins dan body tetap Roboto (perilaku lama). Hanya
/// ketika admin memilih font lain (mis. 'inter') SEMUA token teks aplikasi
/// memakai font itu. Blok kode (`AppText.code`) selalu monospace.
class AppFonts {
  AppFonts._();

  static const String defaultKey = 'default';
  static const String prefKey = 'app_font_family';

  /// Key font SISTEM (font bawaan perangkat) — teks memakai font platform
  /// (Roboto di Android, SF di iOS) baik judul maupun body, tanpa memuat
  /// the underlying providerFonts. Berbeda dari [defaultKey] yang tetap
  /// Poppins (judul) + Roboto (body).
  static const String systemKey = 'system';

  /// Key font aktif (default = perilaku lama: Poppins + Roboto).
  static String current = defaultKey;

  /// Entri katalog: key → label + nama family Google Fonts (null = default).
  static const Map<String, AppFontOption> catalog = {
    defaultKey: AppFontOption(
      key: defaultKey,
      label: 'Default (Poppins + Roboto)',
      family: null,
    ),
    systemKey: AppFontOption(
      key: systemKey,
      label: 'System — font bawaan HP',
      family: null,
    ),
    'inter': AppFontOption(
      key: 'inter',
      label: 'Inter — sans-serif modern',
      family: 'Inter',
    ),
    // Klaster "light/tipis" — disengaja berdampingan dengan Inter supaya
    // gampang dibandingkan di picker admin (sampel Light ada di tiap baris).
    'dm_sans': AppFontOption(
      key: 'dm_sans',
      label: 'DM Sans — light, rounded',
      family: 'DM Sans',
    ),
    'figtree': AppFontOption(
      key: 'figtree',
      label: 'Figtree — light, clean',
      family: 'Figtree',
    ),
    'manrope': AppFontOption(
      key: 'manrope',
      label: 'Manrope — light, geometric',
      family: 'Manrope',
    ),
    'poppins': AppFontOption(
      key: 'poppins',
      label: 'Poppins',
      family: 'Poppins',
    ),
    'roboto': AppFontOption(key: 'roboto', label: 'Roboto', family: 'Roboto'),
    'montserrat': AppFontOption(
      key: 'montserrat',
      label: 'Montserrat',
      family: 'Montserrat',
    ),
    'nunito': AppFontOption(key: 'nunito', label: 'Nunito', family: 'Nunito'),
    'plus_jakarta_sans': AppFontOption(
      key: 'plus_jakarta_sans',
      label: 'Plus Jakarta Sans',
      family: 'Plus Jakarta Sans',
    ),
    'lora': AppFontOption(key: 'lora', label: 'Lora (serif)', family: 'Lora'),
    'jetbrains_mono': AppFontOption(
      key: 'jetbrains_mono',
      label: 'JetBrains Mono',
      family: 'JetBrains Mono',
    ),
  };

  /// Urutan tampil di picker (katalog mengikuti urutan ini).
  static List<AppFontOption> get options => catalog.values.toList();

  /// Apakah key = default (perilaku lama: Poppins + Roboto).
  static bool isDefault([String? key]) => (key ?? current) == defaultKey;

  /// Apakah key = font sistem (bawaan perangkat, tanpa the underlying providerFonts).
  static bool isSystem([String? key]) => (key ?? current) == systemKey;

  /// Normalisasi key tak dikenal → default.
  static String resolve(String? key) {
    if (key == null) return defaultKey;
    return catalog.containsKey(key) ? key : defaultKey;
  }

  /// Nama family untuk key (null bila default / tak ada override).
  /// Tanpa argumen → pakai [current] (font aktif).
  static String? family([String? key]) => catalog[resolve(key ?? current)]?.family;

  /// Label tampil untuk key. Tanpa argumen → pakai [current].
  static String label([String? key]) =>
      catalog[resolve(key ?? current)]?.label ?? defaultKey;

  /// Baca font tersimpan dari SharedPreferences (sinkron saat boot).
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    current = resolve(prefs.getString(prefKey));
  }

  /// Terapkan font (set static + persist). Tidak notify; pemanggil
  /// (ThemeProvider/AuthProvider) yang bertanggung jawab notifyListeners.
  static Future<void> set(String key) async {
    current = resolve(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, current);
  }

  /// Set tanpa menulis prefs (untuk sinkron realtime → dipanggil bersama set).
  static void setLocal(String key) {
    current = resolve(key);
  }

  /// Nama family efektif untuk `ThemeData.fontFamily` — dipakai sebagai
  /// jaring aman agar teks yang TIDAK memakai token AppText (mis. style
  /// bawaan Material) tetap ikut font global.
  ///
  /// Mengembalikan nama family internal the underlying provider Fonts (mis.
  /// `Inter_regular`) berikut fallback-nya, karena `ThemeData(fontFamily:
  /// 'Inter')` (nama mentah) TIDAK memetakan ke font runtime the underlying provider Fonts.
  /// null = default (tanpa override, pakai font platform).
  static ({String family, List<String>? fallback})? themeFontOverride() {
    final f = family();
    if (f == null) return null;
    final st = GoogleFonts.getFont(f);
    final fam = st.fontFamily;
    if (fam == null) return null;
    return (family: fam, fallback: st.fontFamilyFallback);
  }

  /// Bobot "tipis" untuk contoh teks di picker font — dipakai picker DAN
  /// unit test supaya cut Light tiap font bisa dibandingkan berdampingan.
  static const FontWeight lightWeight = FontWeight.w300;

  /// Style preview untuk picker font admin: font the underlying providerFonts
  /// terpilih, font sistem (polos) bila System, atau fallback bila default.
  /// Ditaruh di lib/config agar tidak melanggar aturan "tidak ada fontSize
  /// numerik di luar lib/config" (preview butuh ukuran spesifik 24/14).
  static TextStyle previewStyle(
    String? key, {
    required double size,
    required FontWeight weight,
    required Color color,
    required String fallback,
  }) {
    final fam = family(key);
    if (fam != null) {
      return GoogleFonts.getFont(
        fam,
        fontSize: size,
        fontWeight: weight,
        color: color,
      );
    }
    if (isSystem(key)) {
      return TextStyle(fontSize: size, fontWeight: weight, color: color);
    }
    return GoogleFonts.getFont(
      fallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }
}

/// Satu opsi font di katalog.
class AppFontOption {
  final String key;
  final String label;

  /// Nama family Google Fonts; null = pakai default (Poppins + Roboto).
  final String? family;

  const AppFontOption({
    required this.key,
    required this.label,
    required this.family,
  });
}
