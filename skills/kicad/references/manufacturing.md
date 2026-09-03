# Manufacturing

## What a fab package contains

```
build/fab/
├── gerbers/           # one file per layer, Gerber X2 (RS-274X with attributes)
├── drill/             # Excellon: plated + non-plated separately, plus a map
├── board-pos.csv      # pick-and-place, top and bottom
├── bom.csv            # with MPN, quantity, DNP flags
├── assembly-top.pdf   # F.Fab + refdes + outline
├── board.step         # for the mechanical team
└── MANIFEST.txt       # git SHA, KiCad version, generation date, file checksums
```

`scripts/export-fab.sh` produces exactly this. The manifest matters: months later,
the only way to answer "which revision is on this board" is a record tying the
package to a commit.

## Ordering conventions

Generate fab output from a clean, committed tree — never from a working directory
with uncommitted edits. Tag the commit (`fab-rev-b`, `v1.2-fab`) and put the SHA in
the manifest. When the fab comes back with a question three weeks later, that tag
is the only reliable answer.

Re-run `scripts/kicad-check.sh` immediately before export. Refill zones, commit the
refill separately, then export.

## Stackup and impedance

Use the fab's published stackup, not a generic one. Typical 4-layer 1.6 mm:

| Layer | Copper | Dielectric below |
| --- | --- | --- |
| `F.Cu` | 1 oz (35 µm) plated | 0.2 mm prepreg |
| `In1.Cu` (GND) | 0.5 oz | 1.065 mm core |
| `In2.Cu` (PWR) | 0.5 oz | 0.2 mm prepreg |
| `B.Cu` | 1 oz plated | — |

Consequences worth stating up front:

- The thick core between the inner layers means an `F.Cu`↔`In1.Cu` pair is the
  only tightly-coupled microstrip; routing a controlled-impedance signal on the
  inner layers of this stackup gives a different geometry entirely.
- Single-ended 50 Ω on `F.Cu` over `In1.Cu` at 0.2 mm prepreg is roughly 0.34 mm
  wide — but use *the fab's* calculator with *their* Dk, and put the requested
  impedance in the fab notes so they can adjust the width.
- Asking for controlled impedance adds cost and a coupon; ask only when a signal
  actually needs it.

## Common DFM constraints

Standard, low-cost process (most fabs, no upcharge):

| Constraint | Typical limit |
| --- | --- |
| Min trace / space | 0.15 mm (6 mil) |
| Min via drill | 0.3 mm, 0.6 mm pad |
| Min annular ring | 0.13 mm |
| Min hole-to-copper | 0.25 mm |
| Copper to board edge | 0.3 mm |
| Min silkscreen width / height | 0.15 mm / 1.0 mm |
| Solder-mask sliver | 0.1 mm |
| Min slot width | 1.0 mm |

Below these you are in the fab's advanced process: higher price, longer lead time,
lower yield. Encode the limits as netclass and board constraints in `.kicad_pro`
so DRC enforces them, rather than relying on review to catch a violation.

Via-in-pad requires filling and capping — call it out explicitly; an unfilled
via in a pad wicks solder off the joint.

## JLCPCB specifics

- Accepts a zip of Gerber X2 + Excellon directly. IPC-2581 is accepted for newer
  orders; gerbers remain the safe default.
- Assembly (PCBA) wants its own CSV columns: `Designator, Val, Package, Mid X,
  Mid Y, Rotation, Layer` for placement, and `Comment, Designator, Footprint,
  LCSC Part #` for the BOM. `kicad-cli pcb export pos --format csv` gets the
  geometry right; the headers still need renaming and the LCSC column adding —
  the `kicad-jlcpcb-tools` plugin automates both if you do this often.
- **Rotations differ.** JLC's part library orientation frequently disagrees with
  the KiCad footprint's, most notoriously on polarised parts. Check every
  polarised and multi-pin part in their online preview before confirming.
  A whole board of backwards diodes is the classic outcome of skipping this.
- Their basic-parts library is much cheaper than extended parts, which incur a
  per-reel loading fee. Choosing basic parts at schematic time is worth real money
  on small runs.

## PCBWay and others

- PCBWay accepts gerbers or the native `.kicad_pcb`; native upload avoids gerber
  generation mistakes but gives you no artifact to archive. Send gerbers, archive
  gerbers.
- Both houses run a DFM review before fabrication and will email queries. Answer
  them from the manifest's git SHA, and if a change is needed, change the source
  and regenerate — never hand-edit a gerber.

## Assembly notes to include

Write a short `README` into the fab package covering: board thickness, copper
weight, surface finish (ENIG for fine-pitch and for anything with a press-fit or
edge connector; HASL is fine and cheaper otherwise), solder-mask and silkscreen
colours, impedance requirements if any, and any part that must not be substituted.
The absence of that note is how a board comes back with a "functionally
equivalent" regulator that is not.
