# Regression testing

Runs the Autodesk post binary over a set of `.cnc` fixtures (3, 3+2, 5-axis milling + probing + drilling + coolant) to catch unintended changes in generated G-code when we bump upstream or change our customizations.

## How it works

Post processor versions live as committed files under:

- `upstream/<rev>_<date>.cps` — vanilla snapshots from Autodesk
- `modified/<rev>_<date>.cps` — our customized versions, one per upstream bump

NC outputs (generated when regression runs) live under `tests/runs/<upstream|modified>/<rev>_<date>/` — gitignored, always regenerable.

The two comparisons that matter:

- **Regression** — `modified/N` vs `modified/N-1` (same track, across an upstream bump). This is the signal we watch.
- **Sanity** — `upstream/N` vs `modified/N` (same point, different track). Tells you what our customizations actually produce in the NC output.

## Setup

`tests/post.env` holds machine-local paths and is gitignored. Copy the template and edit it once:

```bash
cp tests/post.env.example tests/post.env
```

Then set `MACHINE_FILE` to the absolute path of your `.mch` machine config. The 4/5-axis fixtures need a machine configuration — without it the post fails with `requires a machine configuration for N-axis toolpath`.

To find the `.mch` path on macOS:

```bash
find "$HOME/Library/Application Support/Autodesk/Autodesk Fusion 360" \
     -name '*.mch' -path '*CAMMachines*'
```

Pick the entry matching your machine (for the U500XD2-5AX, the file is `brother u500Xd2.mch`; skip any copy under a `backup/` folder, which Fusion no longer updates) and paste it as the `MACHINE_FILE` value, wrapped in double quotes so the spaces survive. Example:

```bash
MACHINE_FILE="$HOME/Library/Application Support/Autodesk/Autodesk Fusion 360/<userhash>/W.login/M2/<orghash>/CAMMachines/brother u500Xd2.mch"
```

`POST_BIN` is auto-detected on macOS from the Fusion install — leave it commented unless auto-detect fails or you want to pin a specific build. Fixtures live under `tests/fixtures/` (committed — see attribution below).

## Typical workflow — after an upstream bump

After `./update.sh` has saved the new `upstream/<new-label>.cps` and bootstrapped `modified/<new-label>.cps`, apply your customization merges into the new modified file, then:

```bash
./tests/regression.sh run upstream upstream/<prev-label>.cps
./tests/regression.sh run upstream upstream/<new-label>.cps
./tests/regression.sh run modified modified/<prev-label>.cps
./tests/regression.sh run modified modified/<new-label>.cps

./tests/regression.sh list
./tests/regression.sh diff modified <prev-label> <new-label>   # the regression check
./tests/regression.sh diff upstream <prev-label> <new-label>   # what upstream changed
./tests/regression.sh diff-pair <new-label>                    # what our customizations do
```

Some fixtures exercise output the modified post deliberately refuses (for example `tcp with tsc` uses T0, which G100 does not accept). They are listed in `tests/expected-failures.txt` as `<fixture path>|<error text>`. On a `modified` run, a listed fixture passes only if posting stops with that error text; if it posts, or stops with a different error, it counts as a failure. Upstream runs ignore the list.

Every fixture posts with the high accuracy level at Automatic, so the explicit levels get their own check. It posts one plain and one multi-axis fixture with each explicit `useSmoothing` choice and fails if the M298 L word or the Mode B code under TCP is not the one that choice should write (outputs and post logs under `tests/runs/levels/<label>/`). It applies to the modified post only, since upstream does not default to M298:

```bash
./tests/regression.sh levels modified/<new-label>.cps
```

To see a full diff on one file:

```bash
diff -u "$(./tests/regression.sh show modified <labelA> Milling/3+2/b30)" \
        "$(./tests/regression.sh show modified <labelB> Milling/3+2/b30)"
```

## Fixture attribution

The `.cnc` fixtures under `tests/fixtures/Milling` and `tests/fixtures/Probing` are copied from Autodesk's [cam-posteditor](https://github.com/Autodesk/cam-posteditor) VS Code extension (`vs-code-extension/res/CNC files/`), MIT-licensed. Copyright © 2017 Autodesk, Inc. The full MIT license text is reproduced in [tests/fixtures/LICENSE](fixtures/LICENSE). The set has been pruned to what runs cleanly on the U500XD2-5AX machine configuration (A-axis-only, air/mist/suction coolant, and inspect-surface probing fixtures were removed as unsupported).
