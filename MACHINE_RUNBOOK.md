# Machine runbook: PostEval air runs and real cut (U500Xd2, CNC-D00)

Step by step at the control for the PostEval programs. The test intent and pass criteria are in
`MACHINE_VALIDATION.md`. Key and screen names follow the manuals: `[KEY]` is a physical key or
switch, `<Key>` is an on-screen key. "Data bank" means tapping `<DATABANK>` (the fifth key in
the control key area), then the menu item. You confirm a typed value with `[ENT]`.

Sources: Operation Manual I (OM1), Operation Manual II (OM2), Data Bank & Alarm Manual I (DB1),
Inspection Plus manual (IP), and the probe macros in the Dec 2025 backup. Machine values are
from the 2026-10-12 parameter backup.

## Before you start

- **Programs** are on the FTP share at `u500xd2/MICROFACTORY`:

  | File | Setup | What it tests |
  |---|---|---|
  | `PEVAL-B2A` | Air | B2: 3-axis → 5-axis → 3-axis, same tool |
  | `PEVAL-B2B` | Air | B2: tool change + 5-axis rough. B5: washdown |
  | `PEVAL-B3` | Air | B3: explicit Finishing high |
  | `PEVAL-B4` | Air | B4: M3 form tap (T15) + counter-bore dwell (T2) |
  | `PEVAL-R1` | Real cut, G54 | Face, 1×10 shoulder, rough + finish Ø16 bore |
  | `PEVAL-R2` | Real cut | C4 bore inspection; C2/C5 corner probe → G56 |

- **Material:** a 6061 blank, 95.5 × 64 × 22.5 mm, with flat and square sides.
- **Tools:**

  | T | Tool | Note |
  |---|---|---|
  | 1 | YG1 3/8" 3FL | |
  | 2 | LK 1/4" 3FL | Bore finish uses `G41 D02` |
  | 15 | M3 form tap | Air run only |
  | 28 | OMP400, 4 mm stylus, calibrated | Tool length 129.2191 in the backup |

- **Fixturing:** Lang 45840 plate with the KSC3 125-160 grip jaws.
  - **External offset:** do not use it. On this control it is never applied (010520 = 0 and the
    EXWORK signal is not assigned). The air runs are lifted by adding 100 mm to G54 Z instead.
  - **Order matters:** you set G54 on the blank, then take the blank **out** for the air runs.
  - **The +100 raise is mandatory.** This blank's top is only about 19.5 mm above the jaw tops,
    so with a missed raise the B2 outline contour (Z−21) would reach into the jaws. Check that
    G54 Z reads about 251 before every air run.

### Controls you will use

| What | How |
|---|---|
| Single block | `[SINGL]`, LED lit = on. Each `[START]` runs one block. **Not during cutting in high-accuracy mode** (`M298 L…` or `M28x`): the control raises **SM7571** for a feed move in single block. Use it for the approach rapids, then turn it off before the first feed move |
| Optional stop (M01) | `[OP.STP]`, LED lit = on. Leave it on: the programs stop at M01 before each tool change |
| Pause / resume | `[FEED HOLD]` / `[START]`. Feed hold does not stop the spindle and waits for a tool change or tap to finish |
| Stop everything | `[RST]` stops at once, except during a tool change or tap. It cancels G43 and G41 and returns to the program start |
| Emergency stop | `[EMERGENCY]`. To recover, turn it right to release, then press `[RST]` |
| Rapid override | Position 1 = 0 mm/min (rapids stop). **Position 2 = 500 mm/min (use for first runs)**. Position 3 = 5000. Position 4 = 10000. 100 % = full rapid |
| Feed override | `[FEEDRATE OVERRIDE]`, 0–200 % |
| Where you are | `<POS>` → `<Current position>`: machine, absolute (workpiece) and relative coordinates. Override settings show here too |
| Active modal codes | `<POS>` → `<Modal 1>`: all G and M codes, T/H/D |
| High-accuracy mode | `<POS>` → `<Modal 2>`, item "High accuracy". It shows "rough", "finishing S", or "5 axes machining (M28x)" under TCP |
| Doors | `[DOOR INTERLOCK MODE]` must be on automatic for memory operation |

**Stop rule:** if anything moves somewhere you did not expect, press `[FEED HOLD]`, then `[RST]`.
Write down the N number on screen and what moved, and stop there.

---

## 1. Copy the programs into memory

Your control runs programs from memory (010501 = 0), so copy them from the FTP share first.

1. Turn data protection off: `<Subtools>` → `<Data protection>`. The mark must be **off**. If
   your machine has a `[DATA PROTECTION]` key switch instead, turn that off.
2. Press `[EDIT]` → `<External I/O>` → `<Program>`.
3. Check the **Connected** field reads **FTP(S) server**. If it does not, press
   `<Change connection device>` (second function-key column) and choose **FTP(S) server**.
4. In the FTP pane, tap the folder **MICROFACTORY** and press `[ENT]` to open it. If the files
   are not listed, press `<Latest directory>`.
5. In the NC pane, open the **MICROFACTORY** folder the same way. Programs go into whichever NC
   folder is open.
6. Back in the FTP pane, tap `PEVAL-B2A` and press `<Input>`. Repeat for `PEVAL-B2B`, `PEVAL-B3`,
   `PEVAL-B4`, `PEVAL-R1` and `PEVAL-R2`. If the control asks to overwrite, answer `<No>` and
   tell me: nothing with these names should exist yet.

## 2. Checks at the control, no motion (A1–A4)

### A1. Which variable holds the C work offset

1. Data bank → `<Workpiece coordinate zero>`.
2. Move the cursor to **G59 A**, type `11.111` and press `[ENT]`. Move to **G59 C**, type
   `22.222` and press `[ENT]`. G59 is currently all zeros.
3. Press `<Completion mode>` → `<Save and end>`.
4. Press `[MDI]` → `<Delete all>` → `<Yes>`. Type the three blocks below, each ending with
   `[EOB/ENT]`, then press `[START]`:
   ```
   #195=#5324
   #196=#5325
   #197=#5326
   ```
   System variables can't be shown on a screen, so this copies them into #195–#197. No macro on
   the machine uses #191–#199.
5. Data bank → `<Macro variables>` → `<#100 - 199>`, then read #195, #196 and #197.
   **Result (2026-10-25):** #195 = 11.111 (A), #196 = 0 (B, unused), #197 = 22.222 (C). Write
   down what you see if you repeat it.
6. Data bank → `<Workpiece coordinate zero>`: set **G59 A** and **G59 C** back to `0`, each with
   `[ENT]`, then `<Completion mode>` → `<Save and end>`.

### A2. Renishaw feeds

Data bank → `<Macro variables>` → `<#500 - 599>`:

| Variable | Expected | Meaning |
|---|---|---|
| #505 | **1024** | Bit 2048 off |
| #509 | **5000** | Protected moves run 5000 mm/min in XY and 3000 in Z |

### A3. Parameters

Data bank → `<User parameter>`. For each row, type the number and press
`<Parameter number Search>`:

| Parameter | Expected |
|---|---|
| 011001 | 0 |
| 11000058 | 6000. If the search doesn't reach it, it's a machine parameter: skip it |
| 012004 | 0 |
| 014501 | Your chip shower time |
| 020001 / 020002 | 1 / 0 |
| 020502 | 500 (rapid override position 2) |

### A4. Tool data

Data bank → `<Tool data>` → `<Tool list>`. For each tool, type the number and press `<Search>`:

| Tool | Tool length offset | Cutter comp. | Cutter wear offset |
|---|---|---|---|
| 28 | **129.2191** (calibrated 4 mm probe) | any | any |
| 1 | Measured | any | any |
| 2 | Measured | **0** | **0** |
| 15 | Measured | any | any |

The R1 bore finish uses `G41 D02` on a path that already includes the tool radius, so tool 2's
<Cutter comp.> and <Cutter wear offset> must both be **0**. Note any values you change, and put
them back afterwards. Save with `<Completion mode>` → `<Save and end>`.

## 3. Clamp the blank and set G54 (X0 Y0 = blank centre, Z0 = blank top)

1. **Clamp the blank:** 64 mm side across the jaws, 95.5 mm side along X, resting on the jaw
   step. That's about 3 mm of grip, with the top about 19.5 mm above the jaw tops.
2. **Load the probe:** `[MDI]` → `<Delete all>` → type `G100 T28` `[EOB/ENT]` → `[START]`.
3. **Rough X/Y:** press `[MANU]`. Jog with `[+X]` `[-X]` `[+Y]` `[-Y]`; `[JOG]`, with `[+]`/`[-]`
   to change speed, or the handle. Bring the stylus ball **over the blank centre by eye**, to
   within ±2 mm.
4. Data bank → `<Workpiece coordinate zero>`:
   1. Cursor on **G54 X** → `<Automatic setting>`. Set <Absolute coord. pos. after setting> to
      `0`, with <Apply compensation> off. Press `<Set>`.
   2. Cursor on **G54 Y** → the same.
5. **Rough Z:**
   1. Jog Z down until the ball is about **5 mm above the blank top** (use a 5 mm block or drill
      shank as a gauge).
   2. Read **Machine Z** on `<POS>`.
   3. Work out G54 Z = Machine Z − 129.219 − 5. Type it into **G54 Z** and press `[ENT]`.
   4. **Check it's about 151.2.** That's the value P8811 measured on this setup (Lang plate,
      KSC3, 22.5 mm blank, 2026-10-25). The earlier stack-up estimate of 129.4 was 22 mm low.
      If it's far off, stop and recheck before going on.
   5. Press `<Completion mode>` → `<Save and end>`.
6. **Refine with the probe.** Press `[MDI]` → `<Delete all>`, then type these blocks, each ending
   with `[EOB/ENT]`:
   ```
   G90 G54 G00 X0 Y0
   G43 Z50. H28
   G65 P8832
   G65 P8810 Z10.
   G65 P8811 Z0. S1
   G65 P8810 Z10.
   G65 P8812 X95.5 Z-5. S1
   G65 P8812 Y64. Z-5. S1
   G65 P8810 Z50.
   G65 P8833
   ```
   Turn `[SINGL]` on, set rapid override to position 2, and press `[START]` once per block.
   - `G43 Z50.` rises to 50 mm above the top.
   - P8832 turns the probe on: the spindle orients, then a 2 s dwell.
   - P8811 sets Z0 on the top. **P8812 X/Y** measure the blank's width and set X0 Y0 at its
     centre. They swing out about 55 mm in X and 39 mm in Y at Z10, drop to Z−5 (the ball bottom
     about 12.5 mm above the jaw tops), and touch inward.
   - Each probe cycle sets the centre relative to where it **started**, so the probe must be at
     X0 Y0 when P8812 is called. This sequence does that.
7. Data bank → `<Workpiece coordinate zero>`: write down **G54 X, Y and Z** (Z should still be
   about 151.2).
   - If you get alarm **592** (probe already triggered) or **593** (probe did not trigger), the
     rough setting was too far off: press `[RST]`, redo step 3 or 5, and run the blocks again.
   - If you get alarm **586** (PATH OBSTRUCTED), the protected move hit something: press `[RST]`
     and check the stylus.

## 4. Air runs (B2–B5): no part in the vise

1. **Take the blank out of the vise**, leaving the jaws as they are. G54 X/Y stay set.
2. **Raise G54 by 100:**
   1. Data bank → `<Workpiece coordinate zero>`, cursor on **G54 Z**.
   2. Type `100` and press `<Add>`. G54 Z goes from about 151.2 to about 251.2.
   3. `<Completion mode>` → `<Save and end>`.
   4. Check `<POS>` → `<Workpiece coordinate zero>`: the G54 Z row must show the new value.
3. **For every program:**
   1. `[MEM]` → `<Program list>`.
   2. Tap **MICROFACTORY**, press `[ENT]`, select the program, press `[ENT]`.
   3. Check the program name on screen.
   4. Turn `[SINGL]` and `[OP.STP]` on. Set rapid override to position 2 and feed override to
      about 30–50 %.
   5. Close the doors and press `[START]`, then `[START]` again for each block, up to the last
      rapid before the first feed move (in B2A, B2B and B3: **N85** `G00 Z5`).
   6. **Turn `[SINGL]` off** and press `[START]`: the rest runs in cycle. At rapid position 2
      (500 mm/min) the op-to-op transitions are slow enough to watch. Your stop is
      `[FEED HOLD]`. A feed hold in the middle of a cut may itself raise SM7571; that just stops
      the machine, and `[RST]` clears it.

   Coolant comes on with M08 even in the air. That's expected.

| Program | Watch at block | Pass |
|---|---|---|
| **PEVAL-B2A** | N55 `M298 L2` (Face) | `<Modal 2>` High accuracy = **rough** |
| | N250–N270 | `M299`, `M283`, then `G00 A9.421 C81.109`. **A and C move only after Z has retracted** (N225–N230 end the Face op) |
| | N280 `G100 … G43.4` (swarf) | High accuracy = **5 axes machining (M283)**. No TCP alarm |
| | N1830–N1850 | `G100 T01` retract, then `M289`, `M298 L6`, `G00 A0. C0.`. High accuracy = **finishing S**. No alarms |
| **PEVAL-B2B** | N255 `M284` (5-axis rough) | High accuracy = **5 axes machining (M284)** |
| | N1870 `M01` → N1880 `G100 T02` | Stops at M01; T1 → T2 tool change; contour in `M298 L6` |
| | N225–N230 `M400`/`M401` | **B5:** the chip shower runs for the 014501 time at the end of the first op |
| **PEVAL-B3** | N55 `M298 L6` on the Face | High accuracy = **finishing S** (Automatic would have shown "rough") |
| **PEVAL-B4** | N85 `G77 … I0.5 L1000` (T15 at S500) | No spindle-speed alarm. **Retract visibly faster than the feed in** |
| | N175 `G82 … P0.25` (T2) | A short dwell at the bottom of each hole |

4. **Take the 100 back off:** Data bank → `<Workpiece coordinate zero>`, cursor on **G54 Z**,
   type `-100`, press `<Add>` (back to about 151.2), then `<Save and end>`.

## 5. Real cut (C1–C5)

1. **Re-clamp the blank** as in section 3, step 1, then **redo section 3, steps 2 and 6** (probe
   load and the MDI probe blocks). The rough G54 is still close, and the blank will have moved a
   little. The KSC3 centres the blank in Y, but not in X. Put it back within about ±2 mm in X,
   for example against a stop or a mark. If it's further off, redo section 3, steps 3–5 first:
   P8812 X drops the probe only 5 mm outside the expected faces.
2. Write down **G54 X, Y and Z**. These are the reference for the end of R2.
3. **Run PEVAL-R1:**
   1. `[MEM]` → select `PEVAL-R1`.
   2. `[SINGL]` on through the first approach (N70 `G100 T01 … Z15`, then down to the top).
   3. Once you're happy with it, turn `[SINGL]` off. Feed override at 50 % for the first part,
      then 100 %.

   Sequence: face 1 mm with T1, then the 1×10 shoulder with T1 (four 3 mm passes), stop at M01,
   then the T2 rough bore (helix, then pocket), then the T2 finish bore (`G41 D02`).
4. **Gauge the bore** (nominal Ø16) and write down the reading. Calipers read about 0.03 low here; the R2 probe
   reading is the better number. On 2026-10-25 the bore came out at 15.939 by probe. T2's
   <Cutter wear offset> is a radius, and a negative value opens a G41 bore: −0.030 gave 16.0245
   on a recut. Leave it at 0 for C4.
5. **C3, PATH OBSTRUCTED.** Press `[MDI]` → `<Delete all>`, then type:
   ```
   G100 T28
   G90 G54 G00 X-20. Y0
   G43 Z60. H28
   G65 P8832
   G65 P8810 Z9.
   ```
   Run block by block (`[SINGL]` on). The probe is now 10 mm above the faced top (Z−1) at
   X−20 Y0. Then `<Delete all>`, type `G65 P8810 Z-3. F200`, set feed override low, keep a hand on
   `[FEED HOLD]`, and press `[START]`.
   - **Pass:** the probe touches and the control stops with alarm **586 PATH OBSTRUCTED**. It
     might show as #3000 = 86; tell me exactly what appears.
   - **Fail:** it keeps going. Press `[FEED HOLD]` and stop the plan.
   - **Recover:** press `[RST]`. Then `<Delete all>` → type `G91 G01 Z5. F500` `[EOB/ENT]`
     `G90` `[EOB/ENT]` `G65 P8833` `[EOB/ENT]` → `[START]`.
6. **Run PEVAL-R2** with `[SINGL]` on:
   - **C1, at N65** `G100 T28 X28 Y18 G43 Z55 H28`: the probe stops 56 mm above the faced top,
     then N70 `P8832` turns it on.
   - **C2:** the `P8810` moves run at about 5000 mm/min in XY and 3000 in Z. Check the speed on
     `<POS>`.
   - **C4, at N95** `P8814 D16 Q10 F0 T2 V0`: when it stops after this block, go to Data bank →
     `<Macro variables>` → `<#100 - 199>` and read:

     | Variable | Meaning |
     |---|---|
     | #138 | Measured diameter. Compare with your gauge |
     | #143 | Size error |
     | #145 | Position error |

     Do this before pressing `[START]`, because the next cycle clears them. Read after the end of
     R2 instead, #138 and #143 are blank and #145 is the corner's position error, not the bore's. Then press `[MEM]`
     and `[START]` to continue.
   - **C5, at N140** `P8816 X-46.75 Y-31 Q10 S3.`: after the corner cycle, N155 moves to
     **X−56.75 Y−41**, with both X and Y.
7. **Results:**
   1. Data bank → `<Workpiece coordinate zero>`. **G54** must be unchanged from step 2.
      **G56 − G54** in X and Y should be close to zero, a few hundredths at most. That's the C2
      corner check.
   2. Data bank → `<Tool data>` → `<Tool list>` → tool **2**: <Cutter wear offset> must still be
      **0**. That's C4, with 0 % feedback.
   3. Put back anything you changed in A4.

Record results in the table at the end of `MACHINE_VALIDATION.md`: A1–A4, B2–B5, C1–C5.

## Alarms you might see

Renishaw alarms show as **500 + n**:

| Alarm | Meaning | What to do |
|---|---|---|
| 586 | PATH OBSTRUCTED | Protected move hit something. Expected in C3 |
| 589 | NO TOOL LENGTH ACTIVE | G43 H28 not active |
| 592 | PROBE ALREADY TRIGGERED | Probe touching before the move, or the rough setting is off |
| 593 | PROBE DID NOT TRIGGER | Surface not where expected |
| M0 stop, OUT OF TOLERANCE / OUT OF POSITION | Size or position outside a tolerance | PostEval programs set none, so you shouldn't see this |
| Emergency button activated (EMS*) | E-stop | Release it, then `[RST]` |
