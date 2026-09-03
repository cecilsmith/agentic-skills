#!/usr/bin/env bash
# Generate a complete fabrication package into <project>/build/fab/.
# Runs checks first and refuses to export a board with DRC errors.
#
# Usage: export-fab.sh [project-dir] [--skip-checks] [--dirty]
#   --skip-checks  export even if ERC/DRC fail (records this in the manifest)
#   --dirty        allow export from a tree with uncommitted changes

set -euo pipefail

PROJECT_DIR="."
SKIP_CHECKS=0
ALLOW_DIRTY=0
for arg in "$@"; do
  case "$arg" in
    --skip-checks) SKIP_CHECKS=1 ;;
    --dirty)       ALLOW_DIRTY=1 ;;
    -h|--help)     sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             PROJECT_DIR="$arg" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_cli() {
  if command -v kicad-cli >/dev/null 2>&1; then command -v kicad-cli
  elif [ -x /Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli ]; then
    echo /Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
  else echo "error: kicad-cli not found" >&2; exit 127; fi
}
KICAD_CLI="$(find_cli)"

cd "$PROJECT_DIR"
PCB="$(find . -maxdepth 2 -name '*.kicad_pcb' -not -path './build/*' | head -1 || true)"
SCH="$(find . -maxdepth 2 -name '*.kicad_sch' -not -path './build/*' | head -1 || true)"
[ -n "$PCB" ] || { echo "error: no .kicad_pcb found under $(pwd)" >&2; exit 2; }
BASE="$(basename "$PCB" .kicad_pcb)"

# Refuse to ship from a tree nobody can reproduce.
GIT_SHA="not-a-git-repo"
if git rev-parse --git-dir >/dev/null 2>&1; then
  GIT_SHA="$(git rev-parse HEAD)"
  if [ -n "$(git status --porcelain)" ]; then
    if [ "$ALLOW_DIRTY" -eq 1 ]; then
      GIT_SHA="$GIT_SHA-dirty"
      echo "warning: exporting from a dirty tree"
    else
      echo "error: uncommitted changes. Commit first, or pass --dirty." >&2
      git status --short >&2
      exit 3
    fi
  fi
fi

CHECKS="passed"
if [ "$SKIP_CHECKS" -eq 0 ]; then
  "$SCRIPT_DIR/kicad-check.sh" . || { echo "error: checks failed. Fix, or pass --skip-checks." >&2; exit 4; }
else
  CHECKS="SKIPPED"
  echo "warning: checks skipped"
fi

OUT="build/fab"
rm -rf "$OUT"; mkdir -p "$OUT/gerbers" "$OUT/drill"

echo "gerbers"
if grep -q '"plot"' "$BASE.kicad_pro" 2>/dev/null; then
  "$KICAD_CLI" pcb export gerbers --output "$OUT/gerbers/" --board-plot-params "$PCB"
else
  echo "  note: no stored plot params; using an explicit layer list"
  "$KICAD_CLI" pcb export gerbers --output "$OUT/gerbers/" \
    --layers 'F.Cu,B.Cu,F.Paste,B.Paste,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts' \
    --subtract-soldermask --use-drill-file-origin "$PCB"
fi

echo "drill"
"$KICAD_CLI" pcb export drill --output "$OUT/drill/" --format excellon \
  --drill-origin plot --excellon-separate-th --generate-map --map-format gerberx2 "$PCB"

echo "position"
"$KICAD_CLI" pcb export pos --output "$OUT/${BASE}-pos.csv" \
  --format csv --units mm --side both --use-drill-file-origin "$PCB"

echo "step"
"$KICAD_CLI" pcb export step --output "build/${BASE}.step" --subst-models "$PCB" || \
  echo "  warning: STEP export failed (usually a missing 3D model)"

echo "assembly drawings"
"$KICAD_CLI" pcb export pdf --output "$OUT/${BASE}-assembly-top.pdf" \
  --layers 'F.Fab,F.SilkS,Edge.Cuts' "$PCB" || true
"$KICAD_CLI" pcb export pdf --output "$OUT/${BASE}-assembly-bottom.pdf" \
  --layers 'B.Fab,B.SilkS,Edge.Cuts' --mirror "$PCB" || true

if [ -n "$SCH" ]; then
  echo "schematic + bom"
  "$KICAD_CLI" sch export pdf --output "$OUT/${BASE}-schematic.pdf" "$SCH" || true
  "$KICAD_CLI" sch export bom --output "$OUT/${BASE}-bom.csv" \
    --fields 'Reference,Value,Footprint,MPN,Manufacturer,${QUANTITY},${DNP}' \
    --labels 'Designator,Value,Footprint,MPN,Manufacturer,Qty,DNP' \
    --group-by 'Value,Footprint,MPN' "$SCH" \
    || echo "  warning: BOM export failed (KiCad 8+ required for 'sch export bom')"
fi

{
  echo "project:      $BASE"
  echo "generated:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git sha:      $GIT_SHA"
  echo "kicad-cli:    $("$KICAD_CLI" version 2>/dev/null || echo unknown)"
  echo "erc/drc:      $CHECKS"
  echo
  echo "files:"
  find "$OUT" -type f | sort | while read -r f; do
    printf '  %s  %s\n' "$(shasum -a 256 "$f" | cut -c1-16)" "${f#"$OUT"/}"
  done
} > "$OUT/MANIFEST.txt"

echo
cat "$OUT/MANIFEST.txt"
echo
echo "package: $(pwd)/$OUT"
