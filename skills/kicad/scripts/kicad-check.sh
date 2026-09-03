#!/usr/bin/env bash
# Run ERC and DRC on a KiCad project. Exits non-zero if error-severity
# violations remain. Reports land in <project>/build/.
#
# Usage: kicad-check.sh [project-dir] [--warnings]
#   --warnings   also fail on warning-severity violations

set -euo pipefail

PROJECT_DIR="."
FAIL_ON_WARNINGS=0
for arg in "$@"; do
  case "$arg" in
    --warnings) FAIL_ON_WARNINGS=1 ;;
    -h|--help)  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          PROJECT_DIR="$arg" ;;
  esac
done

find_cli() {
  if command -v kicad-cli >/dev/null 2>&1; then
    command -v kicad-cli
  elif [ -x /Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli ]; then
    echo /Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
  else
    echo "error: kicad-cli not found on PATH or in /Applications/KiCad" >&2
    exit 127
  fi
}
KICAD_CLI="$(find_cli)"

cd "$PROJECT_DIR"
SCH="$(find . -maxdepth 2 -name '*.kicad_sch' -not -path './build/*' | head -1 || true)"
PCB="$(find . -maxdepth 2 -name '*.kicad_pcb' -not -path './build/*' | head -1 || true)"
if [ -z "$SCH" ] && [ -z "$PCB" ]; then
  echo "error: no .kicad_sch or .kicad_pcb found under $(pwd)" >&2
  exit 2
fi

mkdir -p build
echo "kicad-cli: $("$KICAD_CLI" version 2>/dev/null || echo unknown)"
STATUS=0

if [ -n "$SCH" ]; then
  echo "ERC  $SCH"
  "$KICAD_CLI" sch erc --output build/erc.json --format json \
      --severity-all --exit-code-violations "$SCH" >/dev/null 2>&1 || true
fi
if [ -n "$PCB" ]; then
  echo "DRC  $PCB"
  "$KICAD_CLI" pcb drc --output build/drc.json --format json \
      --severity-all --schematic-parity --exit-code-violations "$PCB" >/dev/null 2>&1 || true
fi

python3 - "$FAIL_ON_WARNINGS" <<'PYEOF' || STATUS=$?
import json, os, sys

fail_on_warnings = sys.argv[1] == "1"
worst = 0

for label, path in (("ERC", "build/erc.json"), ("DRC", "build/drc.json")):
    if not os.path.exists(path):
        continue
    try:
        with open(path) as fh:
            report = json.load(fh)
    except (json.JSONDecodeError, OSError) as exc:
        print(f"{label}: could not read {path} ({exc})")
        worst = max(worst, 2)
        continue

    groups = []
    for key in ("violations", "unconnected_items", "schematic_parity"):
        groups.extend(report.get(key) or [])
    # ERC reports nest violations under each sheet.
    for sheet in report.get("sheets") or []:
        groups.extend(sheet.get("violations") or [])

    counts = {}
    for item in groups:
        counts[item.get("severity", "unknown")] = counts.get(item.get("severity", "unknown"), 0) + 1

    if not groups:
        print(f"{label}: clean")
        continue

    summary = ", ".join(f"{n} {sev}" for sev, n in sorted(counts.items()))
    print(f"{label}: {summary}")
    for item in groups:
        sev = item.get("severity", "unknown")
        if sev not in ("error", "warning"):
            continue
        desc = (item.get("description") or item.get("type") or "").strip()
        where = ""
        items = item.get("items") or []
        if items:
            pos = items[0].get("pos") or {}
            if "x" in pos:
                where = f"  @ ({pos['x']:.2f}, {pos['y']:.2f})"
            desc_item = items[0].get("description")
            if desc_item and desc_item not in desc:
                where = f"  [{desc_item}]" + where
        print(f"  {sev:<7} {desc}{where}")

    if counts.get("error"):
        worst = max(worst, 1)
    if fail_on_warnings and counts.get("warning"):
        worst = max(worst, 1)

sys.exit(worst)
PYEOF

if [ "$STATUS" -eq 0 ]; then
  echo "OK — reports in $(pwd)/build/"
else
  echo "FAILED — see $(pwd)/build/erc.json and drc.json"
fi
exit "$STATUS"
