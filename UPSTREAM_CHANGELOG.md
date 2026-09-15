# Upstream changelog

A log of what changed in each upstream Brother Speedio post (`upstream/<rev>.cps`)
pulled via `update.sh`, why Autodesk likely made the change, and how it impacted
our merge into `modified/<rev>.cps`.

Newest first. Each entry records the upstream delta only — our own customizations
are documented in [CUSTOMIZATIONS.md](CUSTOMIZATIONS.md).

How to read the **Merge impact** line: "clean" means the upstream hunk landed in
code we don't customize and merged without a conflict; a conflict is called out
explicitly with how it was resolved. "Regression" reports the G-code diff of our
*modified* post between the two revs (via `tests/regression.sh diff modified <A> <B>`).

---

## 44242 — 2026-09-07 (from 44241)

### What changed upstream

`protectedProbeMove()` now uses the operation's `tool_feedProbeLink` parameter
for protected XY and Z positioning, falling back to `_cycle.feedrate` when the
parameter is absent. Previously XY used `highFeedrate` and Z used `cycle.feedrate`.

### Merge impact

- Ported clean; the customization diff against upstream is unchanged.
- Our safe-probing rapid-move protection remains intact, including its existing
  high-feed setting. This upstream change affects protected cycle positioning.
- All 45 fixtures posted successfully for previous/new upstream and modified
  versions (180 successful posts, zero failures).
- Four probing fixtures changed: `PG Rectangle Boss`, `update tool wear`,
  `PWCS Bore with override`, and `PWCS Rectangle block`. Each changed one emitted
  protected-positioning feed word from F39.4 to F118.1 (inch-mode fixtures),
  honoring the operation's probe-link feedrate. Modal feed also applies to
  subsequent protected moves until another feed is emitted.
- Modified output deltas exactly match upstream output deltas; the other 41
  fixtures are unchanged. Validation covers generated output, not machine trials.

---

## 44241 — 2026-09-02 (from 44229)

### What changed upstream

One line in `onCommand(COMMAND_LOAD_TOOL)`, immediately after the G100 tool block:

```
- currentWorkPlaneABC = abc ? abc : currentWorkPlaneABC; // workplane is set with the G100 command
+ currentWorkPlaneABC = defineWorkPlane(currentSection, false); // workplane is set with the G100 command
```

The local `abc` is `undefined` whenever `settings.workPlaneMethod.useTiltedWorkplane`
is on (G68.2 mode): the G100 block then carries no A/B/C words and the TWP is
established by `defineWorkPlane(currentSection, true)` *before* the tool call. With
the old expression the tracked workplane was left untouched in that mode.

### Why (likely rationale)

`writeToolCall()` calls `forceWorkPlane()` (→ `currentWorkPlaneABC = undefined`) on
every non-first tool change, after `onSection` has already set the TWP. In non-G68
mode the old line repaired that immediately (`abc` is a real vector). In G68 mode it
did not, so the tracked workplane stayed `undefined` after each G100. The next
same-tool section's `setWorkPlane()` then saw "workplane unknown" and emitted a full
re-index — Z retract, G49, `G00 A0. C0.`, G43 re-apply — and `onClose()`'s
`setWorkPlane(0,0,0)` emitted a redundant `G00 A0. C0.` before M30. Deriving the
value from the section instead of the local fixes the G68 path.

### Merge impact

- Ported clean — one line plus the header. None of our customizations touch the
  workplane code.
- **Regression (modified 44229 → 44241):** 4 fixtures changed, all by *removing*
  output, and only because we run with `useG68 = true` (upstream's own output, G68
  off, is byte-identical across the bump):
  - `Milling/2D/full program.nc`: the same-tool section after the T02 tool change
    lost its spurious `G28 G91 Z0 / G90 / G49 / G00 A0. C0.` retract and the
    `G43 … H02` re-apply. It now matches upstream's structure for that section.
  - `Milling/2D/toolchange.nc`, `Milling/2D/optional stop.nc`,
    `Probing/Geometry/update tool wear.nc`: the trailing `G00 A0. C0.` between
    `G53 G00 X0 Y0` and `M30` is gone.
  - The other 41 fixtures are byte-identical (single-tool programs never reach the
    `forceWorkPlane()` in `writeToolCall`). All 45 fixtures post with 0 failures.

---

## 44229 — 2026-06-12 (from 44227)

### What changed upstream

Simulation-only: `machineSimulation()` gained a `rotaryMode` parameter
(`SHORTEST` | `PROGRAMMED`). When given, and `revision >= 50338`, the simulation's
rotary direction is switched via `simulation.setRotaryToGoShortestDirection()` /
`setRotaryToGoProgrammedDirection()` around the move and restored afterwards.
Unknown values raise an error. No G-code path was touched.

### Why (likely rationale)

Lets the backplot / machine simulation honor the rotary direction the post actually
commanded for a given move (e.g. a forced long-way unwind) instead of always
assuming the shortest path.

### Merge impact

- Ported clean. Not logged at the time; this entry was backfilled with the 44241
  bump.
- **Regression (modified 44227 → 44229):** byte-identical across all 45 fixtures,
  as expected for a simulation-only change.

---

## 44227 — 2026-05-26 (from 44222)

### What changed upstream

1. **Length-compensation / TCP API refactor (≈80% of the diff).** A pure
   rename-and-restructure of the tool-length-compensation and TCP machinery, with
   no change to emitted G-code:
   - `toolLengthCompOutput` → `lengthCompOutput`
   - `getOffsetCode()` → `getLengthCompCode()`
   - `disableLengthCompensation()` → `cancelLengthCompensation()`
   - Inline magic numbers `43 / 43.4 / 43.5 / 49` replaced by a named table
     `lengthCompCodes = {tool:43, tcp:43.4, tcpVector:43.5, cancel:49}`
   - Include files `getOffsetCode_fanuc.cpi` + `disableLengthCompensation_fanuc.cpi`
     merged into `lengthCompFunctions_fanuc.cpi` + `cancelLengthCompensation_fanuc.cpi`
   - `setTCP(_tcp, force)` promoted from an *optional* per-post function into the
     shared Fanuc include, collapsing all the
     `if (typeof setTCP == "function") { … } else { … }` fallback branches to a
     plain `setTCP(…)` call.
   - `cancelLengthCompensation` now early-returns when `lengthCompCodes.cancel` is
     falsy, tolerating controls with no G49 cancel.

2. **Back-boring (G87) Z-reference fix.** The Z word changed from
   `cycle.bottom - cycle.backBoreDistance` to `z + dz`, where `dz` is non-zero only
   in the G17 plane — matching the plane-aware `dx`/`dy`/`dz` already computed above
   it. This is the only behavioral change in the release.

3. **Simulation work-coordinate hook (new).** When the work offset changes between
   operations, the post now calls `simulation.activateWorkCoordsForNextOperation()`,
   gated behind `revision >= 50338` (a Fusion CAM-kernel version guard).

4. **Property `order` fields (cosmetic).** `order: 1/2/3` added to
   `showSequenceNumbers`, `sequenceNumberStart`, `sequenceNumberIncrement` to pin
   their position in Fusion's post-properties dialog.

### Why (likely rationale)

The refactor (#1) is Autodesk normalizing their Fanuc-derived post library: hoisting
literal G-codes into one `lengthCompCodes` object and standardizing `setTCP` means a
control with different codes (or no cancel) overrides a single table instead of
forking three functions, and the naming becomes consistent (`lengthComp*` everywhere
instead of mixed `offsetCode` / `toolLengthComp`). #2 is a correctness fix so
back-boring honors the active working plane (G18/G19) instead of hardcoding the
offset into Z. #3 improves backplot accuracy across WCS changes while staying safe on
older Fusion installs. #4 is pure dialog cosmetics.

### Merge impact

- **One conflict.** Upstream's G49-cancel rename
  (`toolLengthCompOutput.format(49)` → `lengthCompOutput.format(lengthCompCodes.cancel)`)
  landed on the same `onOpen()` line where our safe-start block (`M299`/`G69`/`M318`,
  customization #5) is inserted. Resolved by taking upstream's renamed line and
  keeping our block immediately after it.
- Everything else merged clean — our customizations live in `setSmoothing` /
  property / probing code that the rename didn't touch, and none of our code
  references the renamed functions (verified: no stale `getOffsetCode` /
  `disableLengthCompensation` / `toolLengthCompOutput` references remain).
- **Regression (modified 44222 → 44227):** only `Milling/Drilling/back boring.nc`
  changed — `Z-0.6378` → `Z-0.622`, byte-identical to upstream's own change for that
  fixture (the rename produced zero G-code differences). All 45 fixtures post with
  0 failures.

---

## 44222 — 2026-04-15 (from 44220)

### What changed upstream

Coordination around G100's spindle stop/restart:
- Skip the redundant `startSpindle` in `onSection` when a following G100 will run it.
- Set `forceSpindleSpeed = true` after a G100 tool-axis retract so the next section
  re-emits the spindle speed.

### Why (likely rationale)

G100 (Brother's combined tool-change/orient block) internally stops and restarts the
spindle; emitting `startSpindle` separately is redundant and re-forcing the speed
after a retract avoids a stale modal spindle state on the next section.

### Merge impact

- Both fixes ported into the modified copy; merged clean.
- **Regression (modified 44220 → 44222):** byte-identical across all fixtures — the
  new branches only fire on multi-section patterns we don't currently exercise
  (consecutive same-tool 5-axis sims, or 5-axis → 3-axis with no tool change).

---

## 44220 — 2026-04-01 (from 44214)

### What changed upstream

`initializeSmoothing()` was parameterized to operate on an arbitrary section:
- Signature `initializeSmoothing()` → `initializeSmoothing(_section)`, defaulting to
  `currentSection`; all `getProperty` / `getParameter` calls inside rebound to
  `_section`.
- Smoothing is now allowed on multi-axis **connection** sections
  (`_section.isConnectionSection() && _section.isMultiAxis()`).
- On `isFirstSection()`, `smoothing.isActive` is reset to `undefined`.

### Why (likely rationale)

Parameterizing by section lets the framework evaluate smoothing for look-ahead /
connection sections rather than only the active one — needed so smoothing state is
correct across linked multi-axis moves.

### Merge impact

- Ported clean.
- Noted at the time: this rev's `isFirstSection → smoothing.isActive = undefined`
  caused our post to emit a spurious `M299` on the first drilling/probing section.
  That interaction is the reason customization #10 sets `smoothing.isActive = false`
  there instead — see CUSTOMIZATIONS.md #10, part in `initializeSmoothing()`.

---

## 44214 — 2026-02-17 (baseline)

First upstream snapshot tracked in this repo. No prior upstream delta recorded;
serves as the regression baseline for 44220.
