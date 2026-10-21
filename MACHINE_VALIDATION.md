# Machine validation plan — U500XD2-5AX

Validates the audit changes (`AUDIT.md`, commits ceba133, 72185ac, bcf0475) and settles the
open motion questions on the machine. Work through the parts in order: **A** moves nothing,
**B** moves in the air with no part, **C** touches a part with the probe. Do not start a part
until everything before it has passed.

## Rules for every test

- **Stop on any surprise.** If a move goes anywhere other than where the simulation or this plan
  says, press Feed hold, then Reset. Do not resume. Write down the block (N number), the screen
  and what moved, and stop the plan there.
- **Post in millimeters from your own Fusion setups**, with the post's *Control unit* at
  Millimeters. The test fixtures in `tests/fixtures/` are inch files for the regression harness:
  never run them on the machine. The post stops if the program unit differs from *Control unit*.
- **Post with the committed post** `modified/44242_2026-09-07.cps` (commit bcf0475 or later) and
  the current machine file (`brother u500Xd2.mch`).
- **Simulate first.** Run every program through Fusion machine simulation with the machine
  model before it goes to the control, and keep the simulation open next to the machine.
- **First run of every program:** single block on, rapid override at the lowest setting, feed
  override low, hand on Feed hold. Raise the overrides only on a second run that has already
  gone through clean.
- **Air runs (part B):** no part or fixture on the table, or clamp only things well below the
  path. Shift everything up with the external work offset: Z of `#5203` (Workpiece coord zero
  screen, "EXT") = **+100.000**, and set it back to its previous value after part B. Avoid the
  A −30° stroke end in test programs (use A +30° to +90°).

Record each result in the table at the end.

---

## A. At the control, no motion

### A1. Which variable is the C work offset — gates angle compensation (AUDIT §1.1)
Angle compensation is disabled in the post until this is known.
1. Pick an offset you do not use, e.g. **G59**. Write down its current values.
2. On the Workpiece coord zero screen, enter **A = 11.111** and **C = 22.222** for G59.
3. On the macro variable screen, read **#5324, #5325, #5326** (G59 = #5321–#5326).
4. Record which variable shows 11.111 (A) and which shows 22.222 (C).
5. Put G59 back to the values from step 1.

**Expected (from the manual):** #5325 = 11.111 (A), #5326 = 22.222 (C). If so, upstream's
`#5225` (G54) was writing the skew into **A**, and the post fix will use `#5226`.

### A2. Renishaw protected-move feed and mode
The post now leaves F off `G65 P8810`, so O8810 uses the control's settings.
1. Read **#509** (fast feed, mm/min; O8724 resets it to 5000 if it is ≤ 1000 or > 10000).
2. Read **#505** and note whether bit 64 (production mode) or bit 512 (prove-out mode) is set.
   Production mode runs protected moves at 16000 XY / 10000 Z; prove-out halves the feeds.

**Expected:** #509 = 5000 (XY 5000, Z 3000 mm/min), neither mode bit set. If production mode
is on, decide whether that speed is acceptable for approach moves before part C.

### A3. Parameters the post relies on
Confirm on the parameter screens (values read from the 2026-10-12 backup):

| Parameter | Expected | Why |
|---|---|---|
| 011001 Program unit | 0 (Base) | Dwell P in seconds, `Q1`/`I1` read as mm |
| 11000058 Max. tapping speed (machine) | 6000 | Post refuses taps above it |
| 012004 G76, G87 shift direction | 0 (+X) | Boring shift direction; check against how boring bars are mounted |
| 014501 Chip shower retention time | your new value | Washdown at operation end |
| 020001 / 020002 5th / 6th-axis stroke control | 1 / 0 | A is the 5th axis, C the 6th |

### A4. Probe tool number
O8898 loads the probe as **T28**. Check that the probe in the Fusion tool library is T28 with
length offset H28, and that tool data 28 holds the calibrated probe length.

### A5. Unit guard (desk check)
Post any setup with inch output while *Control unit* = Millimeters. **Expected:** posting stops
with "The NC program is in inches but the control unit is set to millimeters…".

---

## B. Air runs (no part, external Z +100)

### B1. A and C directions — gates any TCP work (AUDIT §7.2)
The machine file turns A about −X and C about −Z; G68.2 work does not depend on this sign, but
the pre-index before G68.2 and all TCP motion do.
1. In Fusion make a setup with one 3+2 operation at **A +30°, C +90°** (a short facing pass is
   enough) and one with **A +60°, C 0°**. Post, and simulate with the machine model.
2. Run single block. At the `G00 A… C…` block, compare the table with the simulation: the
   direction the table tilts toward, and the direction C turns.
3. **Pass:** both match the simulation. **Fail:** any mismatch — stop, do not run TCP programs,
   and report which axis is reversed (the `.mch` needs fixing, not the post).
4. Only if 2 passed: post a short **5-axis simultaneous** operation (TCP, G43.4) and run it in the
   air at low feed override. **Pass:** the tool tip follows the path the simulation shows relative
   to the table, with no drift as A/C move.

### B2. Smoothing and TCP transitions
Program, same tool: 3-axis op → 5-axis op → 3-axis op; then the same with a tool change between
them. Post with High accuracy level = Automatic.
- **Pass:** no `<<TCP control command not possible>>`, `<<TCP under control>>` or
  `<<Unavailable modal for machining mode specification>>` alarms. In the 3-axis ops the screen
  shows the M298 machining mode (L2/L3/L4/L6); in the 5-axis op it shows the Mode B level (M28x).

### B3. Explicit high accuracy level
Post a 3-axis op with High accuracy level = **Finishing high**. **Pass:** the program has
`M298 L6` and the screen shows "Finishing S".

### B4. Tapping and dwell words
One tap at S ≤ 6000 with "Double the tap withdraw speed" on, and one counter-bore with a
0.25 s dwell, both in the air.
- **Pass:** the tap block has an integer `L` (e.g. `L2000`), no `<<Spindle speed error>>`, and the
  retract is faster than the feed in. The counter-bore block has `P0.25` and the dwell is short.

### B5. Washdown
Any two-op program (non-probe tools). **Pass:** at the end of the first op the chip shower runs for
the retention time set in 014501.

Set the external Z offset back after part B.

---

## C. Probing on a part (probe calibrated, real WCS)

### C1. Approach to the clearance plane (AUDIT §2 — observe, unchanged by the audit)
The G100 tool call moves XY at tool-change height, then rapids Z down to the operation's
clearance height **before the probe is switched on** (`G65 P8832`). That move is not protected.
1. Before running: in CAM, check the probe operation's clearance height is above every clamp and
   the part, and that the WCS is right (touch off or indicate).
2. Run single block, lowest rapid override. **Pass:** the probe stops at clearance height above
   the part with the expected gap, then P8832 switches it on (spindle orients, 2 s dwell).

### C2. Protected moves at the control's feed
Run a WCS probe op (e.g. a rectangle boss or bore) on a known part.
- **Pass:** the `G65 P8810` moves (no F in the program) run at about #509 in XY and 0.6 × #509 in Z;
  the descent to measuring depth is protected; the cycle finishes without E-alarms; the updated
  work offset matches an indicator check.

### C3. Protection actually trips (confirms G31 P2 is the probe input)
In MDI with the probe on (`G65 P8832`), above a flat face of the part:
`G65 P8810 Z<5 mm below the face> F500`.
- **Pass:** the probe triggers on the face and the machine stops with **PATH OBSTRUCTED**.
  **Fail:** it does not stop — stop using safe probing and report (the skip input setting is
  wrong). Then `G65 P8833`.

### C4. Tool wear feedback at 0 % (if you use tool wear update)
Probe op with "update tool wear" and error correction **0 %**. **Pass:** the program has `F0`, the
cycle reports the size, and the tool wear offset does not change.

### C5. Corner probing (if you use it)
Inner or outer corner op, followed by another probe point or op with the same tool.
- **Pass:** after the corner cycle the probe moves to the XY the simulation shows (the old post
  could drop the X or Y of that move).

### C6. Angle compensation — after A1 and a post update
Not runnable yet: the post refuses it. Once A1 is recorded and the post writes the confirmed
C variable, test on a part with a known small skew (e.g. 1–2°):
- **Pass:** only the C work offset changes, by the skew with the sign that brings the part square,
  and a re-probe reads near zero skew. Note that XY of the WCS is not re-solved about the C
  centreline: re-probe XY after the angle update.

---

## Results

| Test | Result (pass / fail / value) | Date | Notes |
|---|---|---|---|
| A1 A variable / C variable | | | |
| A2 #509 / #505 | | | |
| A3 parameters | | | |
| A4 probe T28 / H28 | | | |
| A5 unit guard | | | |
| B1 A direction / C direction / TCP | | | |
| B2 transitions | | | |
| B3 explicit level | | | |
| B4 tap L / dwell | | | |
| B5 washdown | | | |
| C1 approach | | | |
| C2 protected feeds | | | |
| C3 PATH OBSTRUCTED | | | |
| C4 0 % wear | | | |
| C5 corner | | | |
| C6 angle compensation | | | |
