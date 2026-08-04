import 'dart:convert';
import 'package:http/http.dart' as http;

class GeoInfo {
  final String country;
  final String city;
  final String ipAddress;

  GeoInfo({required this.country, required this.city, required this.ipAddress});
}

class GeoService {
  static const _countryNames = <String, String>{
    'ID': 'Indonesia',
    'MY': 'Malaysia',
    'SG': 'Singapura',
    'TH': 'Thailand',
    'PH': 'Filipina',
    'VN': 'Vietnam',
    'BN': 'Brunei',
    'MM': 'Myanmar',
    'KH': 'Kamboja',
    'LA': 'Laos',
    'TL': 'Timor Leste',
  };

  Future<GeoInfo?> detect() async {
    try {
      final res = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final code = (data['country_code'] as String?) ?? '';
      final country = _countryNames[code] ?? (data['country_name'] as String?) ?? '';
      final city = (data['city'] as String?) ?? '';
      final ip = (data['ip'] as String?) ?? '';

      if (country.isEmpty) return null;
      return GeoInfo(country: country, city: city, ipAddress: ip);
    } catch (_) {
      return null;
    }
  }
}
