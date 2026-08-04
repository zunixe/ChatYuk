// Nama negara dalam Bahasa Indonesia (key) dan English (value di kotaByNegaraEn)
const Map<String, List<String>> kotaByNegara = {
  'Indonesia': ['Jakarta', 'Surabaya', 'Bandung', 'Medan', 'Semarang', 'Makassar', 'Yogyakarta', 'Palembang', 'Denpasar', 'Tangerang', 'Depok', 'Bekasi'],
  'Malaysia': ['Kuala Lumpur', 'George Town', 'Johor Bahru', 'Ipoh', 'Malaka', 'Kota Kinabalu', 'Kuching', 'Shah Alam'],
  'Singapura': ['Singapura'],
  'Thailand': ['Bangkok', 'Chiang Mai', 'Phuket', 'Pattaya', 'Hat Yai', 'Khon Kaen', 'Nakhon Ratchasima', 'Udon Thani'],
  'Filipina': ['Manila', 'Quezon City', 'Cebu City', 'Davao', 'Makati', 'Baguio', 'Iloilo', 'Pasig'],
  'Vietnam': ['Hanoi', 'Ho Chi Minh City', 'Da Nang', 'Hai Phong', 'Can Tho', 'Hue', 'Nha Trang'],
  'Brunei': ['Bandar Seri Begawan', 'Kuala Belait', 'Seria', 'Tutong'],
  'Myanmar': ['Yangon', 'Mandalay', 'Naypyidaw', 'Bago', 'Mawlamyine'],
  'Kamboja': ['Phnom Penh', 'Siem Reap', 'Battambang', 'Sihanoukville'],
  'Laos': ['Vientiane', 'Luang Prabang', 'Pakse', 'Savannakhet'],
  'Timor Leste': ['Dili', 'Baucau', 'Maliana'],
};

// Nama negara dalam English (key = sama dengan kotaByNegara, value = nama EN)
const Map<String, String> negaraEnName = {
  'Indonesia': 'Indonesia',
  'Malaysia': 'Malaysia',
  'Singapura': 'Singapore',
  'Thailand': 'Thailand',
  'Filipina': 'Philippines',
  'Vietnam': 'Vietnam',
  'Brunei': 'Brunei',
  'Myanmar': 'Myanmar',
  'Kamboja': 'Cambodia',
  'Laos': 'Laos',
  'Timor Leste': 'Timor-Leste',
};

/// Mendapatkan nama negara sesuai bahasa (isId = Bahasa Indonesia, else English)
String negaraLabel(String key, bool isId) {
  if (isId) return key;
  return negaraEnName[key] ?? key;
}

/// Mendapatkan list negara sesuai bahasa (label → key mapping untuk dropdown)
List<String> getNegaraKeys() => kotaByNegara.keys.toList();
