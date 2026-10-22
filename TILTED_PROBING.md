# Tilted-plane probing — design (not implemented)

Goal: in-process inspection on 3+2 faces. Measure sizes and positions, update tool offsets,
check feature positions with Fusion's inspection probing, on any face the table can tilt to.
Setting the WCS stays at A0 C0 and is out of scope.

Status: **design only.** The post still refuses every probe operation that is not in the WCS
orientation (CUSTOMIZATIONS #15). Nothing here gets coded until test D1 in
`MACHINE_VALIDATION.md` has passed on the machine. Manual references: PM = D00 Programming
Manual, page numbers as printed (chapter - page).

## Why the probe cycles can't just run under G68.2

- Renishaw: "The Renishaw probe cycles cannot be used while co-ordinate rotation is in force,
  i.e. cancel code G69" (Inspection Plus manual, `brother_renishaw_manual_inspection_plus.txt:2662`).
  On this control `O8732`'s "ROTATED FCS TO WCS CALC" branch is skipped (`GOTO13`) and its
  `TWPX`/`TWPY`/`TWPZ` names were never filled in.
- With G68.2 off, the post puts a tilted operation under TCP (G43.4). With user parameter
  150001 = 0, TCP programs in the table frame, so the cycles would move along the part's
  untilted axes, not across the face.

## Approach: copy the tilted plane into a spare work offset, then cancel G68.2

G69 does not move any axis (PM 3-57), so the table stays tilted. With no rotation active, the
cycles run as designed, in a work offset whose origin is the tilted plane's origin and whose
axes are the machine axes.

Sequence for one tilted inspection operation. Pn = the spare offset (a property, default
**P300**). (x1, y1) = the operation's first point and `clear` its clearance height, in Fusion's
feature-frame values. #30–#33 are main-program local variables (locals stop at #33, PM 6-6). The post uses no
locals, and each G65 macro gets its own local level. Common variables (#100–#199, #500–#999)
are avoided: any program or macro can write them, and Renishaw uses #100–#149 and #500 up.

| # | Block(s) | Motion |
|---|---|---|
| 1 | work offset (`G54`), `G00 A… C…`, `G68.2 …`, `G53.1` | as today: table moves with Z at home. Work offset forced, see Motion safety |
| 2 | `G100 T28 X<x1> Y<y1> G43 Z<clear> H28` | as today: unprotected approach to the first point at clearance height |
| 3 | `M159`, `#30=#5021 #31=#5022 #32=#5023 #33=#5083` | none: records the machine position and the applied tool length offset. M159 stops look-ahead so the reads are the completed position (PM 6-15) |
| 4 | `G28 G91 Z0`, `G90`, `G49` | Z straight up to home, same XY. A bare G49 right after G28 makes no motion and raises no alarm whatever 011501/011502 are set to (PM 4-37 NOTE 2). This is the post's existing operation end |
| 5 | `G69` | none (PM 3-57). Needs G49 first, which step 4 gives |
| 6 | `G10 L20 Pn X[#30-#5201-x1] Y[#31-#5202-y1] Z[#32-#5203-#33-clear]` | none. G10 L20 is refused under G68.2 (PM 3-41 NOTE 1), hence after G69. #5201–#5203 = external offset (PM 6-8; O8732 reads it the same way) |
| 7 | `G54.1 Pn`, `G00 X<x1> Y<y1>`, `M159`, check #5021/#5022 against #30/#31, then (no motion) the workpiece Z #5043 against #5023−#32+#33+clear | XY at Z home to the same XY (zero length if correct); both checks before Z moves. The Z check proves how the control applies the external offset |
| 8 | `G43 Z[clear+25.] H28`, `M159`, check #5023 against #32+25 | Z down to 25 mm above the point already visited. Always with a Z word: with 011501 = 0 (Type 1, the owner's setting), `G43 H` alone moves Z by the offset |
| 9 | `G00 Z<clear>`, `M159`, check #5023 against #32 | the last 25 mm, only after the checks above passed |
| 10 | `G65 P8832`, the operation's cycles unchanged, `G65 P8833` | as today, in Pn |
| 11 | `G28 G91 Z0`, `G90`, `G49`, the section's work offset (`G54`), `G10 L20 Pn X0 Y0 Z0` | Z up; normal offset back and Pn zeroed before any other block |

A failed check (tolerance 0.002 mm) jumps to a recovery block: `G28 G91 Z0`, `G90`, `G49`,
`G69`, the work offset, Pn zeroed, `M159`, then `#3000=1(TILT*COPY*MISMATCH)`. The `M159` is
needed because a macro statement runs when it is read, ahead of the motion blocks before it
(PM 6-4). Without it the alarm could stop the program before the cleanup ran. The operator
sees alarm 9001 (PM 6-9: number 9000+n; message ≤ 20 characters; the manual only guarantees
alphanumerics, and `*` as a space is what the installed Renishaw macros use).

Why the copy is exact: machine position = work offset + tool length (Z) + programmed position
(PM 4-36 example: Z100 + H120 + offset 50 = 270). The manual gives no formula for the external
offset. Step 6 subtracts the same external offset that the control adds back in step 7, so how
G68.2 treats it doesn't matter. The checks prove it on every run.

The checks only compare against the same recorded numbers. They catch a formula term that's
wrong or missing (tool wear, a shift the formula doesn't know). They do not catch a wrong
recording. D1 covers that by comparing the screen at stop 1 and stop 2.

### Alignment: the post refuses unaligned operations

Pn's axes are the machine axes. Fusion's X/Y for the face match them only if nothing is left
of the work plane's rotation once the table has indexed (the remaining orientation is the
identity). A tilt is a rotation about machine X (A), so the probe operation's X axis must run
along the face's tilt axis, the edge that stays level with the table. Example: `A30 C0` with
`G68.2 … I0 J30 K0` (fixture `a-30`) is aligned whatever the axis sign conventions, because a
rotation about X leaves X in place. A plane rotated only about Z (`G68.2 … K<angle>`, C 0) is
not, and stays refused. Fixture `all`'s `A30 C-90` face (`I-90 J30 K90`) is not aligned either
(a ±90° rotation about Z is left). A misaligned single-surface X probe would push the stylus at an angle to the wall, so
the post must refuse it, not warn. If x1/y1 are not zero, a misaligned operation would also
fail the step 7 check.

## What the feature gives and refuses

| Measurement | Tilted face |
|---|---|
| Bore, boss, web, pocket: size, centre position, radius wear update | yes |
| Single surface X, Y: position, radius wear update | yes |
| Single surface Z: position, length update | yes, but Renishaw writes length corrections to the **length geometry** (`O8732` line 7, `#11000+T`; PM 6-8: #11001– = tool length offset, #10001– = length wear) |
| Print results / tolerance checks against the Fusion nominals | yes |
| WCS update (any probe operation that writes a work offset) | **refused**: it would write tilted-frame values into G54 or Pn |
| Angle measurement / rotary angle compensation | refused (already refused everywhere until A1) |
| Operation not aligned (see above), G68.2 off, under TCP | refused |
| Any operation in the program using the same G54.1 Pn | refused |

It does not see rotary-centre calibration errors: the probe uses the same kinematics that cut the
feature ("This function … does not offer compensation for indexing accuracy", PM 3-59). Use the
kinematic test block for that.

## Motion safety

- The table moves only where it moves today: in step 1, with Z at home. Between G68.2 and the
  end of the operation, A and C do not move (also required by PM 3-55).
- Added motion: Z straight up (step 4), XY at Z home to the same XY (step 7), Z back down in
  two stages to a point the probe was at moments earlier (steps 8–9). The probe only goes below
  25 mm above that point after XY and Z have both been checked. The probe stays off until all
  checks pass.
- G28 G91 Z0 under G68.2: the manual doesn't describe it, but after G53.1 the feature Z is the
  tool axis, and the post already runs `G28 G91 Z0` / `G90` / `G49` under G68.2 on this machine
  at every 3+2 operation end.
- No bare G49 except right after G28. No G43 without a Z word.
- **Pn must not survive the operation.** G68.2 builds its frame in the active work offset. If
  Pn were still active at the next 3+2 operation's G68.2, that frame would be shifted and
  tilted: a crash. Step 11 restores the work offset and zeroes Pn. A regression check must fail
  any output where `G68.2` follows `G54.1 Pn` without a work offset in between.
- **Pn must be a free offset.** The owner's Blum tool-setter macros (`BLUM2/O8501`, `O8505`)
  select **P48** as an all-zero offset ("PROXY MACHINE COORDS") and then search down at the
  setter. A tilted-frame copy left in P48 would send the next tool touch-off to the wrong place.
  So the default is P300 (zero and unused in the 2026-10-12 offset backup), and Pn is zeroed
  after use and in the recovery block.
- **The post doesn't always write the work offset before G68.2.** It writes the work offset
  only when it changes or at a tool change. In fixture `all`, faces 2–5 have `G00 A… C…` /
  `G68.2` with no `G54` before them. A program restart is covered on the owner's machine:
  010507 = 0 (Type 1) reads the program up to the restart block and restores operation "as if
  it had been operating" (Operation Manual I 7-14), which should include the work offset. It is
  not covered by Type 2's sequence search (reading skipped), or by resuming after a block stop
  during which the offset was changed in MDI. A tilted probe operation that alarms after step 7
  leaves Pn active, and that is exactly the second case. So when this feature is built, write
  the section's work offset before every A/C index and G68.2. As a general post change, this
  was considered on 2026-10-22 and deferred: it isn't needed on the owner's machine.
- Abort: M02/M30 cancel G68.2 (PM 3-57). Whether Reset cancels G68.2 and G43, and whether the
  work offset stays modal, is not in the manual. D1 records it, and D1 has a recovery program.

## Post changes (after D1 passes)

- Properties: `tiltedProbing` (default off until D2/D3 pass), `tiltedProbingOffset` (G54.1 P
  number, default 300).
- `writeProbeCycle` guard: with `tiltedProbing` on, allow a probe operation that is not in the WCS
  orientation when every condition in the table above holds; otherwise keep today's error.
- Section start/end of a tilted inspection: steps 3–9 after the approach, step 11 at the end,
  recovery block at the program end. Cycle coordinates are unchanged (Fusion's feature-frame
  values are Pn values once aligned).
- Force the work offset before every A/C index and G68.2 (see Motion safety).
- Regression: a tilted inspection fixture (to export from Fusion, none exists), the
  `G68.2`-after-Pn check, the forced work offset check, and refusal fixtures (WCS update,
  misaligned, Pn collision).

## Alternative to ask about

Brother/Renishaw may have an Inspection Plus build for the D00 with the tilted-plane branch of
`O8732` working. If they do, this whole sequence becomes unnecessary.
