#!/usr/bin/env bash
# Lapis 1 guardrail: cek migrasi SEBELUM diterapkan.
#
# Gagal keras (exit 1) kalau menemukan pola yang terbukti merusak fitur
# lain di project ini (lihat docs/FEATURE_MAP.md + AGENTS.md § SQL):
#   1. Dua file migrasi dengan prefix timestamp SAMA → urutan apply
#      tidak deterministik (8 tabrakan nyata pernah terjadi).
#   2. DROP TABLE / DROP COLUMN tanpa penanda `-- SAFE:`.
#   3. ALTER COLUMN ... TYPE tanpa penanda `-- SAFE:`.
#   4. Fungsi FROZEN di-replace tanpa header `-- menyentuh: <fn>`.
#   5. Fungsi FROZEN di-replace tapi snapshot belum di-update.
#   6. GRANT/REVOKE/policy RLS berisiko tanpa penanda `-- SAFE:` (file baru
#      saja — insiden anon 2026-09-22: REVOKE SELECT tak terdeteksi cek 2–5).
#
# Aturan 2–5 hanya berlaku untuk migrasi SEPANJANG cutoff (default:
# 20260914100000, di-set lewat env CUTOFF) supaya migrasi historis yang
# sudah diterapkan & sah tidak diblokir retroaktif.
#
# Pakai: scripts/check_migrations.sh [--all|--staged]
#   CUTOFF=20260914100000 scripts/check_migrations.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIG_DIR="$ROOT/supabase/migrations"
cd "$ROOT"

MODE="${1:---all}"
CUTOFF="${CUTOFF:-20260914100000}"
FAIL=0
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL=1; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$1"; }
note() { printf '  %s\n' "$1"; }

echo "== Lapis 1: check_migrations ($MODE, cutoff=$CUTOFF) =="

# Daftar file yang diperiksa untuk aturan 2–5 (baru = >= cutoff).
new_files() {
  if [ "$MODE" = "--staged" ]; then
    git diff --cached --name-only --diff-filter=ACM | grep -E '^supabase/migrations/.*\.sql$' || true
  else
    for f in "$MIG_DIR"/*.sql; do
      b=$(basename "$f")
      v=${b%%_*}
      [ "$v" \> "$CUTOFF" ] || [ "$v" = "$CUTOFF" ] && echo "supabase/migrations/$b"
    done
  fi
}

# ── 1. Timestamp duplikat (SELALU, termasuk file lama, krn ini fakta) ──
echo "[1] Timestamp unik"
dups=$(ls "$MIG_DIR"/*.sql 2>/dev/null | xargs -n1 basename | sed -E 's/^([0-9]+)_.*/\1/' | sort | uniq -d || true)
if [ -n "$dups" ]; then
  while read -r v; do
    [ -z "$v" ] && continue
    fail "timestamp $v dipakai >1 file:"
    ls "$MIG_DIR/${v}_"*.sql | xargs -n1 basename | sed 's/^/       /'
  done <<< "$dups"
  note "→ rename salah satu (naikkan detik) + catat di docs/MIGRATION_LOG.md"
else
  ok "tidak ada tabrakan timestamp"
fi

# ── 2–3. DROP / ALTER TYPE tanpa -- SAFE: (migrasi baru) ──
echo "[2] DROP / ALTER TYPE butuh penanda '-- SAFE:' (baru saja)"
hit=0
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  f="$ROOT/$rel"
  [ -f "$f" ] || continue
  while IFS= read -r ln; do
    [ -z "$ln" ] && continue
    case "$ln" in *"-- SAFE:"*) continue ;; esac
    fail "$(basename "$f"): $(echo "$ln" | sed 's/^[[:space:]]*//')"
    hit=1
  done <<< "$(grep -nE '^[[:space:]]*(drop[[:space:]]+(table|column)|alter[[:space:]]+table[[:space:]]+[a-z_.]+[[:space:]]+alter[[:space:]]+column[[:space:]]+[a-z_]+[[:space:]]+type)' "$f" || true)"
done <<< "$(new_files)"
[ "$hit" -eq 0 ] && ok "tidak ada DROP/ALTER TYPE tanpa SAFE"

# ── 4. FROZEN functions: header kontrak ──
echo "[3] Fungsi FROZEN di-replace butuh header '-- menyentuh: <fn>'"
FROZEN_LIST="$ROOT/scripts/frozen_functions.txt"
SNAP="$ROOT/supabase/snapshots/functions.sql"
if [ -f "$FROZEN_LIST" ]; then
  while IFS= read -r fn; do
    [ -z "$fn" ] && continue
    case "$fn" in \#*) continue ;; esac
    last=$(grep -rlE "create[[:space:]]+or[[:space:]]+replace[[:space:]]+function[[:space:]]+public\.${fn}\b" "$MIG_DIR" --include="*.sql" 2>/dev/null | sort | tail -1 || true)
    [ -z "$last" ] && continue
    b=$(basename "$last"); v=${b%%_*}
    case "$v" in ''|*[!0-9]*) continue ;; esac
    if [ "$v" \> "$CUTOFF" ] || [ "$v" = "$CUTOFF" ]; then
      if grep -qE "menyentuh:.*\b${fn}\b" "$last"; then
        ok "FROZEN '$fn' header OK ($b)"
      else
        fail "$b redefine FROZEN '$fn' tanpa header '-- menyentuh: $fn'"
      fi
    fi
  done < "$FROZEN_LIST"
fi

# ── 5. Snapshot vs fungsi terkini ──
echo "[4] Snapshot fungsi FROZEN vs migrasi terakhir"
if [ -f "$SNAP" ]; then
  while IFS= read -r fn; do
    [ -z "$fn" ] && continue
    case "$fn" in \#*) continue ;; esac
    last=$(grep -rlE "create[[:space:]]+or[[:space:]]+replace[[:space:]]+function[[:space:]]+public\.${fn}\b" "$MIG_DIR" --include="*.sql" 2>/dev/null | sort | tail -1 || true)
    [ -z "$last" ] && continue
    b=$(basename "$last"); v=${b%%_*}
    case "$v" in ''|*[!0-9]*) continue ;; esac
    if [ "$v" \> "$CUTOFF" ] || [ "$v" = "$CUTOFF" ]; then
      if grep -qE "^--[[:space:]]*snapshot-fn:[[:space:]]*${fn}[[:space:]]*@" "$SNAP"; then
        stamp=$(grep -E "^--[[:space:]]*snapshot-fn:[[:space:]]*${fn}[[:space:]]*@" "$SNAP" | head -1 | sed -E 's/.*@[[:space:]]*//')
        if [ "$stamp" = "$b" ]; then
          :
        else
          fail "snapshot '$fn' dari '$stamp' tapi migrasi terakhir '$b' → jalankan scripts/snapshot_functions.sh"
        fi
      else
        fail "snapshot '$fn' belum ada → jalankan scripts/snapshot_functions.sh"
      fi
    fi
  done < "$FROZEN_LIST"
  ok "snapshot check selesai"
else
  note "snapshot belum ada — jalankan scripts/snapshot_functions.sh"
fi

# ── 6. Regresi-urutan: migrasi lama men-replace fungsi frozen TANPA patch lebih baru ──
# Pola insiden 2026-09-14: apply ulang migrasi LAMA (dummy_wake) menghapus
# cabang yang dipatch migrasi LEBIH BARU (restore). Deteksi: kalau file
# migrasi >= cutoff men-replace fungsi frozen, tapi versi terakhir fungsi itu
# (menurut timestamp) justru file yang TIDAK punya cabang kritis yang ada di
# snapshot — beri peringatan keras.
echo "[5] Cek cabang kritis tiap migrasi yang men-replace fungsi FROZEN"
while IFS= read -r fn; do
  [ -z "$fn" ] && continue
  case "$fn" in \#*) continue ;; esac
  last=$(grep -rlE "create[[:space:]]+or[[:space:]]+replace[[:space:]]+function[[:space:]]+public\.${fn}\b" "$MIG_DIR" --include="*.sql" 2>/dev/null | sort | tail -1 || true)
  [ -z "$last" ] && continue
  b=$(basename "$last"); v=${b%%_*}
  case "$v" in ''|*[!0-9]*) continue ;; esac
  if [ "$v" \> "$CUTOFF" ] || [ "$v" = "$CUTOFF" ]; then
    # Kumpulkan token 'cabang' penting yang ada di snapshot untuk fn ini.
    if [ -f "$SNAP" ]; then
      # baris-baris snapshot untuk fn ini
      snap_block=$(awk -v pat="snapshot-fn: $fn @" '
        $0 ~ pat {p=1} p {print} p && /^\$function\$/ {exit}' "$SNAP")
      for tok in ai_always_online ai_wake_until ai_offline_until invisible; do
        if echo "$snap_block" | grep -q "$tok"; then
          if ! grep -q "$tok" "$last"; then
            fail "REGRESI-URUTAN: '$fn' di $b TIDAK memuat '$tok' padahal snapshot punya — kemungkinan versi lama menimpa patch lebih baru. Re-apply migrasi restore/terbaru."
          fi
        fi
      done
    fi
  fi
done < "$FROZEN_LIST"
ok "cek cabang kritis selesai"

# ── 6. GRANT/REVOKE/policy RLS berisiko (insiden anon 2026-09-22) ──
# Pola insiden: REVOKE SELECT di profiles.status/avatar/last_seen merusak
# registrasi (upsert butuh SELECT) — tak terdeteksi cek [2]–[5] karena bukan
# DROP/ALTER dan bukan replace fungsi.
# Aturan: pernyataan di bawah pada file migrasi BARU wajib penanda `-- SAFE:`
# di baris yang sama (tulis alasan + fitur terdampak). Dikecualikan (rutin):
# `revoke execute on function` (hardening standar tiap RPC baru).
# Hanya file > GRANT_CUTOFF (default = migrasi terakhir saat guard dibuat)
# supaya migrasi historis yang sah tidak diblokir retroaktif.
echo "[6] GRANT/REVOKE/policy RLS butuh penanda '-- SAFE:' (file baru saja)"
GRANT_CUTOFF="${GRANT_CUTOFF:-20260923120000}"
hit6=0
while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  f="$ROOT/$rel"
  [ -f "$f" ] || continue
  b=$(basename "$f"); v=${b%%_*}
  case "$v" in ''|*[!0-9]*) continue ;; esac
  if [ "$v" \> "$GRANT_CUTOFF" ]; then
    while IFS= read -r ln; do
      [ -z "$ln" ] && continue
      case "$ln" in *"-- SAFE:"*) continue ;; esac
      # rutin: cabut execute fungsi dari public/anon
      case "$(echo "$ln" | tr '[:upper:]' '[:lower:]')" in
        *"revoke"*execute*on*function*) continue ;;
      esac
      fail "$(basename "$f"): $(echo "$ln" | sed 's/^[[:space:]]*//')"
      hit6=1
    done <<< "$(grep -inE '^[[:space:]]*(revoke[[:space:]]|grant[[:space:]]+(select|all)[[:space:]]|grant[[:space:]]+[a-z_,[:space:]]+to[[:space:]]+anon\b|(create|drop|alter)[[:space:]]+policy[[:space:]])' "$f" || true)"
  fi
done <<< "$(new_files)"
[ "$hit6" -eq 0 ] && ok "tidak ada GRANT/REVOKE/policy tanpa SAFE (file baru)"

echo
if [ "$FAIL" -ne 0 ]; then
  echo "==> check_migrations: DITOLAK. Perbaiki dulu (baca AGENTS.md § SQL)."
  exit 1
fi
echo "==> check_migrations: OK bersih."
