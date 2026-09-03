# KiCad file formats

## The project triplet

| File | Format | Role |
| --- | --- | --- |
| `board.kicad_pro` | JSON | Project settings: design rules, netclasses, layer stackup, plot params, text variables |
| `board.kicad_sch` | S-expression | Schematic. One file per sheet; the root sheet references children |
| `board.kicad_pcb` | S-expression | Layout: stackup, footprints, tracks, zones, graphics |
| `fp-lib-table`, `sym-lib-table` | S-expression | Project-scoped library tables (see `libraries.md`) |
| `board.kicad_prl` | JSON | Local UI state (visible layers, last used tool). Not shared — gitignore it |
| `*.kicad_dru` | S-expression | Custom design rules, applied on top of `.kicad_pro` constraints |

## S-expression shape

```
(kicad_pcb
  (version 20241229)
  (generator "pcbnew")
  (general (thickness 1.6))
  (layers (0 "F.Cu" signal) (31 "B.Cu" signal) ...)
  (footprint "murmex:LED_0603"
    (layer "F.Cu")
    (uuid "8b2c...")
    (at 129.5 87.25 90)
    (property "Reference" "D3" (at 0 -1.5 0) (layer "F.SilkS") ...)
    (pad "1" smd roundrect (at -0.8 0) (size 0.9 0.8) (layers "F.Cu" "F.Paste" "F.Mask")
      (net 14 "LED_A") (uuid "...")))
  ...)
```

Three things follow from this structure and matter more than anything else:

**UUIDs are the identity of every object.** Footprints, pads, symbols, sheets,
and nets are cross-referenced by UUID between the schematic and the board. If you
regenerate a file, or copy a block and reuse its UUIDs, KiCad will either drop the
link on the next schematic↔board update or silently merge two distinct objects.
Never invent, duplicate, or renumber a UUID by hand.

**Net numbers are positional, not stable.** `(net 14 "LED_A")` — the integer is an
index into the board's `(net ...)` table and is rewritten whenever nets change.
Match on the net *name*, never the number.

**Coordinates are millimetres, Y grows downward.** `(at X Y [rotation])` on a
footprint is absolute board position; `(at X Y)` inside a footprint is relative to
the footprint origin and, for pads, is rotated with the parent. Rotation is in
degrees counter-clockwise. A footprint at rotation 90 has its child geometry
rotated too — do not "fix" placement by editing pad offsets.

## What is safe to edit as text

Safe:

- `.kicad_pro` — netclasses, clearance and width constraints, via sizes, text
  variables, plot parameters. It is plain JSON and the schema is stable within a
  major version.
- Field/property *values* on symbols and footprints: MPN, datasheet, description.
- `dnp` and `exclude_from_bom` flags: `(property "Reference" "R7" ...)` sits
  alongside `(dnp yes)` on the symbol in `.kicad_sch`.
- Library tables (`fp-lib-table`, `sym-lib-table`).
- `.kicad_dru` custom rules.
- `.kicad_mod` footprint sources in a library you own (see `libraries.md`).

Not safe — use the GUI or a scripted transform with the KiCad Python API:

- Track, via, and zone geometry.
- Footprint placement in a finished layout (rotation and origin interact with
  courtyard and 3D-model offsets).
- Anything that adds or removes a UUID-bearing object in `.kicad_sch` or
  `.kicad_pcb`.
- Pad stacks and layer assignments.

When an edit is not safe, say so and describe the GUI steps instead. Producing a
broken board file is worse than producing no change.

## Layer names

The canonical tokens in the file are `F.Cu`, `B.Cu`, `In1.Cu`…, `F.SilkS`,
`B.SilkS`, `F.Mask`, `F.Paste`, `F.CrtYd`, `F.Fab`, `Edge.Cuts`, `User.Comments`.
The KiCad 7+ GUI displays "F.Silkscreen" for `F.SilkS`, and some `kicad-cli`
flags accept the display form. Read the `(layers ...)` block at the top of the
board file for the exact strings that board uses, and prefer
`--board-plot-params` over a hand-written `--layers` list (see `cli.md`).

## Git hygiene

`.gitignore`:

```gitignore
*-backups/
*.kicad_pcb-bak
*.kicad_sch-bak
*.kicad_prl
fp-info-cache
~*.lck
build/
```

Commit `.kicad_pro`. It holds the design rules, and losing it means losing the
constraints the board was checked against.

**Diffs.** A one-track change touches a handful of lines; a re-save with no edits
touches none, because KiCad's writer is deterministic. If a "no-op" save produces
a large diff, the file was written by a different KiCad version — flag that, since
it means the format was upgraded and the project no longer opens in the older
version.

**Merge conflicts in `.kicad_pcb` are not text-mergeable.** The net table, UUIDs,
and zone fills are interdependent. Resolve by picking one side wholesale and
re-applying the other change in the GUI. Do not hand-merge hunks. Prevent this by
locking layout work to one person at a time — layout is the part of hardware
design that does not parallelise.

**Zone fills** are stored in the board file. A refill produces a very large diff
with no logical change. Convention: refill and commit as its own commit, right
before generating fab output, so it never obscures a real edit.
