#!/usr/bin/env python3
"""Generate lib/config/city_coords.dart dari GeoNames cities15000.

Cocokkan setiap (negara, kota) di regions.dart -> lat/lon GeoNames.
Output: const map key 'Negara|Kota' -> [lat, lon].
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGIONS = ROOT / 'lib' / 'config' / 'regions.dart'
OUT = ROOT / 'lib' / 'config' / 'city_coords.dart'
GN_CITIES = Path('/tmp/cities15000.txt')
GN_COUNTRY = Path('/tmp/countryInfo.txt')

def load_regions():
    src = REGIONS.read_text()
    body = src[src.index('kotaByNegara = {'):]
    result = {}
    for cm in re.finditer(r"^  '(?P<country>[^']+)': \[(?P<cities>.*?)\],", body, re.S | re.M):
        country = cm.group('country').replace("\\'", "'")
        cities = re.findall(r"'((?:[^'\\]|\\.)*)'", cm.group('cities'))
        result[country] = [c.replace("\\'", "'") for c in cities]
    return result

def load_country_names():
    code2name = {}
    for line in GN_COUNTRY.read_text(errors='ignore').splitlines():
        if line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) > 4:
            code2name[parts[0]] = parts[4]
    return code2name

def norm(s):
    import unicodedata
    s = unicodedata.normalize('NFKD', s)
    s = ''.join(ch for ch in s if not unicodedata.combining(ch))
    s = s.lower().strip().strip('.')
    return s

COUNTRY_ALIASES = {
    'czech republic': 'CZ',
    'south korea': 'KR',
    'vietnam': 'VN',
    'laos': 'LA',
    'brunei': 'BN',
    'russia': 'RU',
    'syria': 'SY',
    'iran': 'IR',
    'moldova': 'MD',
    'tanzania': 'TZ',
    'palestine': 'PS',
    'kosovo': 'XK',
}

def variants(n):
    """Semua bentuk normalisasi yang mungkin untuk sebuah nama kota."""
    out = {n}
    # GeoNames ascii membuang digraf: Århus -> Arhus, sementara kurasi
    # kita menulis Aarhus. Tambahkan bentuk kolaps 'aa'->'a'.
    if 'aa' in n:
        out.add(n.replace('aa', 'a'))
    return out

CITY_ALIASES = {
    'barisal': 'barishal',
    'chittagong': 'chattogram',
    'rousse': 'ruse',
    'mazar-i-sharif': 'mazar-e sharif',
    'quebec city': 'quebec',
    'santa cruz': 'santa cruz de la sierra',
}

def main():
    regions = load_regions()
    code2name = load_country_names()
    name2code = {norm(v): k for k, v in code2name.items()}
    name2code.update(COUNTRY_ALIASES)

    gn = {}
    global_index = {}
    for line in GN_CITIES.read_text(errors='ignore').splitlines():
        p = line.split('\t')
        if len(p) < 18:
            continue
        cc, name, ascii_name = p[8], p[1], p[2]
        try:
            lat, lon = float(p[4]), float(p[5])
        except ValueError:
            continue
        base = {norm(name), norm(ascii_name)}
        names = set(base)
        for n in base:
            names |= variants(n)
            alias = CITY_ALIASES.get(n)
            if alias:
                names.add(alias)
        for n in names:
            gn.setdefault((cc, n), (lat, lon))
            global_index.setdefault(n, {})[cc] = (lat, lon)

    def lookup(city, cc):
        n0 = norm(city)
        for cand in ({n0} | variants(n0) | ({CITY_ALIASES[n0]} if n0 in CITY_ALIASES else set())):
            if cc and (cc, cand) in gn:
                return gn[(cc, cand)]
            cands = global_index.get(cand)
            if cands and len(cands) == 1:
                return next(iter(cands.values()))
            if cands and cc and cc in cands:
                return cands[cc]
        return None

    out_map = {}
    missing = []
    for country, cities in sorted(regions.items()):
        cc = name2code.get(norm(country))
        for city in cities:
            coord = lookup(city, cc)
            if coord:
                out_map[f'{country}|{city}'] = coord
            else:
                missing.append(f'{country}|{city}')

    lines = [
        '// AUTO-GENERATED oleh scripts/gen_city_coords.py — jangan edit manual.',
        '// Sumber koordinat: GeoNames cities15000 (CC-BY 4.0 / ODbL),',
        '// https://www.geonames.org/export/',
        '// Key: \'Negara|Kota\' (harus cocok dengan kotaByNegara di regions.dart).',
        '',
        "const Map<String, List<double>> kotaCoords = {",
    ]
    for k in sorted(out_map):
        lat, lon = out_map[k]
        esc = k.replace("'", "\\'")
        lines.append(f"  '{esc}': [{lat}, {lon}],")
    lines.append('};')
    lines.append('')
    OUT.write_text('\n'.join(lines))
    total = sum(len(v) for v in regions.values())
    print(f'total kota kurasi: {total}')
    print(f'cocok: {len(out_map)}  tanpa koordinat: {len(missing)}')
    for m in missing[:40]:
        print(' MISS', m)

if __name__ == '__main__':
    sys.exit(main())
