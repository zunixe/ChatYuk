#!/bin/bash
# ChatYuk Dev Runner — Supabase local + flavor dev
# Pemakaian:
#   bash tool/run_dev.sh            -> HP fisik via USB (adb reverse)
#   bash tool/run_dev.sh emulator   -> Android emulator
set -e
cd "$(dirname "$0")/.."

# 1. Pastikan Supabase local jalan
if ! curl -s -o /dev/null --max-time 3 http://127.0.0.1:54321/rest/v1/; then
  echo ">> Supabase local belum jalan — menjalankan supabase start..."
  (cd supabase && supabase start)
fi

# 2. Ambil anon key local
LOCAL_KEY=$(cd supabase && supabase status -o env 2>/dev/null | grep '^ANON_KEY=' | cut -d'"' -f2)
if [ -z "$LOCAL_KEY" ]; then
  echo "ERROR: gagal baca ANON_KEY dari supabase status"
  exit 1
fi

# 3. Target: emulator (10.0.2.2) atau HP fisik USB (localhost + adb reverse)
TARGET="${1:-usb}"
if [ "$TARGET" = "emulator" ]; then
  SUPA_URL="http://10.0.2.2:54321"
else
  adb reverse tcp:54321 tcp:54321
  SUPA_URL="http://localhost:54321"
fi

echo ">> APP_ENV=dev  SUPABASE_URL=$SUPA_URL"
exec flutter run --flavor apkpureDev \
  --dart-define=APP_ENV=dev \
  --dart-define=SUPABASE_URL="$SUPA_URL" \
  --dart-define=SUPABASE_ANON_KEY="$LOCAL_KEY"
