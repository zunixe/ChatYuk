// Kode telepon negara sedunia (E.164).
// Dipakai input nomor HP di Pengaturan › Akun — pilihan +62, +60, +1, dll.

class CountryDial {
  final String iso;
  final String name;
  final String dial;
  const CountryDial({required this.iso, required this.name, required this.dial});
}

String countryFlag(String iso) {
  final up = iso.toUpperCase();
  if (up.length != 2) return '';
  const base = 0x1F1E6;
  return String.fromCharCodes(up.codeUnits.map((c) => base + c - 0x41));
}

const List<CountryDial> countryDials = [
  CountryDial(iso: 'ID', name: 'Indonesia', dial: '62'),
  CountryDial(iso: 'MY', name: 'Malaysia', dial: '60'),
  CountryDial(iso: 'SG', name: 'Singapore', dial: '65'),
  CountryDial(iso: 'PH', name: 'Philippines', dial: '63'),
  CountryDial(iso: 'TH', name: 'Thailand', dial: '66'),
  CountryDial(iso: 'VN', name: 'Vietnam', dial: '84'),
  CountryDial(iso: 'KH', name: 'Cambodia', dial: '855'),
  CountryDial(iso: 'LA', name: 'Laos', dial: '856'),
  CountryDial(iso: 'MM', name: 'Myanmar', dial: '95'),
  CountryDial(iso: 'BN', name: 'Brunei', dial: '673'),
  CountryDial(iso: 'TL', name: 'Timor-Leste', dial: '670'),
  CountryDial(iso: 'IN', name: 'India', dial: '91'),
  CountryDial(iso: 'PK', name: 'Pakistan', dial: '92'),
  CountryDial(iso: 'BD', name: 'Bangladesh', dial: '880'),
  CountryDial(iso: 'LK', name: 'Sri Lanka', dial: '94'),
  CountryDial(iso: 'NP', name: 'Nepal', dial: '977'),
  CountryDial(iso: 'MV', name: 'Maldives', dial: '960'),
  CountryDial(iso: 'CN', name: 'China', dial: '86'),
  CountryDial(iso: 'HK', name: 'Hong Kong', dial: '852'),
  CountryDial(iso: 'MO', name: 'Macau', dial: '853'),
  CountryDial(iso: 'TW', name: 'Taiwan', dial: '886'),
  CountryDial(iso: 'JP', name: 'Japan', dial: '81'),
  CountryDial(iso: 'KR', name: 'South Korea', dial: '82'),
  CountryDial(iso: 'MN', name: 'Mongolia', dial: '976'),
  CountryDial(iso: 'KZ', name: 'Kazakhstan', dial: '7'),
  CountryDial(iso: 'KG', name: 'Kyrgyzstan', dial: '996'),
  CountryDial(iso: 'TJ', name: 'Tajikistan', dial: '992'),
  CountryDial(iso: 'TM', name: 'Turkmenistan', dial: '993'),
  CountryDial(iso: 'UZ', name: 'Uzbekistan', dial: '998'),
  CountryDial(iso: 'AF', name: 'Afghanistan', dial: '93'),
  CountryDial(iso: 'IR', name: 'Iran', dial: '98'),
  CountryDial(iso: 'IQ', name: 'Iraq', dial: '964'),
  CountryDial(iso: 'SA', name: 'Saudi Arabia', dial: '966'),
  CountryDial(iso: 'AE', name: 'United Arab Emirates', dial: '971'),
  CountryDial(iso: 'QA', name: 'Qatar', dial: '974'),
  CountryDial(iso: 'KW', name: 'Kuwait', dial: '965'),
  CountryDial(iso: 'OM', name: 'Oman', dial: '968'),
  CountryDial(iso: 'BH', name: 'Bahrain', dial: '973'),
  CountryDial(iso: 'JO', name: 'Jordan', dial: '962'),
  CountryDial(iso: 'LB', name: 'Lebanon', dial: '961'),
  CountryDial(iso: 'SY', name: 'Syria', dial: '963'),
  CountryDial(iso: 'YE', name: 'Yemen', dial: '967'),
  CountryDial(iso: 'IL', name: 'Israel', dial: '972'),
  CountryDial(iso: 'PS', name: 'Palestine', dial: '970'),
  CountryDial(iso: 'TR', name: 'Turkey', dial: '90'),
  CountryDial(iso: 'CY', name: 'Cyprus', dial: '357'),
  CountryDial(iso: 'GE', name: 'Georgia', dial: '995'),
  CountryDial(iso: 'AM', name: 'Armenia', dial: '374'),
  CountryDial(iso: 'AZ', name: 'Azerbaijan', dial: '994'),
  CountryDial(iso: 'US', name: 'United States', dial: '1'),
  CountryDial(iso: 'CA', name: 'Canada', dial: '1'),
  CountryDial(iso: 'MX', name: 'Mexico', dial: '52'),
  CountryDial(iso: 'GT', name: 'Guatemala', dial: '502'),
  CountryDial(iso: 'HN', name: 'Honduras', dial: '504'),
  CountryDial(iso: 'SV', name: 'El Salvador', dial: '503'),
  CountryDial(iso: 'NI', name: 'Nicaragua', dial: '505'),
  CountryDial(iso: 'CR', name: 'Costa Rica', dial: '506'),
  CountryDial(iso: 'PA', name: 'Panama', dial: '507'),
  CountryDial(iso: 'CU', name: 'Cuba', dial: '53'),
  CountryDial(iso: 'JM', name: 'Jamaica', dial: '1876'),
  CountryDial(iso: 'DO', name: 'Dominican Republic', dial: '1809'),
  CountryDial(iso: 'PR', name: 'Puerto Rico', dial: '1787'),
  CountryDial(iso: 'HT', name: 'Haiti', dial: '509'),
  CountryDial(iso: 'BR', name: 'Brazil', dial: '55'),
  CountryDial(iso: 'AR', name: 'Argentina', dial: '54'),
  CountryDial(iso: 'CL', name: 'Chile', dial: '56'),
  CountryDial(iso: 'CO', name: 'Colombia', dial: '57'),
  CountryDial(iso: 'PE', name: 'Peru', dial: '51'),
  CountryDial(iso: 'VE', name: 'Venezuela', dial: '58'),
  CountryDial(iso: 'EC', name: 'Ecuador', dial: '593'),
  CountryDial(iso: 'BO', name: 'Bolivia', dial: '591'),
  CountryDial(iso: 'PY', name: 'Paraguay', dial: '595'),
  CountryDial(iso: 'UY', name: 'Uruguay', dial: '598'),
  CountryDial(iso: 'GB', name: 'United Kingdom', dial: '44'),
  CountryDial(iso: 'IE', name: 'Ireland', dial: '353'),
  CountryDial(iso: 'FR', name: 'France', dial: '33'),
  CountryDial(iso: 'DE', name: 'Germany', dial: '49'),
  CountryDial(iso: 'NL', name: 'Netherlands', dial: '31'),
  CountryDial(iso: 'BE', name: 'Belgium', dial: '32'),
  CountryDial(iso: 'LU', name: 'Luxembourg', dial: '352'),
  CountryDial(iso: 'ES', name: 'Spain', dial: '34'),
  CountryDial(iso: 'PT', name: 'Portugal', dial: '351'),
  CountryDial(iso: 'IT', name: 'Italy', dial: '39'),
  CountryDial(iso: 'CH', name: 'Switzerland', dial: '41'),
  CountryDial(iso: 'AT', name: 'Austria', dial: '43'),
  CountryDial(iso: 'SE', name: 'Sweden', dial: '46'),
  CountryDial(iso: 'NO', name: 'Norway', dial: '47'),
  CountryDial(iso: 'DK', name: 'Denmark', dial: '45'),
  CountryDial(iso: 'FI', name: 'Finland', dial: '358'),
  CountryDial(iso: 'IS', name: 'Iceland', dial: '354'),
  CountryDial(iso: 'PL', name: 'Poland', dial: '48'),
  CountryDial(iso: 'CZ', name: 'Czech Republic', dial: '420'),
  CountryDial(iso: 'SK', name: 'Slovakia', dial: '421'),
  CountryDial(iso: 'HU', name: 'Hungary', dial: '36'),
  CountryDial(iso: 'RO', name: 'Romania', dial: '40'),
  CountryDial(iso: 'BG', name: 'Bulgaria', dial: '359'),
  CountryDial(iso: 'GR', name: 'Greece', dial: '30'),
  CountryDial(iso: 'HR', name: 'Croatia', dial: '385'),
  CountryDial(iso: 'SI', name: 'Slovenia', dial: '386'),
  CountryDial(iso: 'RS', name: 'Serbia', dial: '381'),
  CountryDial(iso: 'BA', name: 'Bosnia and Herzegovina', dial: '387'),
  CountryDial(iso: 'ME', name: 'Montenegro', dial: '382'),
  CountryDial(iso: 'MK', name: 'North Macedonia', dial: '389'),
  CountryDial(iso: 'AL', name: 'Albania', dial: '355'),
  CountryDial(iso: 'XK', name: 'Kosovo', dial: '383'),
  CountryDial(iso: 'MD', name: 'Moldova', dial: '373'),
  CountryDial(iso: 'UA', name: 'Ukraine', dial: '380'),
  CountryDial(iso: 'BY', name: 'Belarus', dial: '375'),
  CountryDial(iso: 'LT', name: 'Lithuania', dial: '370'),
  CountryDial(iso: 'LV', name: 'Latvia', dial: '371'),
  CountryDial(iso: 'EE', name: 'Estonia', dial: '372'),
  CountryDial(iso: 'RU', name: 'Russia', dial: '7'),
  CountryDial(iso: 'EG', name: 'Egypt', dial: '20'),
  CountryDial(iso: 'LY', name: 'Libya', dial: '218'),
  CountryDial(iso: 'TN', name: 'Tunisia', dial: '216'),
  CountryDial(iso: 'DZ', name: 'Algeria', dial: '213'),
  CountryDial(iso: 'MA', name: 'Morocco', dial: '212'),
  CountryDial(iso: 'SD', name: 'Sudan', dial: '249'),
  CountryDial(iso: 'ET', name: 'Ethiopia', dial: '251'),
  CountryDial(iso: 'SO', name: 'Somalia', dial: '252'),
  CountryDial(iso: 'KE', name: 'Kenya', dial: '254'),
  CountryDial(iso: 'UG', name: 'Uganda', dial: '256'),
  CountryDial(iso: 'TZ', name: 'Tanzania', dial: '255'),
  CountryDial(iso: 'NG', name: 'Nigeria', dial: '234'),
  CountryDial(iso: 'NE', name: 'Niger', dial: '227'),
  CountryDial(iso: 'ML', name: 'Mali', dial: '223'),
  CountryDial(iso: 'SN', name: 'Senegal', dial: '221'),
  CountryDial(iso: 'GH', name: 'Ghana', dial: '233'),
  CountryDial(iso: 'CI', name: "Cote d'Ivoire", dial: '225'),
  CountryDial(iso: 'CM', name: 'Cameroon', dial: '237'),
  CountryDial(iso: 'BF', name: 'Burkina Faso', dial: '226'),
  CountryDial(iso: 'MG', name: 'Madagascar', dial: '261'),
  CountryDial(iso: 'MZ', name: 'Mozambique', dial: '258'),
  CountryDial(iso: 'ZA', name: 'South Africa', dial: '27'),
  CountryDial(iso: 'AU', name: 'Australia', dial: '61'),
  CountryDial(iso: 'NZ', name: 'New Zealand', dial: '64'),
  CountryDial(iso: 'FJ', name: 'Fiji', dial: '679'),
  CountryDial(iso: 'PG', name: 'Papua New Guinea', dial: '675'),
  CountryDial(iso: 'WS', name: 'Samoa', dial: '685'),
  CountryDial(iso: 'TO', name: 'Tonga', dial: '676'),
  CountryDial(iso: 'VU', name: 'Vanuatu', dial: '678'),
  CountryDial(iso: 'SB', name: 'Solomon Islands', dial: '677'),
  CountryDial(iso: 'NC', name: 'New Caledonia', dial: '687'),
  CountryDial(iso: 'PF', name: 'French Polynesia', dial: '689'),
  CountryDial(iso: 'GU', name: 'Guam', dial: '1671'),
  CountryDial(iso: 'MT', name: 'Malta', dial: '356'),
  CountryDial(iso: 'FO', name: 'Faroe Islands', dial: '298'),
  CountryDial(iso: 'GL', name: 'Greenland', dial: '299'),
  CountryDial(iso: 'GI', name: 'Gibraltar', dial: '350'),
  CountryDial(iso: 'AD', name: 'Andorra', dial: '376'),
  CountryDial(iso: 'MC', name: 'Monaco', dial: '377'),
  CountryDial(iso: 'LI', name: 'Liechtenstein', dial: '423'),
  CountryDial(iso: 'SM', name: 'San Marino', dial: '378'),
  CountryDial(iso: 'VA', name: 'Vatican City', dial: '379'),
];

CountryDial findDialForPhone(String phoneE164) {
  final digits = phoneE164.replaceAll(RegExp(r'[^0-9]'), '');
  CountryDial? best;
  for (final c in countryDials) {
    if (digits.startsWith(c.dial)) {
      if (best == null || c.dial.length > best.dial.length) best = c;
    }
  }
  return best ?? const CountryDial(iso: 'ID', name: 'Indonesia', dial: '62');
}

CountryDial findDialForCountryName(String? countryName) {
  if (countryName == null || countryName.isEmpty) {
    return const CountryDial(iso: 'ID', name: 'Indonesia', dial: '62');
  }
  final q = countryName.trim().toLowerCase();
  for (final c in countryDials) {
    if (c.name.toLowerCase() == q) return c;
  }
  for (final c in countryDials) {
    if (c.name.toLowerCase().contains(q) || q.contains(c.name.toLowerCase())) {
      return c;
    }
  }
  return const CountryDial(iso: 'ID', name: 'Indonesia', dial: '62');
}

String splitNationalNumber(String phoneE164, String dial) {
  final digits = phoneE164.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith(dial)) return digits.substring(dial.length);
  if (phoneE164.startsWith('+')) return digits;
  return digits.startsWith('0') ? digits.substring(1) : digits;
}

String combineDialAndNumber(String dial, String national) {
  var d = national.replaceAll(RegExp(r'[^0-9]'), '');
  while (d.startsWith('0')) {
    d = d.substring(1);
  }
  if (d.isEmpty) return '';
  return '+$dial$d';
}
