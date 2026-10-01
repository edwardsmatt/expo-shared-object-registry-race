#!/usr/bin/env bash
# Usage: scripts/run-launches.sh <launches> <label>
# Cold-starts the app <launches> times, taps "Run stress" and prints each run's summary line.
set -euo pipefail
LAUNCHES=${1:-10}
LABEL=${2:-run}
APP=com.example.sharedobjectrace
OUT=${OUT_DIR:-.}/stress-$LABEL.log
adb reverse tcp:8082 tcp:8082 >/dev/null
: > "$OUT"

tap_button() {
  for _ in $(seq 1 60); do
    adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
    local ui bounds
    ui=$(adb shell cat /sdcard/ui.xml 2>/dev/null | tr '>' '\n' || true)
    if [[ -n "$ui" ]] && ! grep -q 'text="Idle"' <<<"$ui"; then
      bounds=$(grep -i 'RUN STRESS' <<<"$ui" | head -1 || true)
      [[ -n "$bounds" ]] && return 0
    fi
    bounds=$(grep -i 'RUN STRESS' <<<"$ui" | grep -o 'bounds="[^"]*"' | head -1 || true)
    if [[ -n "$bounds" ]]; then
      local n=($(echo "$bounds" | grep -oE '[0-9]+'))
      adb shell input tap $(((n[0] + n[2]) / 2)) $(((n[1] + n[3]) / 2))
    fi
    sleep 2
  done
  echo "button not found" >&2
  return 1
}

for i in $(seq 1 "$LAUNCHES"); do
  adb shell am force-stop "$APP"
  adb logcat -c
  adb shell am start -n "$APP/.MainActivity" >/dev/null
  tap_button
  for _ in $(seq 1 600); do
    line=$(adb logcat -d -s ReactNativeJS:I | grep '\[STRESS\] done' | tail -1 || true)
    [[ -n "$line" ]] && break
    sleep 2
  done
  adb logcat -d -s ReactNativeJS:I >> "$OUT" || true
  echo "launch $i: ${line##*\[STRESS\] }"
done
