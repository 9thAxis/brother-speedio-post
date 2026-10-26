# Post processor audit — `modified/44242_2026-09-07.cps`

Audited 2026-10-21 against upstream rev 44242, then verified by three independent
verifiers (primary sources, reproduction by posting, adversarial code trace) with
disagreements settled against the source. Verdicts below are the reconciled result.

## Status

**Batch 1 (2026-10-21), no motion change — done.** §1.1 (angle compensation refused),
§1.2 (O8810 without F, per the owner: the Renishaw settings on the control are the reference;
also covers G5), §1.3, §1.4, §3.1–§3.3, §4.1, §4.2 (warning), §4.3, §4.4 (warning), §5.1
(corrected fix, plus errors for G02/G03/G02.4 written under TCP and for any drilling cycle under TCP),
§5.2 (error on rewind), §6.2–§6.5, G8a. Documented in `CUSTOMIZATIONS.md` #9–#15.
Verification: 42 fixtures post, 3 stop with their expected errors
(`tests/expected-failures.txt`), 0 failures; the only output change is F removed from 12
`G65 P8810` lines in four probing fixtures (no coordinate changes); with
`useTiltedWorkplane` off the six 3+2 fixtures change only M298 L2 → M285 (M284 since 1f53614) and M299 → M289;
explicit-level check 12/12; each new error and word checked with an instrumented post.

**After batch 1 (2026-10-21) — done.** G8c corner cycles (72185ac); §1.5 unit mismatch guard
with a `controlUnit` property (94b4185); `maximumTappingSpeed` property instead of a fixed 6000
(8eff760); §7.2 closed by the owner's TCP use with unchanged .mch kinematics (cbe3000).
Machine validation plan: `MACHINE_VALIDATION.md`.

§6.6 Mode B levels remapped to the D00 table (CUSTOMIZATIONS #16); #11's Mode A rationale
corrected (Mode AIII is supported on the D00; removed to keep M298 as the one non-TCP system).

**Commit review (2026-10-21).** Three independent reviewers (primary sources, behaviour diff,
adversarial), each finding re-checked against the source and then by an independent verifier.
Fixed: probe guard also refuses work planes rotated only about Z (G68.2 K≠0, or a C index with
G68.2 off; rotated instances of rotary-patterned probe ops are now refused); corner cycles reset
the modal X/Y after the macro so the next move is always written in full (the first fix dropped
the move back to the start point, unverifiable for Blum's P8700); tool groups 901–930 allowed;
the regression log is cleared per post and the levels check also covers smoothingMode B and fails
on the wrong code family. Docs: the TCP drilling refusal (any cycle, so no drilling in 3+2 with
G68.2 off), Mode B level meanings hold under TCP only, Renishaw feed explanation (`#505` bit 2048),
validation plan C3 (needs G43 active; 2 mm overshoot test), A2, the external offset under TCP, a
B2 check for M284 roughing. Partly refuted: "the angle refusal does not fire when the angle probe is the last operation" —
for Renishaw it fires at that operation's end; with probingType Blum an outer-corner angle probe
as the last operation posts without compensation (pre-existing, nothing harmful written).

**Open:** §1.1 machine check (`#5325`/`#5326` on G59, validation A1), §6.7–§6.8. §6.1 is the owner's (014501). **Deferred** (optimisation or new motion, not
pursued): §2 approach redesign, §4.2 expansion, G1b, G6, G7.

## Safety rule for every recommendation

Avoiding a crash overrides everything else. The post deliberately sequences motion (Z
retract, then A/C indexing, then tool change; no simultaneous table and spindle moves), and
that stays. Each fix is classed:

- **No motion change** — validation, errors, warnings, M/F/P words, formatting. Safe to make
  after regression posting.
- **Motion change** — alters generated moves. Only with a manual citation for every new block,
  a line-by-line review of posted output, machine simulation, and a dry run (single block, low
  rapid override, no part) before use. Default: don't.
- **Dropped** — rejected as unsafe or refuted.

Sources: post `modified/44242_2026-09-07.cps` (ours) and `upstream/44242_2026-09-07.cps`;
manuals in `../manuals/text/` — programming manual (PM), data bank manuals (DB), Renishaw
Inspection Plus (IP), operation manual I (OM), installation manual 2 (IM2); control
parameters `../backups/s500xd2-2026-10-12/` (`UPRDM1`, `MPRD1`; record `Uxxx000,v1,v2,…` =
parameters xxx001, xxx002, …, alignment checked against DB defaults); Renishaw macros
`../backups/FULL-BACKUP-2025-12-20/OMP400/`; machine file `brother u500Xd2.mch`.

---

## 1. Fix first — wrong part or crash risk

### 1.1 Angle probing may write the skew angle into the A-axis offset — Upstream, escalated (was E1)
- **Code:** `setProbeAngleMethod` 4040–4050 sets `rotaryTableAxis = i` (index among U/V/W,
  C → 1); `setProbeAngle` 4013 writes `#[5200 + wo·20 + 1 + 4]` = `#5225` for G54
  (`angled probing.nc` line 46: `#5225 = [#5225 + #144]`), then `forceWorkPlane()` re-indexes.
- **Why #5225 is probably A:** the formula assumes Fanuc numbering (4th axis = first rotary).
  On the D00 the work offset has six slots, `#5221–#5226` (PM 14945), read as X, Y, Z and
  additional axes in order (PM ~15513); the rotaries are the 5th and 6th axes (IM2 ~1626,
  OM ~8152); parameter 020001 (5th-axis stroke control) = 1 with stroke −30/+120 = A, and
  020002 (6th axis, C) = 0 (`UPRDM1` `U020000`); `POSSD1` G054 has six columns. So
  `#5224` = 4th, `#5225` = A, `#5226` = C.
- **Effect if so:** the measured XY skew is added to A's work offset; the next index tilts the
  table by that angle — wrong part, possible collision.
- **Machine result (MACHINE_VALIDATION A1, 2026-10-25):** with G59 A = 11.111 and C = 22.222,
  `#5324` = 11.111, `#5325` = 0, `#5326` = 22.222. The slots are X, Y, Z, A, **B**, C, so
  `#5225` is the B-axis offset (no B axis on this machine), not A. Upstream's write is lost
  rather than tilting the table, but angle compensation still never reaches C. The correct C
  slot is `#5226` (`#5206 + 20·wo`).
- **Also:** even with the right slot, G54 X/Y are not re-solved about the C centreline
  (correct only if the WCS origin is on it); sign unverified (.mch C turns about −Z; O8843
  line 185 `#144 = #16 − #1`).
- **Machine check (no motion):** on an unused offset (e.g. G59, `#5321–#5326`), enter two
  different, recognisable values for A and C on the Workpiece coord zero screen, then read
  `#5325` and `#5326` on the macro variable screen and see which one matches A. Clear the
  values afterwards. The G54 slots follow the same order.
- **Fix (no motion change):** until confirmed, `error()` for AXIS_ROT angle compensation
  instead of writing it. After confirmation, write `#5226` and warn about the XY origin.

### 1.2 Protected probe moves without F run at the macro's fast feed — Upstream, new
- **Code:** `protectedProbeMove` 783–797 and `onCycleEnd` emit `G65 P8810` through modal
  `getFeed`, so repeated calls drop F.
- **Macro:** O8810 F is the local `#9`, not kept between calls; when vacant it uses
  `#119` (XY, = `#509`, default 5000 mm/min) or `#113` (Z, 0.6 × `#509` = 3000 mm/min)
  (O8810, O8724 lines 61–68).
- **Repro:** `angled probing.nc` lines 40–41: `G65 P8810 Z0.1969 F39.4` (1000 mm/min) then
  `G65 P8810 Z-0.1` — the descent to measuring depth runs at 3000 mm/min.
- **Effect:** protected (stops on contact) but 3× the CAM feed; risk of stylus overtravel.
- **Fix (done, feed only):** omit F on every P8810 so O8810 always uses the control's feeds (owner's choice: the Renishaw settings are the reference). See CUSTOMIZATIONS #14.

### 1.3 Probing under G68.2 is allowed — Upstream, default via our #4 (was A2)
- **Code:** `writeProbeCycle` 1073–1076 errors only when `!useTiltedWorkplane`; 718–719
  reject only G68 and G54.4. TWP defaults true in ours, false upstream.
- **Manual:** IP 2662–2663 "cannot be used while co-ordinate rotation is in force, i.e.
  cancel code G69". The macros read `#5041`/`#5061` (workpiece frame), and O8732's
  "ROTATED FCS TO WCS CALC" branch is bypassed (`GOTO13`).
- **Effect:** most likely an O8810 position-check alarm (E50); otherwise a wrong offset.
  Not reproduced (no tilted probe fixture).
- **Fix (no motion change):** `error()` for every probe cycle whose tool axis is not +Z,
  whatever TWP is.

### 1.4 0 % tool wear feedback writes F100 — Upstream (was A5)
- **Code:** `getProbingArguments` 1630 `toolWearErrorCorrection ? x / 100 : 100`.
- **Manual/macro:** IP 495–497 (F between 0 and 1); O8701 line 41 applies `C[#146*#9]` with
  no range check.
- **Repro:** forced 0 % on `update tool wear` → `G65 P8814 … F100 T3 V0.002`.
- **Effect:** silent 100× tool offset correction.
- **Fix (no motion change):** write `F0`.

### 1.5 A unit mismatch scales every value by 25.4 — Upstream, new (found 2026-10-21 after batch 1)
- **Code:** the post never writes G20/G21 (`gUnitModal` is unused); `onOpen` only writes the
  comment "FILE OUTPUT IN INCHES. PLEASE ENSURE THE UNIT IS SET CORRECTLY ON THE CONTROL".
- **Manual:** the D00 G-code list (PM ~1580–1680) has no G20/G21; units are a machine setting,
  and this machine is metric (011004 = 20000 mm/min; tool lengths 66–161 mm).
- **Effect:** a program posted in a unit other than the control's runs every value 25.4× off —
  on this metric machine, an inch program's `G100 … Z1.1811` (30 mm clearance) would stop
  1.2 mm above Z0.
- **Fix (done, no motion change):** a `controlUnit` property (Millimeters / Inches, default
  Millimeters for this machine; inch-spec D00 machines use Inches) and an error when the
  output unit differs from it. A first version refused all inch output, which would have
  locked out inch machines; replaced at the owner's request. Forcing `unit = MM` in `onOpen`
  converts positions correctly in a test, but values computed at load (`highFeedrate`,
  formats) and raw `getParameter` values would stay in inches, so it was rejected. The
  regression harness posts with `controlUnit` = Inches because the fixtures are inch.

## 2. Safe probing claims more than it does — Ours (#9) (was A1)

- **What:** the approach to the probe operation's clearance plane is never protected. With a
  tool change, `G100 T04 X Y G43 Z1.1811 H04` moves XY at ATC Z height, then rapids Z down to
  the clearance plane (PM ~12925–12941 steps 2, 4, 5) before `G65 P8832` arms the probe;
  same-tool sections use `G00` (`writeInitialPositioning`, 702–712). The `G65 P8810` lines
  after P8832 move nowhere. The descent from clearance to the cycle is protected.
- **Not a regression:** identical to upstream, and consistent with Renishaw's documented
  practice (IP ~720–722: move to a safe plane, then activate the probe).
- **Risk:** only a WCS or tool-length error larger than the clearance margin, or XY over a
  fixture higher than the clearance plane.
- **Constraints on any fix:** O8810 calls O8724, which alarms E70 if G49 is active or H ≤ 0,
  so G43 must be active before any P8810; a Z-only G100 would descend at the previous XY.
- **Fix (motion change — design only, not recommended without a dry run):**
  `G100 T X Y G43 H` with a high Z, P8832, then protected Z down. First, a no-motion step:
  correct the #9 description and `CUSTOMIZATIONS.md` (see 6.2).

## 3. Alarms at the machine — no motion change

### 3.1 Tapping speed above 6000 rpm not checked — Upstream (was B1)
- PM 11285 (G84), ~11380 (G77): `<<Spindle speed error>>` above Max. tapping speed; IM2 578
  and `MPRD1` 11000058 = 6000 (16K spindle).
- Repro: spindle speed forced to 7000 → `G100 … S7000 M03`, `G77 … L6000`, no warning.
- Fix: `error()` in the tapping cases when `spindleSpeed` exceeds a `maximumTappingSpeed` property (default 6000; 8000 on 27K spindles per IM2 578), which also caps the L word.

### 3.2 Manual boring writes G88, which the D00 lacks — Upstream (was B2)
- Code 1022–1028; no G88 in PM (list 1651–1672, table ~10915–10966).
- Repro: remapped stop-boring → `G98 G88 … P0. F15.7`.
- Fix: `error()` (do not expand — expansion adds motion).

### 3.3 Tool numbers outside 1–99 / 201–299 not caught — Upstream (was B4)
- `validateToolData` (check at ~2101) only warns above 28. PM ~12916 G100 T ranges.
- Repro: `tcp with tsc` → `G100 T00 … G43.4 … H00 D00`.
- Fix (done): `error()` outside 1–99, 201–299 and 901–930 (tool groups, added after the commit
  review). The `tcp with tsc` fixture (T0) is listed in `tests/expected-failures.txt`.

## 4. Lower severity

### 4.1 Dwells under 1 s raised to 1 s — Upstream (was A3)
- Code 753, 829 `clamp(1, …)`; PM 3437–3454; 011001 Program unit = 0 (Base).
- Repro: 0.25 s → `P1.`; fix → `P0.25`. Cycle time only, no crash.
- Fix (no motion change): `clamp(0.001, …, 99999.999)`.

### 4.2 G83/G73 ignore degressive pecking — Upstream (was A4)
- Code 859–882 writes a fixed `Q incrementalDepth`. `deep drilling`: CAM reduces each peck
  (reduction 0.1 mm, minimum 0.5 mm), post writes Q 1 mm. Tool life, not crash.
- The D00's W/V reducing step uses a fixed factor table (PM ~12649–12675): no exact match.
- Fix options: **warning** when `incrementalDepthReduction > 0` (no motion change,
  recommended); expanding the cycle is a **motion change**.

### 4.3 Tap L word unformatted — Upstream, on by default via our #7 (was E4)
- Code 894, 915, 936, 963. Repro: rpm 1909.8593 → `S1910`, `L3819.7186342`.
- Fix (done): `rpmFormat.format(Math.min(spindleSpeed * 2, maximumTappingSpeed property))`.

### 4.4 Fine/back boring ignore Fusion's shift orientation — Upstream (was E3)
- Code 970–990 writes no direction or V (orientation angle, PM ~11327/11809); the D00
  shifts by 012004 = 0 (+X).
- Fix (no motion change): warning when `shiftOrientation != 0`.

## 5. Non-default settings only

### 5.1 With G68.2 off, M298 precedes G43.4 — Ours (#10) (was C1)
- `setSmoothing` (called at 653) reads `tcp.isSupportedByOperation` before `defineWorkPlane`
  (660/667/1716) sets it; `isOptimizedForMachine()` is also still false there.
- Repro: `--property useTiltedWorkplane false`, all six 3+2 fixtures → `M298 L2` then
  `G100 … G43.4` (PM ~25592 NOTE 2 alarm).
- **Corrected fix (no motion change):** `currentSection.isMultiAxis() ||
  isTCPSupportedByOperation(currentSection)` in `setSmoothing`, and the same predicate for
  previous and current section in `initializeSmoothing`. Verified: default output unchanged on
  every fixture; the six TWP-off fixtures write M285 before G43.4.
- **Related, not reproduced:** in that mode G02/G03 can be written under G43.4 (PM ~26464).
  Recommendation: `error()` when `useTiltedWorkplane` is off and a non-multi-axis section
  would use TCP, rather than linearising arcs.

### 5.2 After a rewind the spindle is off on re-entry — Upstream, unreachable today (was C2)
- `writeRetract` 1841–1845 retracts with `G100 T`; nothing restarts the spindle on return
  (3751). Repro needs rewinds enabled in a .mch copy: 8 rewinds, none with M03.
- G100 is the right retract: it cancels TCP itself (PM G100 NOTE 14) and the Z offset from
  step 1 (NOTE 5). The originally proposed `allowCancelTCPBeforeRetracting` is **dropped**:
  it writes a bare G49 under TCP, which moves Z by the tool length (PM 14.2.5.1, 14.2.5.2
  NOTE 7) — tool lengths here are 66–161 mm.
- Fix: `error()` if the machine configuration enables rewinds (no motion change), until a
  reviewed restart sequence exists.

## 6. Settings and documentation

- **6.1 Washdown (#6) is a no-op with 014501 = 0** — M401 stops the shower after Chip shower
  retention time (PM ~22896). **Owner is setting 014501.** No post change.
- **6.2 `CUSTOMIZATIONS.md` #9 and the `useSafeProbing` description** say approach rapids from
  the tool change are protected — false (section 2).
- **6.3 `CUSTOMIZATIONS.md` #11 and code comment 422–424 say B+C** — the machine is A+C (OM
  ~3971; .mch). Upstream's removed `useTrunnion` was A+C; #11's stated reason was wrong.
- **6.4 `commissioningMode`** — the M0 call site (1793) is upstream (upstream 1740), but upstream
  never declared the property, so it was off; our commit 7bb7d41 declared it with default
  true. Not in `CUSTOMIZATIONS.md`; fires only after inspection ops; M0 comes before probe
  off (1811).
- **6.5 `defineMachine` 449 references `useTCP`**, deleted by #11. Unreachable (needs no .mch).
- **6.6 Mode B levels under TCP (Ours: automatic map; Upstream: values and explicit map)** —
  roughing → M285 (user-defined, PM 14.2.6.4), semi → M283 (most accuracy-heavy). Proposal:
  roughing → M284, semi → M280, semi-finishing → M281, finishing → M283. No motion change.
  **Owner decision.**
  **Checked on the owner's control (2026-10-21):** the TCP levels are User Parameter 15
  "5th-axis machining: By M code" 155n01–155n07 (DB 17425–17545). The backup (`U155000`–
  `U155700`) matches the U500Xd2 factory column exactly. M285 = 100 on all overrides, i.e. the
  same as no machining level (high speed) — a sensible roughing level, matching the intent of
  the Mode A table the `[0, 5, 3, 4, 1, 2]` offsets come from (M265 = high speed). The real
  inversion is semi-roughing → M283 (corner decel 2/2/10 %, accel 10 %), slower than finishing's
  M282. Cycle time only. Origin: Autodesk applied Mode A level offsets
  (PM 13-1 ~23760: 0 shape accuracy, 5 high speed, 3/4 surface, 1/2 shape) to M28x, whose D00
  levels mean something else. The offsets are correct for Mode AIII, which the D00 does support
  (PM 13.1; parameters 101n01–101n08 populated on the control).
  **Done (owner's decision):** remapped as proposed — CUSTOMIZATIONS #16.
- **6.7 The parameter backup folder `s500xd2-2026-10-12` is this U500XD2** (5-axis strokes,
  16K, 28 tools, T28 = `OMP400-4MM-01`). Rename.
- **6.8 O8898 loads the probe as T28**; the Fusion library should use T28.

## 7. Machine checks (no post change)

- **7.1** `#5225` vs `#5226` — see 1.1.
- **7.2 A and C directions — closed by field use.** The .mch turns A about −X and C about −Z
  (upstream's built-in trunnion used +X / +Z). The owner has cut parts under TCP on this machine
  with the Fusion post, which validates these directions, and the rotation axes
  (`axis_of_rotation`) are identical in the machine file used then (now under `backup/`) and
  the current one: A (−1, 0, 0) through (−284, 0, 50), C (0, 0, −1). Re-check only if the .mch
  kinematics change.

## 8. Improvements

| ID | Item | Class | Verdict |
|----|------|-------|---------|
| G1 | Replace TCP retract `G100 T` with G49 + G28 | Motion | **Dropped** — unsafe (bare G49 under TCP); G28 forbidden under TCP |
| G1b | Skip the first of `G100 T02 / G49 / M299 / G100 T02` at program end | Motion | Deferred |
| G2 | Index A/C during the tool change (`G100 … G53.1`) | Motion | **Dropped** — simultaneous table and spindle motion |
| G3 | Skip retract and probe off/on between same-tool probe ops | Motion | **Dropped** — unsafe after angle updates (re-index with probe down) |
| G4 | Unwind C to the nearest 360° | Motion | **Refuted** — C stroke control off (020002 = 0); control takes the shortest route (PM ~5624) |
| G5 | Safe-probing feed: omit F so O8810 uses `#509` (5000 XY, 3000 Z) | Feed only | Recommended — slower Z than today's F200 (5080 mm/min) |
| G6 | G277/G278 for full-retract peck tapping | Motion | Deferred — matches Fusion only when accumulated ≤ incremental depth |
| G7 | G85/G89 E, G81 W/V/E/L, P on G83/G86 | Motion | Deferred |
| G8a | `warningOnce` for the Blum warning (3257) | None | Recommended |
| G8b | Duplicate G69 at start | None | Leave — harmless |
| G8c | Corner cycles (`writeProbeCycle`, corner cases) format X/Y through modal outputs | Restores CAM motion | **Confirmed and fixed** — reproduced with a forced corner cycle: old post wrote `G65 P8810 Y2.5748` (X dropped, probe at the wrong X), fixed post writes `X1.9748 Y2.5748`. Upstream bug. |

## Closed during the audit (confirmed by all three verifiers)

- O8832 / O8833 exist (probe on/off: M5, M19, M406, `G04P2.` / M407, `G04P1.`); O8819 (PCD
  bore/boss) exists.
- O8810 uses `G31P2`, so the #9 "G31 P2" wording is right.
- Inch programs: O8724 converts on `#4006` = 20; only O8898/O8899 (not called) are metric-only.
- M28x before G43.4 is valid (PM 14.2.6.5 NOTE 1, program example 2).
- **Refuted finding B3:** offsets above G54.1 P48 are fine on this control. O8732 N31 switches
  to the `#14000` block for S149+ (G54.1 P49–P300, PM 14950–14957). The IP manual's
  S101–S148 is the generic limit.

---

## Verification log

| ID (original) | Manuals verifier | Repro verifier | Code verifier | Reconciled |
|---|---|---|---|---|
| A1 | PARTLY (G100 mechanics) | PARTLY (overstated) | PARTLY (not a regression; fix flawed) | Moved to §2, rewritten; G100 steps checked PM 12921–12942 |
| A2 | CONFIRMED (effect: alarm likelier) | CONFIRMED (code) | CONFIRMED (fix too narrow) | §1.3 |
| A3 | CONFIRMED, severity lower | CONFIRMED | CONFIRMED, Low | §4.1 |
| A4 | CONFIRMED | CONFIRMED | CONFIRMED, Medium | §4.2, fix → warning |
| A5 | CONFIRMED (line 1630) | CONFIRMED | CONFIRMED | §1.4 |
| B1 | CONFIRMED | CONFIRMED | CONFIRMED | §3.1 |
| B2 | CONFIRMED | CONFIRMED | CONFIRMED | §3.2 |
| B3 | REFUTED (O8732) | REFUTED | REFUTED | Closed; O8732 N31 checked |
| B4 | CONFIRMED (warns, not silent) | CONFIRMED | CONFIRMED | §3.3 |
| C1 | CONFIRMED | CONFIRMED, fix wrong | PARTLY, fix wrong | §5.1, corrected fix verified by two verifiers |
| C2 | CONFIRMED | CONFIRMED, fix unsafe | CONFIRMED, fix unsafe | §5.2; G100 NOTE 5/14 and PM 14.2.5.1 checked |
| D1 | CONFIRMED | CONFIRMED | CONFIRMED | §6.1, owner setting 014501 |
| D2 | CONFIRMED | CONFIRMED (attribution) | CONFIRMED (attribution) | §6.6 |
| E1 | CONFIRMED (check item) | CONFIRMED (premise) | ESCALATED (#5225 may be A) | §1.1; PM 14945, U020000, POSSD1 checked |
| E2 | PARTLY | CONFIRMED (+X/+Z vs −X/−Z) | CONFIRMED | §7.2 |
| E3 | CONFIRMED | CONFIRMED | CONFIRMED | §4.4 |
| E4 | CONFIRMED | CONFIRMED by repro | CONFIRMED | §4.3 |
| F1–F6 | CONFIRMED (F3 attribution) | CONFIRMED (F5 PARTLY) | CONFIRMED (F3 PARTLY) | §6 |
| G1–G8 | see §8 | see §8 | see §8 | §8 |
| — | — | — | NEW: protected feed | §1.2; O8810/O8724 and output lines 40–41 checked |
