#!/usr/bin/env bash
# Gate ukuran file Dart — cegah "file raksasa" tumbuh lagi (ratchet).
#
# Aturan: file lib/**/*.dart TIDAK BOLEH > 1000 baris, KECUALI yang sudah
# terdaftar di allowlist di bawah (utang teknis yang dijadwalkan dipecah).
#
# Ratchet: file yang sudah terdaftar HANYA BOLEH menyusut — batasnya adalah
# ukuran saat pendaftaran. Setelah file dipecah (< 1000), baris allowlist-nya
# DIHAPUS. Jangan menaikkan angka allowlist tanpa alasan kuat (itu regresi).
#
# Kebijakan konfigurasi: lib/config/ dikecualikan dari batas 1000 karena
# berisi DATA statis (strings, regions, city_coords) yang dijadwalkan pindah
# ke asset/generated terpisah — lihat docs/ARCHITECTURE.md.
set -euo pipefail

cd "$(dirname "$0")/.."

LIMIT=1000

# Format: "<path>:<max_baris>"  (max = ukuran SAAT PENDAFTARAN; hanya boleh turun)
ALLOWLIST=(
  "lib/config/strings.dart:4167"
  "lib/config/regions.dart:2428"
  "lib/config/city_coords.dart:1704"
  "lib/config/strings_admin.dart:1519"
  "lib/screens/private_chat_screen.dart:3117"
  "lib/screens/room_chat_screen.dart:2935"
  "lib/screens/profile_screen.dart:2196"
  "lib/screens/private_chats_screen.dart:1625"
  "lib/screens/admin_chat_list_screen.dart:1481"
  "lib/screens/story_composer_screen.dart:1328"
  "lib/screens/admin_chat_view_screen.dart:1185"
  "lib/services/room_voice_service.dart:1432"
  "lib/app.dart:1637"
  "lib/main.dart:1748"
)

fail=0
# 1) File > LIMIT yang TIDAK ada di allowlist = penambahan baru → tolak.
while IFS= read -r line; do
  n=$(echo "$line" | awk '{print $1}')
  f=$(echo "$line" | awk '{print $2}')
  [ "$n" -gt "$LIMIT" ] || continue
  found=0
  for entry in "${ALLOWLIST[@]}"; do
    if [ "${entry%%:*}" = "$f" ]; then found=1; break; fi
  done
  if [ "$found" -eq 0 ]; then
    echo "DITOLAK: $f = $n baris (> $LIMIT) & belum terdaftar di allowlist."
    echo "  Pecah file ini, atau (bila tidak bisa segera) daftarkan di"
    echo "  scripts/check_file_size.sh dengan angka = $n."
    fail=1
  fi
done < <(find lib -name '*.dart' | xargs wc -l | awk '$2!="total"{print $1" "$2}')

# 2) File allowlist yang MELEBIHI batas terdaftar = regresi (tumbuh) → tolak.
for entry in "${ALLOWLIST[@]}"; do
  f="${entry%%:*}"
  max="${entry##*:}"
  if [ -f "$f" ]; then
    n=$(wc -l < "$f" | tr -d ' ')
    if [ "$n" -gt "$max" ]; then
      echo "DITOLAK: $f tumbuh $max -> $n baris (ratchet hanya boleh turun)."
      echo "  Kembalikan pertumbuhan, atau pecah file. Jangan naikkan allowlist."
      fail=1
    fi
  else
    echo "INFO: $f ada di allowlist tapi file tidak ditemukan — hapus entri ini."
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo
  echo "Gagal: ada file raksasa baru / yang tumbuh. Lihat pesan di atas."
  exit 1
fi

echo "OK: tidak ada file baru > $LIMIT & allowlist tidak ada yang tumbuh."
