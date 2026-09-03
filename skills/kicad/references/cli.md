# kicad-cli

Headless driver for KiCad, shipped with the application. Everything below assumes
KiCad 8.x or 9.x; subcommands and flags changed between majors, so run
`kicad-cli version` and `kicad-cli <group> <cmd> --help` before scripting against
an unfamiliar install.

macOS path when not on `PATH`:
`/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli`

## Checks

```bash
# ERC — schematic
kicad-cli sch erc \
  --output build/erc.json --format json \
  --severity-error --exit-code-violations \
  board.kicad_sch

# DRC — board
kicad-cli pcb drc \
  --output build/drc.json --format json \
  --severity-error --exit-code-violations \
  board.kicad_pcb
```

`--exit-code-violations` makes the command exit non-zero when violations remain —
the flag that turns these into a CI gate. `--format json` gives you structured
output with a `violations` array; each entry carries `severity`, `description`,
and `items` with coordinates and UUIDs. Parse that rather than scraping the report
text. Add `--schematic-parity` to `pcb drc` to catch board/schematic divergence.

`scripts/kicad-check.sh` wraps both.

## Schematic exports

```bash
kicad-cli sch export pdf     --output build/schematic.pdf board.kicad_sch
kicad-cli sch export svg     --output build/sch/          board.kicad_sch
kicad-cli sch export netlist --output build/netlist.net   board.kicad_sch

kicad-cli sch export bom \
  --output build/bom.csv \
  --fields 'Reference,Value,Footprint,MPN,Manufacturer,${QUANTITY},${DNP}' \
  --labels 'Refs,Value,Footprint,MPN,Mfr,Qty,DNP' \
  --group-by 'Value,Footprint,MPN' \
  --exclude-dnp \
  board.kicad_sch
```

`sch export bom` is KiCad 8+. On 7.x the equivalent is
`sch export python-bom` plus an XSLT/Python post-processor. `${QUANTITY}`, `${DNP}`,
and `${REFERENCE}` are computed fields, distinct from user fields like `MPN`.

Decide deliberately whether to `--exclude-dnp`: the assembler needs the DNP rows
*marked*, while a cost roll-up needs them gone.

## Board exports

```bash
# Gerbers — preferred: use the plot settings stored in the project
kicad-cli pcb export gerbers \
  --output build/fab/ --board-plot-params \
  board.kicad_pcb

# Gerbers — explicit layer list, when no stored settings exist
kicad-cli pcb export gerbers \
  --output build/fab/ \
  --layers 'F.Cu,B.Cu,F.Paste,B.Paste,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts' \
  --subtract-soldermask --use-drill-file-origin \
  board.kicad_pcb

# Drill files
kicad-cli pcb export drill \
  --output build/fab/ --format excellon \
  --drill-origin plot --excellon-separate-th --generate-map --map-format gerberx2 \
  board.kicad_pcb

# Pick-and-place
kicad-cli pcb export pos \
  --output build/fab/board-pos.csv \
  --format csv --units mm --side both --use-drill-file-origin \
  board.kicad_pcb

# Mechanical
kicad-cli pcb export step --output build/board.step --subst-models board.kicad_pcb
kicad-cli pcb export vrml --output build/board.wrl board.kicad_pcb

# Documentation
kicad-cli pcb export pdf --output build/fab/assembly-top.pdf \
  --layers 'F.Fab,F.SilkS,Edge.Cuts' board.kicad_pcb
kicad-cli pcb render --output build/render-top.png --side top --quality high board.kicad_pcb

# Single-file interchange (KiCad 8+), accepted by an increasing number of fabs
kicad-cli pcb export ipc2581 --output build/board.xml board.kicad_pcb
```

Prefer `--board-plot-params`: it uses the plot configuration saved in
`.kicad_pro`, so the CLI output matches what the GUI would produce and the layer
set stays correct as the stackup changes. Reach for `--layers` only when the
project has no stored settings, and read the board's own `(layers ...)` block for
the exact token spellings.

`--use-drill-file-origin` on gerbers and position files, with
`--drill-origin plot` on the drill export, keeps every output on one coordinate
system. Mismatched origins between gerbers and the position file is a common
assembly failure, and it is invisible until the machine misplaces every part.

## Library maintenance

```bash
kicad-cli sym upgrade  library.kicad_sym          # migrate to the current format
kicad-cli fp  upgrade  murmex.pretty/             # in place
kicad-cli sym export svg --output build/syms/ library.kicad_sym
kicad-cli fp  export svg --output build/fps/  murmex.pretty/
```

`upgrade` rewrites files into the running version's format. That is a one-way
door for anyone still on the older KiCad — commit before running it, and say so.

## CI

```yaml
# .github/workflows/kicad.yml
jobs:
  checks:
    runs-on: ubuntu-latest
    container: ghcr.io/kicad/kicad:9.0
    steps:
      - uses: actions/checkout@v4
      - run: kicad-cli sch erc --exit-code-violations --severity-error --format json --output erc.json *.kicad_sch
      - run: kicad-cli pcb drc --exit-code-violations --severity-error --schematic-parity --format json --output drc.json *.kicad_pcb
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: reports, path: "*.json" }
```

Gate on ERC/DRC, not on export success — a board can export perfectly and still be
unbuildable.
