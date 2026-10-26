# Brother Speedio Post Processor

Customized [Autodesk Fusion](https://cam.autodesk.com/hsmposts) post processor for the **Brother Speedio U500XD2-5AX** (CNC-D00v control, 16K RPM, CTS, 28-tool magazine, Renishaw probe).

The upstream post (`brother_speedio.cps`) is a generic post that covers the entire Speedio family — S, W, R, U, F, and H series. Its defaults target older controls (CNC-B00/C00) and the most conservative settings. This repo tracks a customized version tuned for the D00v control and the U500XD2-5AX's specific capabilities.

## What's changed

See [CUSTOMIZATIONS.md](CUSTOMIZATIONS.md) for the full list with rationale. In short:

- **M298 smoothing with Mode B fallback** — The D00 control uses the M298 Ln system for high-accuracy mode, not the legacy M260/M269 codes. Smoothing is set to automatic with L6 for finishing surfaces. Since M298 is incompatible with G43.4/G43.5 TCP, multi-axis sections automatically use Mode B (M280-M287) instead — the only smoothing mode the D00 allows during TCP.
- **G68.2 tilted workplane** — Required for [3+2 positional machining](https://plasticranger.com/g68-2-cnc-code/) on the 5-axis trunnion table.
- **Safe start block** — Outputs `M299` and `G69` at program start to cancel residual M298 machining mode and workplane rotation from previously aborted programs.
- **Washdown coolant** — Enabled between operations for chip management in the enclosed work area.
- **Double tap withdraw** — Takes advantage of the 16K spindle for faster G77 tapping cycles.
- **Safe probing** — Once the probe is switched on, rapid moves in a probe operation use G65 P8810 (protected positioning with G31 P2 skip-on-trigger) instead of bare G0, at the protected feeds set on the control. Stops with a PATH OBSTRUCTED alarm if the probe contacts anything. The approach to the operation's clearance height (G100 tool call or initial G00) comes before the probe is on and is not protected.
- **Refuses unsafe or unsupported output** — Posting stops with an error instead of writing code the D00 would alarm on or run wrongly: probing on a tilted plane, taps above the maximum tapping speed, G88, arcs or canned cycles under TCP, invalid G100 tool numbers, and rewinds. See [CUSTOMIZATIONS.md](CUSTOMIZATIONS.md) #15.
- **Angle compensation on the C axis** — An angle probe adds the measured skew to the C work offset (`#5226` for G54) and turns the work offset's X/Y about the C centreline, read from the control at run time. The next operation re-indexes C. See [CUSTOMIZATIONS.md](CUSTOMIZATIONS.md) #17.
- **Stuck chips detection** — Optional M318 output at program start to monitor Z-axis load during tool changes and detect debris between spindle face and tool holder.

## Options

These properties can be toggled in Fusion's post processor dialog:

| Property | Default | Description |
|---|---|---|
| Enable safe probing | ON | Uses protected positioning (O8810) instead of G0 for rapids inside probe operations once the probe is on. The approach to clearance height is not covered. Disable for maximum speed in production when you trust your WCS. |
| Maximum tapping speed | 6000 | Machine parameter 11000058, in rpm. Posting stops when a tap's spindle speed exceeds it, and it caps the doubled withdraw speed. 6000 for 10K/12K/16K spindles, 8000 for 27K. |
| Control unit | Millimeters | The unit the control is set to. The CNC-D00 has no G20/G21, so posting stops if the NC program's unit differs. Set to Inches for an inch-spec machine. |
| Commissioning mode | ON | Stops (M0) after each inspection operation so the operator can check measurements. Disable for production runs. |
| Stuck chips detection | OFF | Outputs M318 at program start to enable Z-axis load monitoring during tool changes. Only useful once your magazine tool lineup is stable — frequent tool swaps cause false alarms against the learned baselines. |

## Smoothing level mapping

The post is set to **Automatic** smoothing, which selects the M298/Mode B level based on the operation's stock-to-leave in Fusion. Multi-axis TCP sections automatically use Mode B (M280-M287) instead of M298 since they are mutually exclusive on the D00 control.

### Automatic mode (stock-to-leave thresholds)

| Fusion stock-to-leave | Category | 3-axis (M298) | 5-axis TCP (Mode B) |
|---|---|---|---|
| >= 0.5mm (or face op) | Roughing | M298 L2 | M284 |
| 0.1 – 0.5mm | Semi-roughing | M298 L3 | M280 |
| 0.05 – 0.1mm | Semi-finishing | M298 L4 | M281 |
| < 0.05mm (or 0) | Finishing | M298 L6 | M283 |

Probing and drilling cycles always skip smoothing regardless of the setting.

### Manual override

If `useSmoothing` is changed from Automatic to a fixed level in the post properties:

| Property value | M298 level | Mode B code |
|---|---|---|
| Off | _(no output)_ | _(no output)_ |
| Standard | M298 L1 | M280 |
| Roughing | M298 L2 | M284 |
| Medium rough | M298 L3 | M280 |
| Medium rough high | M298 L4 | M282 |
| Finishing | M298 L5 | M281 |
| Finishing high | M298 L6 | M283 |

Note: the property ids (0-5) are offsets from level 1, so each choice writes the M298 level its title names (Programming Manual 13.3: L0 off, L1 Standard … L6 Finishing S). Upstream writes the raw id, one level too low (see [CUSTOMIZATIONS.md](CUSTOMIZATIONS.md) #12). Mode B codes follow the D00 Mode B levels (M280 surface medium, M281 + shape, M282 surface high, M283 + shape, M284 high speed + smooth); see [CUSTOMIZATIONS.md](CUSTOMIZATIONS.md) #16. Automatic is recommended — it picks the right level per operation based on your CAM setup.

## Repo layout

- `upstream/<rev>_<date>.cps` — committed vanilla snapshots from Autodesk (one per pulled version)
- `modified/<rev>_<date>.cps` — our customized versions (one per upstream bump)
- `tests/` — regression testing harness (see [tests/README.md](tests/README.md))
- [CUSTOMIZATIONS.md](CUSTOMIZATIONS.md) — every change we make to upstream, with rationale
- [UPSTREAM_CHANGELOG.md](UPSTREAM_CHANGELOG.md) — what changed in each upstream bump and how it affected the merge

Fusion should be pointed at the most recent `modified/<latest>.cps` as its post processor.

## Updating to a new upstream version

```bash
bash update.sh
```

This downloads the latest post from the [Autodesk post library](https://cam.autodesk.com/hsmposts), parses its `$Revision` / `$Date`, and saves it as `upstream/<rev>_<date>.cps`. It also seeds `modified/<rev>_<date>.cps` by copying the previous modified version, giving you a starting point for re-applying our changes. Review [CUSTOMIZATIONS.md](CUSTOMIZATIONS.md), merge upstream's changes into the new modified file, then run `tests/regression.sh` to verify. Record the upstream delta and its merge impact in [UPSTREAM_CHANGELOG.md](UPSTREAM_CHANGELOG.md).

## Disclaimer

This post processor is provided as-is, with no promises or guarantees of accuracy, safety, or fitness for any purpose. Use it at your own risk. You are responsible for verifying all G-code output before running it on your machine. I am not responsible for any damage to your machine, tooling, workpiece, or anything else — including but not limited to setting your machine on fire.

## License

Original work in this repo is MIT-licensed — see [LICENSE](LICENSE). Upstream Brother Speedio post (`upstream/*.cps`) is Autodesk's work and remains subject to their terms; CNC fixtures under `tests/fixtures/` are redistributed under MIT with Autodesk's 2017 copyright (see [tests/fixtures/LICENSE](tests/fixtures/LICENSE)).

## Links

- [Autodesk post processor library](https://cam.autodesk.com/hsmposts) — upstream source
- [Post processor API reference](https://cam.autodesk.com/posts/reference/index.html) — .cps framework documentation
- [Post processor training guide (PDF)](https://cam.autodesk.com/posts/posts/guides/Post%20Processor%20Training%20Guide.pdf) — customization walkthrough
- [Brother U500XD2-5AX](https://machinetool.global.brother/en-us/all-products/uxd2/u500xd2-5ax) — machine product page
- [Brother CNC-D00 control](https://machinetool.global.brother/en-eu/cnc-d00) — control product page
- [G68.2 tilted workplane reference](https://plasticranger.com/g68-2-cnc-code/) — technical guide
