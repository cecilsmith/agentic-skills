# Review checklist

Work in order. Report findings grouped by severity, each naming the specific
refdes, net, or coordinate. "Add decoupling" is noise; "U3 pin 14 (VDDIO) has no
capacitor within 4 mm; nearest is C21 at 11 mm on the far side of the via field"
is a finding.

Severity: **blocker** (board will not work or cannot be built) / **defect**
(will need a rework or a respin to fix properly) / **improvement**.

## 0. Machine checks first

```bash
scripts/kicad-check.sh .
```

ERC and DRC clean — or every remaining violation individually justified with an
inline exclusion and a comment. A board with 40 "acceptable" DRC warnings has no
DRC coverage at all, because nobody reads the 41st.

## 1. Schematic — electrical

- **Power tree.** Trace every rail from source to load. Voltage correct at each
  pin, sequencing satisfied where a device demands it (many SoCs and FPGAs latch
  up or fail to boot on the wrong order), and every regulator's input/output
  capacitor within its datasheet's stability range — not just "10 µF".
- **Current budget.** Sum the loads per rail against the regulator rating with
  margin. Check the regulator's thermal derating at the actual input voltage:
  a 3.3 V LDO from 12 V dissipates 2.6 W per amp, which no SOT-223 survives.
- **Decoupling.** Every supply pin of every IC. Value and package per the
  datasheet, placed on the same side, nearest pin first.
- **Pin-strap and boot configuration.** Resistors present, pulled to the right
  rail, values inside the device's threshold spec. Confirm against the boot table
  in the datasheet, not against a reference design.
- **Reset and enable.** Defined at power-up — no floating resets, no enable pins
  left to leakage.
- **Unused pins.** Tied per the datasheet: unused op-amp inputs biased, unused
  logic inputs pulled, unused ADC inputs grounded. Never left floating.
- **Crystals.** Load capacitors computed from the crystal's C_L and the estimated
  stray, not copied. Drive level within spec.
- **Protection.** ESD on every externally exposed connector; reverse-polarity and
  overvoltage on any input a user can reach; current limiting on outputs.
- **Level shifting.** Every interface between voltage domains. Check direction,
  speed, and whether the device is 5 V tolerant — most modern parts are not.
- **I2C addresses.** No collisions on a bus; pull-ups present exactly once per
  bus and sized for the bus capacitance and speed.
- **Test and debug access.** SWD/JTAG brought out, UART accessible, test points on
  every rail and on the signals you will need at 2 a.m.

## 2. Schematic — hygiene

- Annotation complete and unique; no `R?`.
- Every net that matters is named. `Net-(U3-Pad14)` in a netlist is a net nobody
  can discuss.
- Hierarchical sheet pins match their labels; no accidental global-label collisions
  joining two unrelated nets across sheets.
- Every symbol has a `Footprint` field, and DNP parts are marked `dnp` rather than
  deleted, so the BOM and assembly drawing agree.
- No power flags missing (the usual source of spurious ERC "not driven" errors) —
  and no power flags added merely to silence a real one.

## 3. Layout — physical

- **Stackup** matches the fab's standard offering. A non-standard stackup is a
  quote delay and a cost multiplier.
- **Board outline** closed on `Edge.Cuts`, with no zero-length segments or
  duplicate overlapping lines — the most common reason a fab rejects a job.
- **Mounting holes** positioned to the mechanical drawing, with correct
  plating/keep-out, and enough clearance for the screw head and standoff.
- **Connector positions and orientations** verified against the enclosure and the
  mating cable. Check the STEP export in the mechanical assembly, not just the
  2D view.
- **Component clearance** for tall parts, and courtyard violations resolved rather
  than excluded.

## 4. Layout — electrical

- **Return paths.** Every high-speed signal has a continuous reference plane
  beneath it. A split plane under a fast trace is a blocker, not a nitpick.
- **Trace width vs current.** Sized with derating for the copper weight and
  acceptable rise (IPC-2152, not the older 2221 curves, if you have the data).
  Check the whole path, including the via count.
- **Impedance-controlled nets** identified, netclass configured, geometry matching
  the fab's stackup calculator — USB, Ethernet, HDMI, DDR, RF.
- **Differential pairs** routed together, length-matched within tolerance, with
  symmetrical vias and no stubs.
- **Crystal and switching-regulator loops** kept small; the switch-node copper
  minimised; input capacitor's loop area to the IC as tight as it can be.
- **Sensitive analog** separated from digital and from the switcher; ADC
  references and dividers kept away from noisy copper.
- **Thermals.** Copper area and vias under power devices; thermal reliefs on
  through-hole pads that need hand-soldering, and *not* on pads that need to sink
  heat.
- **Zone stitching.** Ground vias along the edges and around high-speed returns;
  no large isolated copper islands, which act as antennas.

## 5. Manufacturing readiness

- Silkscreen legible: no text under parts, none overlapping pads, minimum height
  and stroke per the fab's capability, polarity and pin-1 markers visible after
  assembly.
- Reference designators on `F.Fab` for the assembly drawing.
- Fiducials if the board is machine-assembled — three, asymmetric, unobstructed.
- Panelisation and edge clearance agreed with the fab if applicable.
- BOM: every line has an MPN and a distributor part, DNP rows marked, alternates
  named for anything with a long lead time.
- Position file origin matches the gerber origin (see `cli.md`).
- The final zone refill is committed and the fab outputs regenerated from that
  commit — not from a working tree with uncommitted changes.

## 6. Before saying it is done

State explicitly which checks you ran, which you could not run and why, and what
you did not look at. A review that implies more coverage than it had is worse than
a short one.
