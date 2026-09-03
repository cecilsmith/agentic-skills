#!/usr/bin/env python3
"""Lint KiCad footprints for the defects that survive DRC and reach the fab.

Usage:
    lint-footprints.py <path>... [--strict]

<path> may be a .kicad_mod file, a .pretty directory, or a directory containing
.pretty libraries. --strict makes warnings fail the run.

Exit status: 0 clean, 1 findings, 2 usage/parse error.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

# --- S-expression parsing -------------------------------------------------

class Node(list):
    """An S-expression list. Node[0] is the tag when it is an atom."""

    @property
    def tag(self) -> str:
        return self[0] if self and isinstance(self[0], str) else ""

    def children(self, tag: str):
        return [c for c in self if isinstance(c, Node) and c.tag == tag]

    def child(self, tag: str):
        found = self.children(tag)
        return found[0] if found else None

    def atoms(self):
        return [c for c in self[1:] if isinstance(c, str)]


def parse(text: str) -> Node:
    pos = 0
    length = len(text)

    def skip_ws():
        nonlocal pos
        while pos < length:
            if text[pos].isspace():
                pos += 1
            else:
                return

    def read_node() -> Node:
        nonlocal pos
        assert text[pos] == "("
        pos += 1
        node = Node()
        while True:
            skip_ws()
            if pos >= length:
                raise ValueError("unexpected end of file")
            ch = text[pos]
            if ch == ")":
                pos += 1
                return node
            if ch == "(":
                node.append(read_node())
            elif ch == '"':
                pos += 1
                buf = []
                while pos < length and text[pos] != '"':
                    if text[pos] == "\\" and pos + 1 < length:
                        pos += 1
                    buf.append(text[pos])
                    pos += 1
                pos += 1
                node.append("".join(buf))
            else:
                start = pos
                while pos < length and not text[pos].isspace() and text[pos] not in "()":
                    pos += 1
                node.append(text[start:pos])

    skip_ws()
    if pos >= length or text[pos] != "(":
        raise ValueError("file does not start with an S-expression")
    return read_node()


# --- checks ---------------------------------------------------------------

ERROR, WARN = "error", "warn"


def layers_used(node: Node, out: set) -> set:
    """Collect every layer token appearing anywhere in the tree."""
    for child in node:
        if isinstance(child, Node):
            if child.tag == "layer":
                out.update(child.atoms())
            elif child.tag == "layers":
                out.update(child.atoms())
            layers_used(child, out)
    return out


def text_item(fp: Node, kind: str):
    """Return (value, layer) for Reference or Value, across format versions."""
    for prop in fp.children("property"):
        atoms = prop.atoms()
        if atoms and atoms[0] == kind:
            layer = prop.child("layer")
            return (atoms[1] if len(atoms) > 1 else "",
                    layer.atoms()[0] if layer and layer.atoms() else "")
    for txt in fp.children("fp_text"):  # KiCad 6 and earlier
        atoms = txt.atoms()
        if atoms and atoms[0] == kind.lower():
            layer = txt.child("layer")
            return (atoms[1] if len(atoms) > 1 else "",
                    layer.atoms()[0] if layer and layer.atoms() else "")
    return (None, None)


def check_footprint(path: Path) -> list:
    findings = []

    def add(sev, msg):
        findings.append((sev, msg))

    try:
        fp = parse(path.read_text(encoding="utf-8"))
    except (ValueError, OSError, UnicodeDecodeError) as exc:
        return [(ERROR, f"could not parse: {exc}")]

    if fp.tag not in ("footprint", "module"):
        return [(ERROR, f"root node is '{fp.tag}', expected 'footprint'")]

    name = fp.atoms()[0] if fp.atoms() else ""
    if name and name != path.stem:
        add(WARN, f"footprint name '{name}' does not match filename '{path.stem}'")

    layers = layers_used(fp, set())

    # Courtyard: the single most important line of defense against collisions.
    if not ({"F.CrtYd", "B.CrtYd"} & layers):
        add(ERROR, "no courtyard (F.CrtYd/B.CrtYd) — DRC cannot check for collisions")

    if not ({"F.Fab", "B.Fab"} & layers):
        add(WARN, "no fabrication layer (F.Fab/B.Fab) — assembly drawings will be blank")

    ref_value, ref_layer = text_item(fp, "Reference")
    if ref_value is None:
        add(ERROR, "no Reference field")
    else:
        if ref_value != "REF**":
            add(WARN, f"Reference value is '{ref_value}', expected 'REF**'")
        if ref_layer and not ref_layer.endswith(".SilkS"):
            add(WARN, f"Reference is on {ref_layer}, expected F.SilkS or B.SilkS")

    val_value, val_layer = text_item(fp, "Value")
    if val_value is None:
        add(ERROR, "no Value field")
    elif val_layer and not val_layer.endswith(".Fab"):
        add(WARN, f"Value is on {val_layer}, expected F.Fab or B.Fab")

    attr = fp.child("attr")
    attr_atoms = attr.atoms() if attr else []
    if not ({"smd", "through_hole"} & set(attr_atoms)):
        add(ERROR, "no (attr smd) or (attr through_hole) — the part will be "
                   "dropped from the pick-and-place file")

    pads = fp.children("pad")
    if not pads:
        add(WARN, "no pads")
    else:
        numbers = [p.atoms()[0] for p in pads if p.atoms()]
        if numbers and "1" not in numbers and "A1" not in numbers and "A" not in numbers:
            add(WARN, f"no pad numbered 1 (found: {', '.join(sorted(set(numbers))[:8])})")

    for model in fp.children("model"):
        atoms = model.atoms()
        if not atoms:
            continue
        model_path = atoms[0]
        if not model_path.startswith("$") and (
            model_path.startswith("/") or (len(model_path) > 1 and model_path[1] == ":")
        ):
            add(ERROR, f"absolute 3D-model path '{model_path}' — use ${{KIPRJMOD}} "
                       "or a configured path variable")
    if not fp.children("model"):
        add(WARN, "no 3D model — STEP export and mechanical fit checks will be incomplete")

    descr = fp.child("descr")
    if not descr or not descr.atoms() or not descr.atoms()[0].strip():
        add(WARN, "no description")

    return findings


def collect(paths) -> list:
    files = []
    for raw in paths:
        p = Path(raw)
        if p.is_file() and p.suffix == ".kicad_mod":
            files.append(p)
        elif p.is_dir():
            files.extend(sorted(p.rglob("*.kicad_mod")))
        else:
            print(f"warning: skipping {p} (not a footprint or directory)", file=sys.stderr)
    return files


def main(argv) -> int:
    args = [a for a in argv if not a.startswith("-")]
    strict = "--strict" in argv
    if "-h" in argv or "--help" in argv or not args:
        print(__doc__.strip())
        return 0 if args or "-h" in argv or "--help" in argv else 2

    files = collect(args)
    if not files:
        print("no .kicad_mod files found", file=sys.stderr)
        return 2

    errors = warnings = 0
    for path in files:
        findings = check_footprint(path)
        if not findings:
            continue
        rel = os.path.relpath(path)
        if rel.startswith(".."):
            rel = str(path)
        print(rel)
        for sev, msg in findings:
            print(f"  {sev:<5} {msg}")
            if sev == ERROR:
                errors += 1
            else:
                warnings += 1
        print()

    print(f"{len(files)} footprint(s): {errors} error(s), {warnings} warning(s)")
    return 1 if errors or (strict and warnings) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
