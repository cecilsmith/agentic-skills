---
name: kicad
description: >-
  Design, review, edit, and produce fabrication outputs for KiCad projects.
  Use when working with .kicad_sch, .kicad_pcb, .kicad_pro, .kicad_mod, or
  .kicad_sym files; running ERC or DRC; reviewing a schematic or a PCB layout;
  managing symbol, footprint, or 3D-model libraries and library tables;
  generating gerbers, drill files, pick-and-place, BOM, or STEP output; or
  preparing a board for JLCPCB, PCBWay, or another fab house.
metadata:
  version: 0.1.0
  kicad-versions: "8.x, 9.x"
---

# KiCad

KiCad files are plain-text S-expressions (`.kicad_sch`, `.kicad_pcb`, `.kicad_mod`,
`.kicad_sym`) plus a JSON project file (`.kicad_pro`). They are readable and
diffable, which makes them tempting to edit freely. Most of the damage an agent
can do to a KiCad project comes from treating them as ordinary text files.

## Orient first

Before touching anything, establish what you are working with:

```bash
kicad-cli version                      # flags differ across 7/8/9 — check before scripting
ls *.kicad_pro *.kicad_sch *.kicad_pcb # the project triplet
cat fp-lib-table sym-lib-table 2>/dev/null   # project-scoped library tables
grep -m1 '(version' board.kicad_pcb    # file-format epoch
```

If `kicad-cli` is not on `PATH`, on macOS it lives at
`/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli`.

## Rules

1. **Never regenerate a `.kicad_sch` or `.kicad_pcb` wholesale.** Every symbol,
   footprint, net, and sheet carries a UUID that other files reference. Rewriting
   the file breaks that linkage silently — the board opens, but annotations,
   net names, and schematic↔layout sync are gone. Make surgical edits.
2. **Never reformat.** Do not pretty-print, re-indent, or reorder S-expressions.
   KiCad rewrites its own formatting on save; a reformatted file produces a diff
   nobody can review and hides the real change.
3. **Text-edit only what is safe.** Field values, `dnp` / `exclude_from_bom`
   flags, library tables, and design rules in `.kicad_pro` (JSON) are fine to
   edit. Placement, routing, zone geometry, and pad shapes are not — those belong
   in the GUI or in a scripted transform. See `references/file-formats.md` for
   the line between the two.
4. **Verify after every edit.** Run `scripts/kicad-check.sh` (ERC + DRC). An edit
   that has not been re-checked is not finished.
5. **Write generated output to a build directory**, never beside the sources, and
   never commit gerbers, `*-backups/`, `*.kicad_*-bak`, or autosave files.
6. **State the KiCad version your answer assumes.** Design-rule syntax, layer
   names, and `kicad-cli` subcommands all moved between major versions.

## Where to look

| Task | Read |
| --- | --- |
| Understand or hand-edit the file formats; git hygiene, diffs, merge conflicts | `references/file-formats.md` |
| Symbol/footprint/3D libraries, `fp-lib-table`, path variables, naming | `references/libraries.md` |
| Any `kicad-cli` invocation — ERC, DRC, exports, rendering | `references/cli.md` |
| Reviewing a schematic or layout before release | `references/review-checklist.md` |
| Fab outputs, stackup, DFM constraints, JLCPCB/PCBWay specifics | `references/manufacturing.md` |

Load a reference when the task reaches it, not before.

## Scripts

All scripts take the project directory as their first argument and default to the
current directory.

| Script | Purpose |
| --- | --- |
| `scripts/kicad-check.sh` | Runs ERC and DRC, prints violations, exits non-zero if any error-severity violation remains. Use this as the gate on every change. |
| `scripts/export-fab.sh` | Produces a complete fab package — gerbers, drill, pick-and-place, BOM, STEP — into `build/fab/` with a manifest. |
| `scripts/lint-footprints.py` | Checks a `.pretty` library for missing courtyards, misplaced reference/value text, absolute 3D-model paths, and wrong footprint attributes. |

Run `scripts/kicad-check.sh` before proposing that any change is complete.

## Working with a review request

When asked to review a board, do not freelance. Run the checks first
(`scripts/kicad-check.sh`), then walk `references/review-checklist.md` in order
and report findings grouped by severity, each with the specific net, refdes, or
coordinate it applies to. A review that says "consider adding decoupling" without
naming the pin is not useful.
