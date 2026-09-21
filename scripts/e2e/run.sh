#!/usr/bin/env bash
# E2E ChatYuk (Maestro) — jalankan flow UI di HP/emulator nyata.
#
# Maestro SENGAJA terpisah dari pubspec (dev-dep `integration_test` pernah
# merusak build rilis — lihat integration_test/README.md). Cara ini nol
# dampak ke build.
#
# Pakai:
#   scripts/e2e/run.sh              # semua flow
#   scripts/e2e/run.sh 01           # hanya flow yang namanya mengandung "01"
#   DEV=192.168.18.33:46197 scripts/e2e/run.sh
#
# Prasyarat: maestro terpasang (brew install mobile-dev-inc/tap/maestro),
# adb, dan APK ChatYuk sudah terpasang di device.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

export PATH="/opt/homebrew/bin:$PATH"
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"

if ! command -v maestro >/dev/null 2>&1; then
  echo "maestro tidak ditemukan. Pasang: brew install mobile-dev-inc/tap/maestro" >&2
  exit 1
fi
if ! command -v adb >/dev/null 2>&1; then
  echo "adb tidak ditemukan (Android platform-tools)" >&2
  exit 1
fi

DEV="${DEV:-$(adb devices | grep -oE '([0-9]+\.){3}[0-9]+:[0-9]+' | head -n1)}"
if [ -z "$DEV" ]; then
  echo "Tidak ada device adb (wireless debugging belum tersambung?)" >&2
  adb devices >&2
  exit 1
fi

echo "== E2E ChatYuk (Maestro) =="
echo "device: $DEV"

# App ADMIN tidak boleh menutupi app user — Maestro membaca window teratas,
# dan pernah salah baca UI admin (membuat selector "tidak ketemu" palsu).
adb -s "$DEV" shell am force-stop com.chatyuk.chatyuk.admin 2>/dev/null || true

# Pastikan app user terpasang.
if ! adb -s "$DEV" shell pm list packages 2>/dev/null | grep -q "com.chatyuk.chatyuk$"; then
  echo "APK user (com.chatyuk.chatyuk) belum terpasang di $DEV." >&2
  echo "Build + install dulu (lihat AGENTS.md § Build & Push ke HP)." >&2
  exit 1
fi

FILTER="${1:-}"
if [ -n "$FILTER" ]; then
  FLOWS=()
  while IFS= read -r f; do FLOWS+=("$f"); done < <(ls e2e/flows/*"$FILTER"*.yaml 2>/dev/null)
  if [ "${#FLOWS[@]}" -eq 0 ]; then
    echo "Tidak ada flow cocok filter '$FILTER' di e2e/flows/" >&2
    exit 1
  fi
else
  FLOWS=(e2e/flows/*.yaml)
fi

echo "flow: ${#FLOWS[@]} file"
echo

maestro test "${FLOWS[@]}" --udid "$DEV"
RC=$?

echo
if [ "$RC" -eq 0 ]; then
  echo "==> E2E: semua flow lolos."
else
  echo "==> E2E: ADA YANG GAGAL (rc=$RC). Artefak: ~/Library/Application Support/*/maestro/tests/"
fi
exit "$RC"
