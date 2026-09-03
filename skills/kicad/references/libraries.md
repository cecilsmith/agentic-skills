# Symbol, footprint, and 3D-model libraries

## The three layers of indirection

A part on a board is three separate assets joined by name:

```
symbol (.kicad_sym, in a library)      →  schematic
   └─ Footprint field: "murmex:LED_0603"
        └─ footprint (.kicad_mod, in a <name>.pretty directory)  →  board
             └─ (model "${KIPRJMOD}/3dmodel/LED_0603.step" ...)  →  3D view / STEP export
```

Break any link and the failure appears late: a missing footprint blocks netlist
import; a missing 3D model only shows up when someone asks for a STEP file for
the enclosure.

## Library tables

`sym-lib-table` and `fp-lib-table` map a nickname to a path. They exist in two
scopes:

- **Global** — `~/Library/Preferences/kicad/<ver>/` (macOS),
  `~/.config/kicad/<ver>/` (Linux). Machine-specific; never commit.
- **Project** — beside the `.kicad_pro`. Committed, and the reason a project
  opens correctly on someone else's machine.

```lisp
(fp_lib_table
  (version 7)
  (lib (name "murmex")(type "KiCad")(uri "${KIPRJMOD}/../KiCad-Library/footprint/murmex.pretty")(options "")(descr "House footprints"))
)
```

The nickname (`murmex`) is what appears in every `Footprint` field, so renaming a
library breaks every board that used it. Choose the nickname once.

## Path variables

Always use a variable, never an absolute path:

| Variable | Expands to |
| --- | --- |
| `${KIPRJMOD}` | Directory containing the `.kicad_pro`. Resolves per-project — the right default for a library vendored next to or near the project |
| `${KICAD9_3DMODEL_DIR}` | Stock 3D models (`KICAD8_…` on 8.x — version-suffixed, so it changes on upgrade) |
| `${KICAD9_FOOTPRINT_DIR}` | Stock footprints |
| A custom variable | Define in **Preferences → Configure Paths**, e.g. `${MURMEX_LIB}`, when the library lives outside the project tree |

An absolute path like `/Users/you/Documents/GitHub/KiCad-Library/...` works on
exactly one machine. `scripts/lint-footprints.py` flags these.

## House library layout

A personal library repo, kept separate from any board that uses it:

```
KiCad-Library/
├── symbol/
│   └── murmex.kicad_sym        # one file, many symbols
├── footprint/
│   └── murmex.pretty/          # a directory; one .kicad_mod per footprint
│       ├── LED_0603.kicad_mod
│       └── USB_C_Receptacle_HRO_TYPE-C-31-M-12.kicad_mod
├── 3dmodel/
│   ├── LED_0603.step           # .step for mechanical/STEP export
│   └── LED_0603.wrl            # .wrl for the coloured 3D viewer
└── tools/
```

Consume it from a board either as a git submodule or via a custom path variable.
A submodule pins the library version to the board revision, which is what you
want when a footprint changes after a board has been fabricated.

**Naming.** Follow the KiCad convention — `<Device>_<Package>_<Variant>`, e.g.
`R_0402_1005Metric`, `SOT-23-5`, `QFN-32-1EP_5x5mm_P0.5mm_EP3.4x3.4mm`. Encode the
package, not the part number: one footprint serves every 0402 resistor. Put the
MPN in the symbol's fields, not the footprint name.

## Footprint anatomy

Every footprint has an obligatory set of layers. Getting these wrong is the most
common library defect:

| Layer | Contents | Rule |
| --- | --- | --- |
| `F.Cu` + pads | Copper pads | Pad 1 marked; pad numbering matches the datasheet, not visual order |
| `F.Paste` | Stencil apertures | Reduced from pad size on large thermal pads (typically 50–80 % coverage, windowpaned) |
| `F.Mask` | Solder-mask openings | Normally auto-generated from pads; explicit only for deliberate mask changes |
| `F.SilkS` | Silkscreen outline, pin-1 marker, `REF**` reference text | Must not overlap pads — silk on a pad interferes with wetting |
| `F.CrtYd` | Courtyard: the keep-out rectangle | **Required.** DRC courtyard checks are the main defense against parts colliding. 0.25 mm clearance for nominal density |
| `F.Fab` | Body outline, pin-1 marker, `${REFERENCE}` value text | Documentation layer; drives assembly drawings |

The reference field belongs on `F.SilkS` with value `REF**`; the value field
belongs on `F.Fab`. `scripts/lint-footprints.py` checks this.

**Density levels (IPC-7351).** `_Nominal` (Level B) is the default. Use `_Least`
(Level C) only when space forces it and you are confident in the assembler;
`_Most` (Level A) for hand-soldering or wave-soldered through-hole. Do not mix
levels across a board without a reason.

**Attributes.** `(attr smd)` or `(attr through_hole)` must be set — pick-and-place
export filters on it, so an unmarked SMD part silently vanishes from the position
file and does not get placed.

## Adding a part: order of operations

1. Footprint first, verified against the datasheet's recommended land pattern —
   check pad pitch, pad size, and courtyard against the drawing, not against a
   similar existing footprint.
2. 3D model, referenced with `${KIPRJMOD}` or a custom variable, aligned to the
   footprint origin.
3. Symbol, with the `Footprint` field pre-filled to `nickname:footprint_name`, and
   fields for MPN, manufacturer, datasheet URL, and distributor part number.
4. `scripts/lint-footprints.py` over the library.
5. Print the footprint 1:1 and lay the physical part on it before committing to a
   fab run. This catches unit errors (mil vs mm) that no linter will.
