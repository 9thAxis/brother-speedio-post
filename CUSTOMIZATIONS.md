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
  settings.smoothing.modeBRoughing = 5;
  settings.smoothing.modeBSemi = 3;
  settings.smoothing.modeBSemifinishing = 1;
  settings.smoothing.modeBFinishing = 2;
  ```
- **Why:** The framework default for finishing is L5. M298 L6 ("Finishing S") is the optimal setting for 3D surface finishing on the D00 control. The Mode B levels are fallback mappings used by `setSmoothing()` during multi-axis TCP operations (see #10).

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
- **Why:** Outputs an L value in G77 tapping cycles for faster withdrawal (up to 6000 RPM). Takes advantage of the 16K spindle's capability.

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

  3. **Level mapping** — M298 and Mode B use different level numbering. An automatic M298 level (set by `initializeSmoothing`) is mapped to the equivalent Mode B level by category: roughing→5, semi→3, semifinishing→1, finishing→2. Mappings are stored in `settings.smoothing.modeB*` (see #3). An explicit `useSmoothing` level uses the property's own `[0, 5, 3, 4, 1, 2]` mapping instead (see #12).

  4. **`setSmoothing` moved before tool call in `onSection()`** — Smoothing codes must be output before G100 (which activates G43.4 TCP internally). Moved from after coolant to before the `insertToolCall` block. Also moved before G100 in `onClose()`.

  5. **`initializeSmoothing()` TCP transition detection** — Forces smoothing re-output when switching between TCP and non-TCP sections. Without this, the `isDifferent` guard in `setSmoothing()` would skip output when the smoothing level is the same but the required M-code changes (M298 vs M280).

  Both `setSmoothing()` and `initializeSmoothing()` decide TCP with `sectionUsesTCP(section)` = `isMultiAxis() || isTCPSupportedByOperation(section)`, evaluated from the section itself. `setSmoothing()` runs before `defineWorkPlane()` sets `tcp.isSupportedByOperation` and before the section is optimized, so reading those gave a stale answer: with `useTiltedWorkplane` off, 3+2 sections run under G43.4 and used to get `M298 L2` before `G100 … G43.4` (alarm). They now get Mode B; default output is unchanged.

- **Why:** Without this, any program mixing 3-axis and 5-axis operations with smoothing enabled would alarm on the first multi-axis section. The D00 manual explicitly states M280-M287 is valid regardless of TCP state, making it the correct choice for 5-axis work.

- **NC output example (3-axis → 5-axis transition with tool change):**
  ```
  M299         (cancel M298 — setSmoothing(false) on tool change)
  ...
  M282         (Mode B finishing — compatible with TCP)
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
  M282         (Mode B finishing — compatible with TCP)
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
  3. **`smoothingMode` value `"A"`** (and the `case "A":` branches in `onOpen` and `setSmoothing`) — Mode A outputs M260/M269, which is the legacy CNC-B00/C00 smoothing syntax. D00v does not support it. Mode B and M298 remain.
- **Why:** These parameters could never produce correct output on this machine, and exposing them risks someone toggling one and getting wrong kinematics or invalid M-codes. Simplifies `defineMachine()` to rely purely on the CAM-provided machine config (which is the correct source of truth for axis ranges, trunnion layout, etc.).

## 12. Explicit high accuracy levels write the level their title names

- **Where:** `setSmoothing()` function (`grep 'isExplicitLevel'`)
- **What:** The explicit `useSmoothing` choices have ids 0 to 5, which are offsets from level 1 (Standard = 0 … Finishing high = 5). Two fixes, both gated on `isExplicitLevel` (property id 0 to 5) so the Automatic levels (2, 3, 4, 6), which overlap that range, are left as they were:
  1. **M298 branch** — writes `L` + (id + 1). Upstream writes the raw id, so every explicit choice lands one level below its title and Standard writes `M298 L0`, which turns high accuracy off (Programming Manual 13.3: L0 off, L1 Standard, L2 Rough, L3 Medium rough, L4 Medium rough S, L5 Finishing, L6 Finishing S).
  2. **TCP fallback (#10)** — maps an explicit id through the property's `[0, 5, 3, 4, 1, 2]` table, as the plain Mode B branch does, instead of looking it up in `modeBLevelMap`, whose keys are the Automatic L numbers. Before, ids 0, 1 and 5 hit no entry (warning) and 1, 2, 3 and 5 wrote the wrong M28x code.

  | Property choice   | M298 (upstream → ours) | Under TCP (before → after) |
  |-------------------|------------------------|----------------------------|
  | Standard          | L0 → L1                | M280 (warning) → M280      |
  | Roughing          | L1 → L2                | M281 (warning) → M285      |
  | Medium rough      | L2 → L3                | M285 → M283                |
  | Medium rough high | L3 → L4                | M283 → M284                |
  | Finishing         | L4 → L5                | M281 → M281                |
  | Finishing high    | L5 → L6                | M285 (warning) → M282      |

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
- **Why:** O8810 keeps F in a local variable, so F is not carried between calls; a call without F uses the protected feeds set on the control by O8724 — `#119` = `#509` for XY and `#113` = 0.6 × `#509` for Z (5000 / 3000 mm/min unless `#509` is changed), with the prove-out and production mode overrides Renishaw built in. Upstream's mix meant the descent to measuring depth (no F) ran at 3000 mm/min right after a move at the CAM link feed. The Renishaw settings on the control are the reference. Blum (P8703) moves keep upstream's feeds.

## 15. Refuse what the control would alarm on, or would run wrongly

These are validation errors and warnings only; none changes generated motion. Each is checked by the regression run or by an instrumented post in the audit (see AUDIT.md).

| Check | Where | Reason |
|---|---|---|
| Error for any probe operation whose tool axis is not +Z | `writeProbeCycle()` | Renishaw cycles cannot run under coordinate rotation (Inspection Plus manual, "cancel code G69"); upstream only refused WCS probing, and only with `useTiltedWorkplane` off. |
| Error instead of rotary-offset angle compensation (`AXIS_ROT`) | `setProbeAngle()` | The slot assumes Fanuc numbering (`#5225` = C for G54). On the D00 the rotaries are the 5th (A) and 6th (C) axes, so `#5225` is most likely A. Disabled until confirmed on the control. |
| 0 % tool wear feedback writes `F0` | `getProbingArguments()` | Upstream wrote `F100` for 0 % (a 100× correction); the macro expects 0 to 1. |
| Error when a tap's spindle speed exceeds 6000 | `writeDrillCycle()`, `maximumTappingSpeed` | Machine parameter 11000058 (Max. tapping speed) = 6000; G77/G78/G84 alarm above it. |
| Tap `L` word formatted through `rpmFormat` and capped at `maximumTappingSpeed` | `writeDrillCycle()` | A fractional rpm printed as `L3819.7186342`. |
| Error for manual boring | `writeDrillCycle()` | Upstream wrote G88, which the D00 does not have. |
| Error for canned cycles and G02/G03/G02.4 under TCP | `writeDrillCycle()`, `onCircular()` | Not allowed under G43.4/G43.5 (programming manual 14). Arcs that are linearized are unaffected. |
| Error for tool numbers outside 1–99 and 201–299 | `validateToolData()` | G100 reads T101–199 as pots and T901–930 as groups; T0 is invalid. |
| Error when a rewind (retract and reconfigure) occurs | `onMoveToSafeRetractPosition()` | The TCP retract is `G100 T<current>`, which stops the spindle; nothing restarted it before re-entry. |
| Error when the output unit differs from the new `controlUnit` property (Millimeters / Inches, default Millimeters for this machine) | `onOpen()` | The CNC-D00 has no G20/G21 (not in the programming manual's G-code list), so the program cannot switch units: a mismatch scales every value by 25.4 — on a metric control an inch program's 30 mm clearance becomes about 1.2 mm. The post only wrote a comment. Inch-spec D00 machines set the property to Inches. |
| Corner cycles (O8815/O8816, Blum P8700 A1) write X/Y as arguments, not through the modal outputs | `writeProbeCycle()` | Upstream set the modal X/Y to the corner point, but the macro returns the probe to its start point; a later move to that X or Y was dropped (reproduced: `G65 P8810 Y2.5748` instead of `X1.9748 Y2.5748`), and a corner X/Y equal to the modal value was left off the macro call. Restores the CAM's motion. |
| Dwells below 1 s are kept (minimum 0.001 s) | `onDwell()`, `writeDrillCycle()` | Upstream raised every dwell to 1 s; P is in seconds with Program unit = Base (011001 = 0). |
| Warning when G73/G83 drop the CAM's peck reduction | `warnDegressivePecking()` | The cycles take a fixed Q. |
| Warning when fine/back boring has a shift orientation | `warnShiftOrientation()` | The D00 shifts by user parameter 012004 (+X here), not by the CAM value. |
