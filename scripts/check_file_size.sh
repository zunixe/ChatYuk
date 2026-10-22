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
# 2026-10-13: private_chat_message.dart menembus 1000 lewat kerja lain
# (commit c7e8bf7: gate link preview viewport + memo kode) = 1004, lalu +10
# baris cabang stiker (1 pemanggilan StickerMessageBubble). Utang teknis:
# pecah widget bubble (voice/video/foto/sticker) ke file terpisah. Angka =
# ukuran SAAT pendaftaran (hanya boleh TURUN).
# 2026-10-19: file sudah 1156 baris di HEAD (allowlist 1014 tertinggal dari
# kenyataan -> gate selalu gagal). Angka disamakan ke ukuran nyata 1158
# (net +2 dari pekerjaan padding balasan). Utang teknis TETAP: pecah widget
# bubble (voice/video/foto/sticker) ke file terpisah; setelah dipecah angka
# ini WAJIB turun/dihapus.
# 2026-10-22: private_chat_message.dart DIPECAH (1311 -> 969) → keluar dari
# allowlist (ratchet turun). Sisa file >1000 yang belum dipecah didaftarkan di
# angka SEKARANG; jangan dinaikkan, hanya boleh turun/hapus.
ALLOWLIST=(
  lib/widgets/post_card.dart:1091
  lib/widgets/chat_video_bubble.dart:1006
  lib/widgets/chat_composer_input.dart:1082
  lib/screens/private_chats/private_chats_build.dart:1342
  lib/screens/private_chat/private_chat_core.dart:1016
  lib/screens/room_chat/room_chat_live.dart:1070
  lib/services/chat_stream_session.dart:1219
  lib/main_notifications.dart:1010
)

fail=0
# 1) File > LIMIT yang TIDAK ada di allowlist = penambahan baru → tolak.
while IFS= read -r line; do
  n=$(echo "$line" | awk '{print $1}')
  f=$(echo "$line" | awk '{print $2}')
  [ "$n" -gt "$LIMIT" ] || continue
  found=0
  for entry in "${ALLOWLIST[@]+"${ALLOWLIST[@]}"}"; do
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
for entry in "${ALLOWLIST[@]+"${ALLOWLIST[@]}"}"; do
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
