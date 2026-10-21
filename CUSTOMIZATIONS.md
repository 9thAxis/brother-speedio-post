# Customizations for Brother Speedio U500XD2-5AX

Machine: **U500XD2-5AX** (CNC-D00v control, 16K RPM, CTS, 28-tool, Renishaw probe)

Last verified against upstream revision: **44242** (2026-09-07)

These changes should be re-applied each time `update.sh` pulls a new upstream version.
Update this revision number after verifying customizations against a new version.
See [UPSTREAM_CHANGELOG.md](UPSTREAM_CHANGELOG.md) for what changed in each upstream
bump and how it affected the merge.

---

## 1. Smoothing mode → M298

- **Where:** `smoothingMode` property definition (`grep 'smoothingMode'`)
- **From:** `value: "A"`
- **To:** `value: "M298"`
- **Why:** The CNC-D00v controller uses the M298 Ln smoothing system, not the legacy M260/M269 codes.

## 2. Enable high accuracy (automatic)

- **Where:** `useSmoothing` property definition (`grep 'useSmoothing'`)
- **From:** `value: "-1"` (Off)
- **To:** `value: "9999"` (Automatic)
- **Why:** High accuracy mode should always be active for milling on the D00 control.

## 3. Finishing smoothing level → L6 + Mode B fallback for TCP

- **Where:** `smoothingMode` switch inside `onOpen()` (`grep 'settings.smoothing.finishing'`)
- **Add:** a `case "M298":` block with:
  ```javascript
  settings.smoothing.finishing = 6; // M298 L6 = Finishing S
  settings.smoothing.modeBRoughing = 4; // M284
  settings.smoothing.modeBSemi = 0; // M280
  settings.smoothing.modeBSemifinishing = 1; // M281
  settings.smoothing.modeBFinishing = 3; // M283
  ```
- **Why:** The framework default for finishing is L5. M298 L6 ("Finishing S") is the optimal setting for 3D surface finishing on the D00 control. The Mode B levels are fallback mappings used by `setSmoothing()` during multi-axis TCP operations (see #10); their values follow the D00 Mode B table (see #16).

## 4. Enable G68.2 (tilted workplane)

- **Where:** `useTiltedWorkplane` property definition (`grep 'useTiltedWorkplane'`)
- **From:** `value: false`
- **To:** `value: true`
- **Why:** Required for proper 3+2 positional machining. Without this, angled WCS setups won't generate G68.2 output.

## 5. Safe start block — cancel residual smoothing and rotation

- **Where:** `onOpen()` function, after the `writeBlock(gFeedModeModal.format(94) ...` line (`grep 'gFeedModeModal.format(94)'`)
- **Add these lines after the safe start block:**
  ```javascript
  writeBlock(mFormat.format(299)); // cancel M298 machining mode (required before TCP)
  writeBlock(gFormat.format(69));  // cancel tilted workplane
  ```
- **Why:** Cancels residual M298 machining mode and G68.2 rotation that may persist from previously aborted programs. Uses M299 (not M298 L0) because M299 fully exits M298 mode, which is required before G43.4/G43.5 TCP can activate. M298 L0 only sets the level to zero but leaves M298 mode selected, which blocks TCP.

## 6. Washdown coolant → end of operation

- **Where:** `washdownCoolant` property definition (`grep 'washdownCoolant'`)
- **From:** `value: "off"`
- **To:** `value: "operationEnd"`
- **Why:** Activates chip washdown between operations for better chip management in the enclosed work area.

## 7. Double tap withdraw speed

- **Where:** `doubleTapWithdrawSpeed` property definition (`grep 'doubleTapWithdrawSpeed'`)
- **From:** `value: false`
- **To:** `value: true`
- **Why:** Outputs an L value in G77 tapping cycles for faster withdrawal, capped at the `maximumTappingSpeed` property (machine parameter 11000058, 6000 by default).

## 8. Stuck chips detection (optional, default OFF)

- **Where:** `useStuckChipsDetection` property definition (`grep 'useStuckChipsDetection'`)
- **Default:** `value: false`
- **To enable:** `value: true`
- **Why:** Outputs M318 at program start to enable Z-axis load monitoring during tool changes. The D00 compares each tool change load signature against a learned baseline to detect chips or debris stuck between the spindle face and tool holder. Only useful once your magazine is stable — the detection compares against previously recorded load profiles, so if you're frequently swapping tools in/out of the magazine, the baselines won't be meaningful and you'll get false alarms. Enable this for production runs where the tool lineup is settled.

## 9. Safe probing — protected rapids inside probe operations

- **Where:** `useSafeProbing` property definition (`grep 'useSafeProbing'`) and `onRapid()` function (`grep 'function onRapid'`)
- **Default:** `value: true`
- **What:** Adds a `useSafeProbing` property and modifies `onRapid()` to use G65 P8810 (protected positioning with G31 P2 skip-on-trigger) for rapid moves made while the probe tool is active. Splits combined XYZ rapids into safe Z-up → XY → Z-down ordering. No F word is written, so O8810 runs at the protected feeds set on the control (see #14). Only works with Renishaw probes — if `probingType` is set to Blum, a warning is emitted once and these moves fall back to standard G0 rapids.
- **What it does not cover:** the approach to the operation's clearance height. With a tool change, `G100 T.. X Y G43 Z.. H..` moves XY at ATC height and rapids Z down to the clearance plane; for the same tool, `writeInitialPositioning` writes G00. Both happen before `G65 P8832` switches the probe on, so they are not protected. This matches upstream and Renishaw's documented practice (move to a safe plane, then activate the probe). Protecting it would change the approach motion; see AUDIT.md §2.
- **Why:** The stock post only uses protected positioning during the probing cycle itself (`protectedProbeMove`). With this enabled, rapids between moves of a probe operation (after the probe is on) also go through O8810, which stops with a PATH OBSTRUCTED alarm on premature contact. Tradeoff: those moves run at the protected feed instead of true G0 rapid, so disable for production when you trust your WCS and want maximum speed.

## 10. M298 / TCP incompatibility — automatic Mode B fallback for multi-axis

- **Where:** `setSmoothing()` function, `smoothing` state object, and `initializeSmoothing()` (`grep 'usedModeB'`)
- **What:** On the D00 control, M298 and G43.4/G43.5 TCP are mutually exclusive. Issuing M298 while TCP is active triggers `<<TCP under control>>`. Issuing G43.4 while M298 is selected triggers `<<TCP control command not possible>>`. Per the programming manual (Ch. 13 / 14.2), Mode B (M280-M287) is the only smoothing mode valid during TCP.

  The fix has five parts:

  1. **`setSmoothing()` rewired for M298 mode** — When enabling smoothing for a multi-axis/TCP section, outputs M280+level (Mode B) instead of M298 Ln. For non-TCP sections, M298 Ln is used as before. Cancellation outputs M299 (fully exits M298 mode) or M289 (Mode B cancel) depending on which was active, tracked by `smoothing.usedModeB`.

  2. **Explicit cancel when switching between M298 and Mode B** — When `setSmoothing` re-enables smoothing but the mode changes (M298→Mode B or vice versa), the old mode is explicitly canceled first (M299 or M289). This is critical for same-tool transitions between 3-axis and 5-axis sections, where `setSmoothing(false)` may not have been called (it is gated behind `insertToolCall || smoothing.cancel`). Without the explicit cancel, M298 would remain active when Mode B is issued, and the subsequent G43.4 TCP activation would alarm. A warning is also emitted if the smoothing level has no explicit Mode B mapping, to catch misconfigured manual overrides.

  3. **Level mapping** — M298 and Mode B use different level numbering. An automatic M298 level (set by `initializeSmoothing`) is mapped to the equivalent Mode B level by category: roughing→M284, semi→M280, semifinishing→M281, finishing→M283. Mappings are stored in `settings.smoothing.modeB*` (see #3 and #16). An explicit `useSmoothing` level uses the explicit Mode B table instead (see #12 and #16).

  4. **`setSmoothing` moved before tool call in `onSection()`** — Smoothing codes must be output before G100 (which activates G43.4 TCP internally). Moved from after coolant to before the `insertToolCall` block. Also moved before G100 in `onClose()`.

  5. **`initializeSmoothing()` TCP transition detection** — Forces smoothing re-output when switching between TCP and non-TCP sections. Without this, the `isDifferent` guard in `setSmoothing()` would skip output when the smoothing level is the same but the required M-code changes (M298 vs M280).

  Both `setSmoothing()` and `initializeSmoothing()` decide TCP with `sectionUsesTCP(section)` = `isMultiAxis() || isTCPSupportedByOperation(section)`, evaluated from the section itself. `setSmoothing()` runs before `defineWorkPlane()` sets `tcp.isSupportedByOperation` and before the section is optimized, so reading those gave a stale answer: with `useTiltedWorkplane` off, 3+2 sections run under G43.4 and used to get `M298 L2` before `G100 … G43.4` (alarm). They now get Mode B; default output is unchanged.

- **Why:** Without this, any program mixing 3-axis and 5-axis operations with smoothing enabled would alarm on the first multi-axis section. The D00 manual explicitly states M280-M287 is valid regardless of TCP state, making it the correct choice for 5-axis work.

- **NC output example (3-axis → 5-axis transition with tool change):**
  ```
  M299         (cancel M298 — setSmoothing(false) on tool change)
  ...
  M283         (Mode B finishing — compatible with TCP)
  G100 T08 ... G43.4 ...  (tool call activates TCP)
  ...
  M289         (cancel Mode B at section end)
  M298 L6      (back to M298 for next 3-axis section)
  ```

- **NC output example (3-axis → 5-axis transition, same tool / no tool change):**
  ```
  M298 L6      (3-axis section active)
  ...
  M299         (cancel M298 — explicit cancel inside setSmoothing before switching to Mode B)
  M283         (Mode B finishing — compatible with TCP)
  ... G43.4 ...  (TCP activates)
  ...
  M289         (cancel Mode B — explicit cancel inside setSmoothing before switching to M298)
  M298 L6      (back to M298 for next 3-axis section)
  ```

## 11. Prune wrong-machine properties and legacy Mode A

- **Where:** Property definitions at the top of the file and the smoothing mode switches (`grep 'hasAAxis\|useTrunnion\|case "A"'`)
- **What:** Removed three properties / code paths that are invalid for the U500XD2-5AX + CNC-D00v combination:
  1. **`hasAAxis` property** (and the `createAxis` block that configured an A rotary from post-side) — a single A rotary, not this machine's trunnion.
  2. **`useTrunnion` property** (and the `createAxis` block that configured an A+C trunnion from post-side) — the U500XD2 is in fact an A+C trunnion (A tilts the table −30° to 120°, C rotates it; Operation manual I §8), so this was not wrong kinematics, but defining kinematics in the post conflicts with the `.mch` in the CAM setup, which is the source of truth. The `.mch` turns A about −X and C about −Z where this block used +X / +Z. The dead `useTCP` reference this left in `defineMachine()` has been removed.
  3. **`smoothingMode` value `"A"`** (and the `case "A":` branches in `onOpen` and `setSmoothing`) — High-accuracy Mode AIII (M260–M267, cancel M269). The D00 does support it (programming manual 13.1; its parameters are populated on the control), so this is not a compatibility fix: it was removed to keep one non-TCP smoothing system, M298 (Brother's machining mode system, with named levels), next to Mode B, which TCP requires. Like M298, Mode A is not allowed under TCP (14.2.6.5 NOTE 3), so keeping it would have needed its own TCP fallback and transitions in #10. Mode B and M298 remain.
- **Why:** Kinematics belong to the CAM-provided machine config (the source of truth for axis ranges, trunnion layout, etc.), so the post-side kinematics toggles only risked conflicting with it; dropping Mode A leaves fewer smoothing paths to keep correct around TCP. Simplifies `defineMachine()` to rely purely on the machine config.

## 12. Explicit high accuracy levels write the level their title names

- **Where:** `setSmoothing()` function (`grep 'isExplicitLevel'`)
- **What:** The explicit `useSmoothing` choices have ids 0 to 5, which are offsets from level 1 (Standard = 0 … Finishing high = 5). Two fixes, both gated on `isExplicitLevel` (property id 0 to 5) so the Automatic levels (2, 3, 4, 6), which overlap that range, are left as they were:
  1. **M298 branch** — writes `L` + (id + 1). Upstream writes the raw id, so every explicit choice lands one level below its title and Standard writes `M298 L0`, which turns high accuracy off (Programming Manual 13.3: L0 off, L1 Standard, L2 Rough, L3 Medium rough, L4 Medium rough S, L5 Finishing, L6 Finishing S).
  2. **TCP fallback (#10)** — maps an explicit id through the explicit Mode B table, as the plain Mode B branch does, instead of looking it up in `modeBLevelMap`, whose keys are the Automatic L numbers. Before, ids 0, 1 and 5 hit no entry (warning) and 1, 2, 3 and 5 wrote the wrong M28x code. The table itself was later changed to follow the D00 Mode B levels (#16); the column below shows the current output.

  | Property choice   | M298 (upstream → ours) | Under TCP (before #12 → now) |
  |-------------------|------------------------|------------------------------|
  | Standard          | L0 → L1                | M280 (warning) → M280        |
  | Roughing          | L1 → L2                | M281 (warning) → M284        |
  | Medium rough      | L2 → L3                | M285 → M280                  |
  | Medium rough high | L3 → L4                | M283 → M282                  |
  | Finishing         | L4 → L5                | M281 → M281                  |
  | Finishing high    | L5 → L6                | M285 (warning) → M283        |

- **Why:** An explicit level must run the mode its title names. The M298 half is an upstream bug (upstream's `case "M298"` has the same `"L" + smoothing.level`), exposed by our switch to M298 (#1). It does not affect Automatic, which is why the fixture corpus never caught it: `tests/regression.sh levels` now checks each explicit level, plain and multi-axis.

## 13. Commissioning mode — M0 after inspection operations

- **Where:** `commissioningMode` property definition (`grep 'commissioningMode'`); used in `onSectionEnd()`
- **Default:** `value: true`
- **What:** Upstream's `onSectionEnd()` already calls `getProperty("commissioningMode")` to write M0 after every inspection operation except the last, but upstream never declares the property, so the stop never fires there. We declare it (commit 7bb7d41) and default it to on.
- **Limits:** it only fires for inspection (inspect surface) operations, not for WCS or geometry probing, and the M0 comes before the probe is switched off (P8833).
- **Why:** Lets the operator check measurements before the program continues while a setup is being commissioned. Turn off for production.

## 14. Renishaw protected moves use the control's feeds

- **Where:** `protectedProbeMove()` (`grep 'useControlFeeds'`) and the safe probing branch of `onRapid()`
- **What:** `G65 P8810` is written without F. Upstream writes the probe tool's link feed (`tool_feedProbeLink`) on the first move and then drops F through the modal feed output.
- **Why:** O8810 keeps F in a local variable, so F is not carried between calls; a call without F uses the protected feeds set on the control by O8724 — `#119` = `#509` for XY and `#113` = 0.6 × `#509` for Z (5000 / 3000 mm/min unless `#509` is changed). That holds with `#505` bit 2048 (Renishaw's optimised mode) off, as on the owner's control (`#505` = 1024); with it on, O8724 decodes `#509` differently. Production and prove-out mode don't apply: each `G65 P8832` the post writes (without arguments) clears them. Upstream's mix meant the descent to measuring depth (no F) ran at 3000 mm/min right after a move at the CAM link feed. The Renishaw settings on the control are the reference. Blum (P8703) moves keep upstream's feeds.

## 15. Refuse what the control would alarm on, or would run wrongly

These are validation errors and warnings only; none changes generated motion. Each is checked by the regression run or by an instrumented post in the audit (see AUDIT.md).

| Check | Where | Reason |
|---|---|---|
| Error for any probe operation whose work plane is not the WCS orientation (tilted, or rotated about Z) | `writeProbeCycle()` | Renishaw cycles cannot run under coordinate rotation (Inspection Plus manual, "cancel code G69"). With 'Use G68.2' on, either case gets G68.2 from `setWorkPlane`; with it off, the table is indexed (e.g. C turned) instead, and probing in that frame is refused too. Upstream only refused WCS probing with a tilted tool axis, and only with `useTiltedWorkplane` off. Side effect: the rotated instances of a rotary-patterned probe operation are refused. |
| Error instead of rotary-offset angle compensation (`AXIS_ROT`) | `setProbeAngle()` | The slot assumes Fanuc numbering (`#5225` = C for G54). On the D00 the rotaries are the 5th (A) and 6th (C) axes, so `#5225` is most likely A. Disabled until confirmed on the control. |
| 0 % tool wear feedback writes `F0` | `getProbingArguments()` | Upstream wrote `F100` for 0 % (a 100× correction); the macro expects 0 to 1. |
| Error when a tap's spindle speed exceeds the new `maximumTappingSpeed` property (default 6000) | `writeDrillCycle()` | Machine parameter 11000058 (Max. tapping speed): G77/G78/G84 alarm above it. Factory values are 6000 for 10K/12K/16K spindles and 8000 for 27K spindles, hence a property rather than a constant. |
| Tap `L` word formatted through `rpmFormat` and capped at the `maximumTappingSpeed` property instead of a fixed 6000 | `writeDrillCycle()` | A fractional rpm printed as `L3819.7186342`; a 27K spindle was capped below its limit. |
| Error for manual boring | `writeDrillCycle()` | Upstream wrote G88, which the D00 does not have. |
| Error for drilling cycles and for G02/G03/G02.4 under TCP | `writeDrillCycle()`, `onCircular()` | Canned cycles and arcs are not allowed under G43.4/G43.5 (programming manual 14). The drilling check refuses every cycle under TCP, including ones the post would have expanded into G00/G01: expanding a tap would lose spindle synchronisation. In practice it refuses drilling in 3+2 operations when 'Use G68.2' is off (with it on, 3+2 has no TCP). Arcs that are linearized are unaffected. |
| Error for tool numbers outside 1–99, 201–299 and 901–930 | `validateToolData()` | G100, H and D read 1–99 and 201–299 as tools and 901–930 as tool groups; T101–199 are magazine pots, so the H/D the post writes would not match the tool loaded; T0 is invalid. |
| Error when a rewind (retract and reconfigure) occurs | `onMoveToSafeRetractPosition()` | The TCP retract is `G100 T<current>`, which stops the spindle; nothing restarted it before re-entry. |
| Error when the output unit differs from the new `controlUnit` property (Millimeters / Inches, default Millimeters for this machine) | `onOpen()` | The CNC-D00 has no G20/G21 (not in the programming manual's G-code list), so the program cannot switch units: a mismatch scales every value by 25.4 — on a metric control an inch program's 30 mm clearance becomes about 1.2 mm. The post only wrote a comment. Inch-spec D00 machines set the property to Inches. |
| Corner cycles (O8815/O8816, Blum P8700 A1) write X/Y as arguments, not through the modal outputs, and force the next X/Y | `writeProbeCycle()` | Upstream set the modal X/Y to the corner point, but the macro moves the probe (O8815/O8816 return it to the start point); a later move to that X or Y was dropped (reproduced: `G65 P8810 Y2.5748` instead of `X1.9748 Y2.5748`), and a corner X/Y equal to the modal value was left off the macro call. Resetting the modal X/Y after the macro writes the next move in full whatever the macro does (the Blum P8700 is not installed on the owner's control to check), so the output is unchanged except the dropped move. |
| Dwells below 1 s are kept (minimum 0.001 s) | `onDwell()`, `writeDrillCycle()` | Upstream raised every dwell to 1 s; P is in seconds with Program unit = Base (011001 = 0). |
| Warning when G73/G83 drop the CAM's peck reduction | `warnDegressivePecking()` | The cycles take a fixed Q. |
| Warning when fine/back boring has a shift orientation | `warnShiftOrientation()` | The D00 shifts by user parameter 012004 (+X here), not by the CAM value. |

## 16. Mode B levels follow the D00 Mode B table

- **Where:** `onOpen()` `case "B"` and `case "M298"` (`settings.smoothing.*` / `modeB*`), and the explicit table in `setSmoothing()` (`grep 'Mode B level per explicit choice'`); `useSmoothing` value comments.
- **What:** Upstream picks Mode B (M280+n) levels with the offsets of the Mode AIII table (M260+n: 0 shape accuracy, 1/2 shape accuracy high / + surface, 3/4 surface quality, 5 high speed; programming manual 13.1 ~23760), and our TCP fallback (#3) copied those values. Under TCP the D00 Mode B levels mean something else (14.2.6.4; parameters 155n01–155n07): M280 surface quality (medium), M281 + shape accuracy, M282 surface quality (high), M283 + shape accuracy, M284 high speed + smooth (factory setting on the U500Xd2), M285–M287 user defined. Now:

  | Use | Before | Now |
  |---|---|---|
  | Automatic roughing | M285 (user defined) | M284 |
  | Automatic semi-roughing | M283 (slowest level) | M280 |
  | Automatic semi-finishing | M281 | M281 |
  | Automatic finishing | M282 | M283 |
  | Explicit Standard / Roughing / Medium rough / Medium rough high / Finishing / Finishing high | M280 / M285 / M283 / M284 / M281 / M282 | M280 / M284 / M280 / M282 / M281 / M283 |

  The explicit table follows the M298 names (Standard and Medium rough balance → M280; Medium rough S, surface → M282; Finishing, accuracy → M281; Finishing S, surface and accuracy → M283).
- **Why:** Roughing ran a user-defined level whose content depends on each machine (factory: all overrides 100 %, i.e. no level), and semi-roughing ran the slowest level (corner deceleration 2/2/10 %, acceleration 10 % on the U500Xd2), slower than finishing. Smoothing levels change path-following tolerance and cycle time, not commanded positions — though M284 lets the tool path deviate more from the programmed path than M285 did. Mode B is written for TCP operations by default and for 3+2 with `useTiltedWorkplane` off.
- **Without TCP** (`smoothingMode` B on non-TCP operations) the table above does not hold: per 14.2.6.4 NOTE 1, M280–M287 then select the Chapter 13 Mode B levels (user parameters 102n01–102n07). On the U500Xd2 only M280 has a factory setting there; M281–M287 are identical defaults (the owner's control matches). Set those levels on the control before relying on `smoothingMode` B.
- **Check:** the regression fixtures change only M282 → M283 (finishing) and M285 → M284 (roughing), with no other line affected, in M298 mode, Mode B and TWP-off runs; each automatic category was forced in an instrumented post (M298: TCP gets M284/M280/M281/M283; Mode B: same everywhere); `tests/regression.sh levels` checks the explicit table.

Note on `probingType` Blum: the Blum branches call `G65 P8700` / `P8703`, Blum's own macro numbers. They are only correct on a control with Blum's probing macros installed. On a control with the Renishaw O88xx set (the owner's), O8700 is Renishaw's error-message macro and O8703 is absent, so Blum must not be selected there.
