#!/usr/bin/env bash
# Lapis 4: ukur frame + memori app di HP saat dipakai (scroll, buka chat).
# Pakai: scripts/stress/device.sh start   → reset & mulai ukur
#        scripts/stress/device.sh stop    → ambil hasil
set -uo pipefail
export PATH="$PATH:$HOME/Library/Android/sdk/platform-tools"
PKG="${PKG:-com.chatyuk.chatyuk.admin}"
DEV="${DEV:-$(adb devices | grep -oE '192\.168\.[0-9.]+:[0-9]+' | head -n1)}"
OUT="${OUT:-/tmp/stress}"
mkdir -p "$OUT"

layer() {
  adb -s "$DEV" shell dumpsys SurfaceFlinger --list 2>/dev/null \
    | grep -oE "$PKG/com.chatyuk.chatyuk.MainActivity#[0-9]+" | head -n1
}

case "${1:-start}" in
  start)
    L="$(layer)"; echo "$L" > "$OUT/layer.txt"
    echo "layer: $L"
    adb -s "$DEV" shell dumpsys SurfaceFlinger --latency "$L" > "$OUT/_marker.txt" 2>/dev/null
    echo "start: $(date +%s)" > "$OUT/device_start.txt"
    adb -s "$DEV" shell dumpsys meminfo "$PKG" > "$OUT/mem_before.txt" 2>/dev/null
    grep -E "TOTAL PSS|TOTAL RSS" "$OUT/mem_before.txt"
    echo "→ silakan pakai app (scroll list chat, buka chat, geser story) lalu jalankan: $0 stop"
    ;;
  stop)
    L="$(cat "$OUT/layer.txt")"
    adb -s "$DEV" shell dumpsys SurfaceFlinger --latency "$L" > "$OUT/lat_after.txt" 2>/dev/null
    adb -s "$DEV" shell dumpsys meminfo "$PKG" > "$OUT/mem_after.txt" 2>/dev/null
    python3 - "$OUT" <<'PY'
import sys
out=sys.argv[1]
v=[]
for i,l in enumerate(open(f"{out}/lat_after.txt")):
    if i==0: continue
    p=l.split()
    if len(p)<3: continue
    try: a,b,c=int(p[0]),int(p[1]),int(p[2])
    except: continue
    if a and c: v.append((c-a)/1e6)
v.sort()
if v:
    n=len(v); j=sum(1 for x in v if x>16.7)
    print(f"frame diukur : {n}")
    print(f"  p50   : {v[n//2]:.1f} ms")
    print(f"  p90   : {v[int(n*.9)]:.1f} ms")
    print(f"  p95   : {v[int(n*.95)-1]:.1f} ms")
    print(f"  max   : {v[-1]:.1f} ms")
    print(f"  jank  : {j} ({j*100/n:.1f}%)  (>16.7ms)")
else:
    print("frame: tidak ada sample")
for tag in ("before","after"):
    try:
        for line in open(f"{out}/mem_{tag}.txt"):
            if "TOTAL PSS" in line or "TOTAL RSS" in line:
                print(f"mem {tag:6}: {line.strip()}")
    except Exception: pass
PY
    ;;
esac
