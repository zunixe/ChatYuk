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

# Widgets & mixins: juga lapisan UI/kontrak — DILARANG import services/
# langsung (gate diperluas Fase B 2026-10-10). Semua I/O via providers/.
for dir in lib/widgets lib/mixins; do
  h=$(grep -rn "import '\(\.\./\)\+services/" "$dir" --include='*.dart' || true)
  if [ -n "$h" ]; then
    echo "DITOLAK: $dir dilarang import services/ (pakai provider)."
    echo "$h" | head -20
    echo
    echo "Perbaikan: tambah passthrough di provider, atau inject dari"
    echo "composition root (main.dart) untuk helper murni core/."
    exit 1
  fi
done

# Core = helper murni (non-I/O bisnis): DILARANG import services/ maupun
# providers/ (boundary Fase B 2026-10-10).
for pat in "\(\.\./\)\+services/" "\(\.\./\)\+providers/" "package:chatyuk/services/" "package:chatyuk/providers/"; do
  core_hits=$(grep -rn "import '$pat" lib/core --include='*.dart' || true)
  if [ -n "$core_hits" ]; then
    echo "DITOLAK: core/ dilarang import services/providers (helper murni saja)."
    echo "$core_hits" | head -20
    echo
    echo "Perbaikan: inject dependensi dari luar (mis. PostPhotoCache.downloader"
    echo "atau MessageCache.isStoragePath di-wire di lib/main.dart), atau"
    echo "pindahkan file ke lib/services/."
    exit 1
  fi
done

# Cari import core/<sub>/ yang tidak lewat prefix core (defensif).
echo "OK: 0 screen/widget/mixin import services/ + 0 core import services/providers."
