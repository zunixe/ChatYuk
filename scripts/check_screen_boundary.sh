#!/usr/bin/env bash
# Gate boundary: screen DILARANG import services/ (AGENTS.md § Modularitas).
#
# Aturan: semua I/O bisnis lewat providers/controllers. Screen hanya boleh
# import core/ (helper murni), widgets/, models/, config/, providers/.
#
# Batas ini sudah ditegakkan penuh (Fase 9) — gate mencegah regresi.
set -euo pipefail

cd "$(dirname "$0")/.."

# Cari import services/ di lib/screens (termasuk subfolder widgets/).
hits=$(grep -rn "import '\(\.\./\)\+services/" lib/screens --include='*.dart' || true)

if [ -n "$hits" ]; then
  echo "DITOLAK: screen dilarang import services/ (pakai provider/controller)."
  echo "$hits" | head -20
  echo
  echo "Perbaikan: pindahkan panggilan ke provider (lib/providers/) atau,"
  echo "untuk helper murni (cache/perf/media), ke lib/core/."
  exit 1
fi

# Core = helper murni (non-I/O bisnis): DILARANG import services/.
# Ketergantungan network/Storage di-inject dari luar (lihat main.dart).
core_hits=$(grep -rn "import '\(\.\./\)\+services/" lib/core --include='*.dart' || true)

if [ -n "$core_hits" ]; then
  echo "DITOLAK: core/ dilarang import services/ (helper murni saja)."
  echo "$core_hits" | head -20
  echo
  echo "Perbaikan: inject dependensi dari luar (mis. PostPhotoCache.downloader)"
  echo "yang di-wire di lib/main.dart, atau pindahkan file ke lib/services/."
  exit 1
fi

# Cari import core/<sub>/ yang tidak lewat prefix core (defensif).
echo "OK: 0 screen & 0 core import services/ (boundary bersih)."
