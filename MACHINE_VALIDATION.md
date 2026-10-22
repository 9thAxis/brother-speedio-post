# Machine validation plan — U500XD2-5AX

Validates the audit changes (`AUDIT.md`; every commit listed in its status section) and settles the
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
- **Post with the committed post** `modified/44242_2026-09-07.cps` (latest commit, uploaded to
  Fusion — see A0) and the current machine file (`brother u500Xd2.mch`).
- **Simulate first.** Run every program through Fusion machine simulation with the machine
  model before it goes to the control, and keep the simulation open next to the machine.
- **First run of every program:** single block on, rapid override at the lowest setting, feed
  override low, hand on Feed hold. Raise the overrides only on a second run that has already
  gone through clean.
- **Air runs (part B):** no part or fixture on the table, or clamp only things well below the
  path. Shift everything up with the external work offset: Z of `#5203` (Workpiece coord zero
  screen, "EXT") = **+100.000**, and set it back to its previous value after part B. Avoid the
  A −30° stroke end in 3+2 test programs (use A +30° to +90°). Under TCP (5-axis ops) this control
  works in the table coordinate system (user parameter 150001 = 0): work offsets, the external
  one included, are fixed to the table and tilt with it, so the +100 is along the table's normal,
  not machine Z. At large A the path shifts sideways and will not line up with the simulation;
  keep 5-axis (TCP) air runs within |A| ≤ 30°.

Record each result in the table at the end.

---

## A0. Fusion uses the updated post (before anything else)

The machine file points Fusion at `cloud://44242_2026-09-07.cps`, the copy in the Fusion cloud
post library. The audit fixes kept the same file name, so Fusion keeps posting with the old copy
until it is replaced.
1. Upload `modified/44242_2026-09-07.cps` from this repo (latest commit) to the Fusion cloud post
   library over the existing `44242_2026-09-07.cps`.
2. Open the post dialog for an NC program on this machine. **Pass:** the properties include
   **Control unit** and **Maximum tapping speed**.
3. Post any probing operation. **Pass:** the `G65 P8810` lines have **no F word**.
If either check fails, Fusion is still using the old post: stop and fix that first.

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

### A2. Renishaw protected-move feed
The post now leaves F off `G65 P8810`, so O8810 uses the feeds O8724 derives from `#509`.
1. Read **#505**. Bit 2048 ("optimised" mode) must be **off**: with it on, O8724 decodes `#509`
   differently and the feeds below do not apply — stop and report.
2. Read **#509**: the protected XY feed in mm/min; Z moves run at 0.6 × #509. O8724 resets it to
   5000 if it is ≤ 1000 or > 10000.

**Expected (Dec 2025 macro backup):** #505 = 1024, #509 = 5000 → XY 5000, Z 3000 mm/min.
Production and prove-out mode (bits 64 / 512) don't apply: every `G65 P8832` the post writes
clears them.

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

### B1. A and C directions — closed, no test needed (AUDIT §7.2)
TCP parts have already been cut on this machine with the Fusion post, and the machine file's
rotation axes are unchanged since then (A about −X, C about −Z). Re-test only if the `.mch`
kinematics change: run a 3+2 op at A +30°/C +90° in the air, single block, and compare the
`G00 A… C…` move with Fusion's machine simulation.

### B2. Smoothing and TCP transitions
Program, same tool: 3-axis op → 5-axis op → 3-axis op; then the same with a tool change between
them. Post with High accuracy level = Automatic.
- **Pass:** no `<<TCP control command not possible>>`, `<<TCP under control>>` or
  `<<Unavailable modal for machining mode specification>>` alarms. In the 3-axis ops the screen
  shows the M298 machining mode (L2/L3/L4/L6); in the 5-axis op it shows the Mode B level (M28x).
- Include a **5-axis roughing op** (≥ 0.5 mm stock to leave). It now gets **M284** (high speed +
  smooth), which follows the programmed path less tightly than the old M285 (no level). **Pass:**
  M284 in the program, smooth motion, no alarm.

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
O8810 alarms (E70) unless a tool length offset is active, so start with the probe loaded and
G43 on: either stop a C2 program in single block right after its `G65 P8832`, or in MDI run
`G100 T28 G43 Z<a height clear of everything> H28` and then `G65 P8832`.
1. With protected moves, put the stylus 10 mm above a flat face of the part:
   `G65 P8810 X… Y…`, then `G65 P8810 Z<face + 10>`.
2. Feed override low, hand on Feed hold: `G65 P8810 Z<face − 2> F200` (2 mm below the face, at
   200 mm/min).
- **Pass:** the probe touches the face and the machine stops with **PATH OBSTRUCTED**.
- **Fail:** it keeps going — Feed hold. The overshoot is at most 2 mm, within the stylus
  overtravel (check the OMP400 stylus spec before the test). Stop using safe probing and report
  (the skip input is not the probe).
3. Reset the alarm and back off with a plain move, not a protected one (the stylus may still be
   deflected and would trip again): `G91 G01 Z5. F500`, then `G90`. Then `G65 P8833`.

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

## D. Tilted-plane probing (future feature — `TILTED_PROBING.md`)

Not part of validating the current post. D1 proves the frame copy before any post code is
written; D2 and D3 come after the post change.

### D1. Frame copy round trip, in the air (hand-written program)
G68.2 only runs in memory operation, not MDI, and MDI intervention is refused while it is active
(PM 3-56). So load this as a program in memory (not extended memory, tape or FTP: PM 6-25
NOTE 2), and do not use MDI at the stops. The air-run rules apply: no part, external Z
+100. The program refuses to start without that offset. The G68.2 and A/C lines are the post's
own output for an A+30° face (regression fixture `a-30`). The copy goes into **P300**, which
is zero and unused. Don't use P48: the Blum tool-setter macros use P48 as an all-zero offset.

```
(D1 TILTED FRAME COPY - AIR TEST)
(NO PART. EXT Z +100. SINGLE BLOCK. RAPID OVERRIDE LOWEST.)
IF[ABS[#5203-100.]GT0.001]GOTO98
#24=0. (TEST POINT X, FEATURE FRAME)
#25=0. (TEST POINT Y, FEATURE FRAME)
#26=50. (TEST HEIGHT ABOVE THE FACE)
G00 G90 G40 G80
G28 G91 Z0
G90
G94 G49
M299
G69
G54
G53 G00 X0 Y0
G00 A0. C0.
G00 A30. C0.
G68.2 X0 Y0 Z0 I0. J30. K0.
G53.1
G17 G90 G94
G100 T28 X#24 Y#25 G43 Z#26 H28
M159
#30=#5021
#31=#5022
#32=#5023
#33=#5083
IF[ABS[#33-#11028-#10028]GT0.0005]GOTO90
(STOP 1 - WRITE DOWN MACHINE X Y Z FROM THE SCREEN)
M00
G28 G91 Z0
G90
G49
G69
G10 L20 P300 X[#30-#5201-#24] Y[#31-#5202-#25] Z[#32-#5203-#33-#26]
G54.1 P300
G00 X#24 Y#25
M159
IF[ABS[#5021-#30]GT0.002]GOTO90
IF[ABS[#5022-#31]GT0.002]GOTO90
IF[ABS[#5043-#5023+#32-#33-#26]GT0.002]GOTO90
G43 Z[#26+25.] H28
M159
IF[ABS[#5023-#32-25.]GT0.002]GOTO90
G00 Z#26
M159
IF[ABS[#5023-#32]GT0.002]GOTO90
(STOP 2 - MACHINE X Y Z MUST MATCH STOP 1)
M00
G28 G91 Z0
G90
G49
G54
G10 L20 P300 X0 Y0 Z0
G53 G00 X0 Y0
G00 A0. C0.
GOTO99
N90
G28 G91 Z0
G90
G49
G69
G54
G10 L20 P300 X0 Y0 Z0
M159
#3000=1(TILT*COPY*MISMATCH)
N98
#3000=2(SET*EXT*Z*100)
N99
M30
```

Before running: check that P300 is zero, and that T28/H28 hold the probe. Single block,
rapid override at its lowest setting, hand on Feed hold.
- The table moves only at `G00 A…` blocks, with Z at home. Between `G68.2` and the final
  `G00 A0. C0.` the table must not move.
- After `G54.1 P300`, `G00 X#24 Y#25` runs with Z at home. It should be a zero-length move,
  because the probe is already at that XY. The XY check runs right after it, then a Z check with no motion:
  the control's own workpiece Z under P300 and the external offset must match the copy.
- `G43 Z[#26+25.] H28` must be a Z-only move down, stopping 25 mm above the stop 1 point. Then
  `G00 Z#26` covers the last 25 mm.
- **Pass:** no alarm, and stop 2 shows the same machine X/Y/Z as stop 1 (within 0.002).
- **Fail:** alarm 9001 means a check failed. The program has already retracted Z, cancelled
  everything and zeroed P300 (the `M159` before the alarm makes the cleanup finish first). The table is still at A30: after Reset, return it in MDI with
  `G53 G00 X0 Y0` then `G00 A0. C0.`. Before Reset, read #30–#33, #5201–#5203, #11028 and #10028 on the
  macro variable screen and record them. Alarm 9002 means the external Z offset isn't +100. A Z
  mismatch that is the same on every run points to an offset the formula doesn't know about,
  such as a warm-up shift.
- **Any other alarm** (not 9001/9002) can leave G68.2, G43 or G54.1 P300 active. Recover as in
  D1d, zero P300 (offset screen, or `G10 L20 P300 X0 Y0 Z0` from memory) and select G54 before
  running any other program.

**D1b, non-zero terms.** D1 with zeros everywhere can't catch a sign error in the X/Y terms, or
#5083 leaving out wear. Run it again with all of these:
- `#24=40.` and `#25=-30.`;
- external X and Y offsets of +5.000 each (Z stays +100);
- T28 length wear temporarily set to +0.500. Positive wear lifts the probe, so any failure
  errs upward.
Then put the wear and the external X/Y back. Same pass criteria.

**D1c, a C face.** D1 with `G00 A30. C-90.` and `G68.2 X0 Y0 Z0 I-90. J30. K90.` (fixture `all`),
keeping `#24=0.` and `#25=0.`. Non-zero test points are only valid on an aligned face, and this
one is not aligned: a ±90° rotation about Z is left after indexing (see `TILTED_PROBING.md`). Same pass criteria.

**D1d, Reset behaviour.** At stop 1 of one run (probe in the air at A30), press Reset instead of
Cycle start. Record whether the modal screen still shows G68.2, G43/H28 and which work offset is
active. Then recover:
1. Jog Z up in handle mode.
2. If MDI is accepted, run `G28 G91 Z0`, `G90`, `G49`, `G69`, `G54`, `G53 G00 X0 Y0`,
   `G00 A0. C0.`.
3. If MDI is refused (G68.2 still active), run those blocks as a small program from memory.
4. Check that P300 is still zero.

Afterwards: set the external offset back to its previous value (X, Y and Z), and check that
P300 is zero and T28's wear is back.

### D2. Tilted inspection in the air (post output) — after the post change
### D3. Bore and single surface on a tilted face of a test part — after D2
Machine a bore and a wall on a 30° face in 3+2, then inspect them with tool wear update at 0 %.
**Pass:** the reported diameter matches a bore gauge, the centre and wall positions are within a
few hundredths of nominal, and no tool offset changes.

---

## Results

| Test | Result (pass / fail / value) | Date | Notes |
|---|---|---|---|
| A0 Fusion uses updated post | | | |
| A1 A variable / C variable | | | |
| A2 #509 / #505 | | | |
| A3 parameters | | | |
| A4 probe T28 / H28 | | | |
| A5 unit guard | | | |
| B1 A/C directions | closed — TCP used before, .mch axes unchanged | 2026-10-21 | |
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
| D1 tilted frame copy | | | |
| D1b non-zero terms / D1c C face | | | |
| D1d Reset: G68.2 / G43 / offset after Reset | | | |
| D2 tilted inspection, air | | | |
| D3 tilted inspection, part | | | |
