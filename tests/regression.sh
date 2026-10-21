#!/usr/bin/env bash
set -euo pipefail

# Regression harness for the Brother Speedio post processor.
# See tests/README.md for the workflow.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f "$SCRIPT_DIR/post.env" ]] && source "$SCRIPT_DIR/post.env"

FIXTURES_DIR="${FIXTURES_DIR:-$SCRIPT_DIR/fixtures}"
RUNS_DIR="$SCRIPT_DIR/runs"

if [[ -z "${POST_BIN:-}" ]]; then
  POST_BIN=$(find "$HOME/Library/Application Support/Autodesk/webdeploy/production" \
    -maxdepth 10 -name post -type f 2>/dev/null | head -1 || true)
fi

require_post_bin() {
  if [[ -z "${POST_BIN:-}" || ! -x "$POST_BIN" ]]; then
    echo "error: POST_BIN not set or not executable." >&2
    echo "Copy tests/post.env.example to tests/post.env and set POST_BIN." >&2
    exit 1
  fi
}

derive_label() {
  local cps="$1" rev date
  rev=$(grep -m1 '\$Revision:' "$cps" | awk '{print $2}')
  date=$(grep -m1 '\$Date:' "$cps" | awk '{print $2}')
  if [[ -z "$rev" || -z "$date" ]]; then
    echo "error: could not derive label from $cps (missing \$Revision or \$Date)" >&2
    exit 1
  fi
  echo "${rev}_${date}"
}

cmd_run() {
  local kind="${1:-}" cps="${2:-}"
  if [[ "$kind" != "upstream" && "$kind" != "modified" ]]; then
    echo "usage: $0 run <upstream|modified> <path-to-cps>" >&2; exit 1
  fi
  [[ -f "$cps" ]] || { echo "error: cps not found: $cps" >&2; exit 1; }
  require_post_bin

  local label out_dir count=0 failures=0 expected_failures=0 log
  label=$(derive_label "$cps")
  out_dir="$RUNS_DIR/$kind/$label"
  rm -rf "$out_dir"
  mkdir -p "$out_dir"
  log=$(mktemp)

  echo "Posting $(basename "$cps") against $FIXTURES_DIR"
  echo "  label:   $label"
  echo "  output:  $out_dir"
  [[ -n "${MACHINE_FILE:-}" ]] && echo "  machine: $(basename "$MACHINE_FILE")"

  while IFS= read -r -d '' cnc; do
    local rel="${cnc#$FIXTURES_DIR/}"
    local out="$out_dir/${rel%.cnc}.nc"
    local expected_error
    expected_error=$(expected_failure "$kind" "$rel")
    mkdir -p "$(dirname "$out")"
    local -a post_args=(--log "$log")
    [[ -n "${MACHINE_FILE:-}" ]] && post_args+=(--machine "$MACHINE_FILE")
    # Only emit N numbers on tool changes so inserting/removing a line doesn't
    # shift every subsequent N and create noise in regression diffs.
    post_args+=(--property showSequenceNumbers '"toolChange"')
    # The fixtures are in inches; the modified post stops when the output unit differs from
    # its 'Control unit' property (posts that don't define the property ignore it).
    post_args+=(--property controlUnit '"IN"')
    post_args+=("$cps" "$cnc" "$out")
    : > "$log"
    if "$POST_BIN" "${post_args[@]}" >/dev/null 2>&1; then
      if [[ -n "$expected_error" ]]; then
        failures=$((failures+1))
        echo "  FAIL: $rel posted, expected error: $expected_error"
      else
        count=$((count+1))
      fi
    elif [[ -n "$expected_error" ]] && grep -qF "$expected_error" "$log"; then
      expected_failures=$((expected_failures+1))
      rm -f "$out"
      echo "  expected error: $rel"
    else
      failures=$((failures+1))
      echo "  FAIL: $rel"
    fi
  done < <(find "$FIXTURES_DIR" -name "*.cnc" -print0)
  rm -f "$log"

  echo "Done: $count posted, $expected_failures stopped with their expected error, $failures failed."
  [[ $failures -eq 0 ]]
}

# Fixtures the modified post must refuse, with the error text it must stop with.
# Format of tests/expected-failures.txt: <fixture path relative to FIXTURES_DIR>|<error text>
expected_failure() {
  local kind="$1" rel="$2" file="$SCRIPT_DIR/expected-failures.txt"
  [[ "$kind" == "modified" && -f "$file" ]] || return 0
  awk -F'|' -v rel="$rel" '$1 == rel { print $2; exit }' "$file"
}

# Every fixture posts with useSmoothing at Automatic, so the explicit levels
# are checked here, per property id: a plain fixture (M298 L word, no Mode B),
# a multi-axis fixture (Mode B code under TCP, no M298) and the plain fixture
# with smoothingMode B (Mode B code, no M298).
LEVELS_PLAIN_FIXTURE="Milling/2D/face"
LEVELS_TCP_FIXTURE="Milling/5x Simultaneous/5x contour"
LEVELS_IDS=(0 1 2 3 4 5)
LEVELS_M298=("M298 L1" "M298 L2" "M298 L3" "M298 L4" "M298 L5" "M298 L6")
LEVELS_MODEB=(M280 M284 M280 M282 M281 M283)

check_level_output() {
  local out="$1" pattern="$2" expected="$3" desc="$4" forbidden="$5" got
  got=$(grep -oE "$pattern" "$out" | sort -u | paste -sd ' ' -)
  if [[ "$got" != "$expected" ]]; then
    echo "  FAIL: $desc wrote '$got', expected '$expected'"
    return 1
  fi
  if grep -qE "$forbidden" "$out"; then
    echo "  FAIL: $desc also wrote $(grep -oE "$forbidden" "$out" | sort -u | paste -sd ' ' -)"
    return 1
  fi
  if grep -q "no explicit Mode B mapping" "${out%.nc}.log"; then
    echo "  FAIL: $desc warned about a missing Mode B mapping"
    return 1
  fi
}

cmd_levels() {
  local cps="${1:-}"
  [[ -n "$cps" ]] || { echo "usage: $0 levels <path-to-cps>" >&2; exit 1; }
  [[ -f "$cps" ]] || { echo "error: cps not found: $cps" >&2; exit 1; }
  require_post_bin

  local label out_dir failures=0 checks=0 i id case fixture out
  label=$(derive_label "$cps")
  out_dir="$RUNS_DIR/levels/$label"
  rm -rf "$out_dir"
  mkdir -p "$out_dir"

  echo "Posting $(basename "$cps") at each explicit high accuracy level"
  echo "  output:  $out_dir"

  for i in "${!LEVELS_IDS[@]}"; do
    id="${LEVELS_IDS[$i]}"
    for case in plain multi-axis mode-b; do
      fixture="$LEVELS_PLAIN_FIXTURE"
      [[ "$case" == "multi-axis" ]] && fixture="$LEVELS_TCP_FIXTURE"
      out="$out_dir/$id-$case-$(basename "$fixture").nc"
      local -a post_args=(--log "${out%.nc}.log")
      [[ -n "${MACHINE_FILE:-}" ]] && post_args+=(--machine "$MACHINE_FILE")
      post_args+=(--property useSmoothing "\"$id\"" --property controlUnit '"IN"')
      [[ "$case" == "mode-b" ]] && post_args+=(--property smoothingMode '"B"')
      post_args+=("$cps" "$FIXTURES_DIR/$fixture.cnc" "$out")
      checks=$((checks+1))
      if ! "$POST_BIN" "${post_args[@]}" >/dev/null 2>&1; then
        echo "  FAIL: level $id, $case did not post"
        failures=$((failures+1))
      elif [[ "$case" == "plain" ]]; then
        check_level_output "$out" 'M298 L[0-9]+' "${LEVELS_M298[$i]}" "level $id, $case" 'M28[0-7]' || failures=$((failures+1))
      else
        check_level_output "$out" 'M28[0-7]' "${LEVELS_MODEB[$i]}" "level $id, $case" 'M298' || failures=$((failures+1))
      fi
    done
  done

  echo "Done: $checks checks, $failures failed."
  [[ $failures -eq 0 ]]
}

summarize_diff() {
  local dir_a="$1" dir_b="$2"
  local changed=0 only_a=0 only_b=0

  while IFS= read -r -d '' file; do
    local rel="${file#$dir_a/}"
    if [[ -f "$dir_b/$rel" ]]; then
      if ! cmp -s "$file" "$dir_b/$rel"; then
        echo "  CHANGED: $rel"
        changed=$((changed+1))
      fi
    else
      echo "  REMOVED: $rel"
      only_a=$((only_a+1))
    fi
  done < <(find "$dir_a" -type f ! -name "*.failed" -print0)

  while IFS= read -r -d '' file; do
    local rel="${file#$dir_b/}"
    if [[ ! -f "$dir_a/$rel" ]]; then
      echo "  ADDED:   $rel"
      only_b=$((only_b+1))
    fi
  done < <(find "$dir_b" -type f ! -name "*.failed" -print0)

  echo ""
  echo "Summary: $changed changed, $only_a only-in-A, $only_b only-in-B"
}

cmd_diff() {
  local kind="${1:-}" a="${2:-}" b="${3:-}"
  if [[ "$kind" != "upstream" && "$kind" != "modified" ]] || [[ -z "$a" || -z "$b" ]]; then
    echo "usage: $0 diff <upstream|modified> <labelA> <labelB>" >&2; exit 1
  fi
  local dir_a="$RUNS_DIR/$kind/$a" dir_b="$RUNS_DIR/$kind/$b"
  [[ -d "$dir_a" ]] || { echo "error: missing $dir_a" >&2; exit 1; }
  [[ -d "$dir_b" ]] || { echo "error: missing $dir_b" >&2; exit 1; }
  echo "Diff $kind: $a -> $b"
  summarize_diff "$dir_a" "$dir_b"
}

cmd_diff_pair() {
  local label="${1:-}"
  [[ -n "$label" ]] || { echo "usage: $0 diff-pair <label>" >&2; exit 1; }
  local dir_u="$RUNS_DIR/upstream/$label" dir_m="$RUNS_DIR/modified/$label"
  [[ -d "$dir_u" ]] || { echo "error: missing $dir_u" >&2; exit 1; }
  [[ -d "$dir_m" ]] || { echo "error: missing $dir_m" >&2; exit 1; }
  echo "Diff upstream vs modified at $label"
  summarize_diff "$dir_u" "$dir_m"
}

cmd_show() {
  local kind="${1:-}" label="${2:-}" file="${3:-}"
  if [[ -z "$kind" || -z "$label" || -z "$file" ]]; then
    echo "usage: $0 show <upstream|modified> <label> <fixture-relative-path>" >&2; exit 1
  fi
  local path="$RUNS_DIR/$kind/$label/${file%.cnc}.nc"
  path="${path%.nc}.nc"
  [[ -f "$path" ]] || { echo "error: not found: $path" >&2; exit 1; }
  echo "$path"
}

cmd_list() {
  for kind in upstream modified; do
    echo "$kind runs:"
    if [[ -d "$RUNS_DIR/$kind" ]]; then
      ls -1 "$RUNS_DIR/$kind" 2>/dev/null | sed 's/^/  /'
    else
      echo "  (none)"
    fi
  done
}

usage() {
  cat <<EOF
usage: $0 <command> [args]

commands:
  run <upstream|modified> <cps>       Post all fixtures through the given .cps,
                                       label derived from its \$Revision / \$Date.
  diff <upstream|modified> <A> <B>    Compare two labeled runs of the same kind
                                       (the regression check).
  diff-pair <label>                   Compare upstream vs modified at a given
                                       label (inspect what our changes produce).
  levels <cps>                        Post with each explicit high accuracy level
                                       and check the M298 L / M28x words written.
  list                               List available labeled runs.

environment (override via tests/post.env):
  POST_BIN        Path to Autodesk post binary (auto-detected on macOS).
  MACHINE_FILE    Path to .mch machine config (required for 4/5-axis fixtures).
  FIXTURES_DIR    Fixture root (default: tests/fixtures).
EOF
}

case "${1:-}" in
  run)       shift; cmd_run "$@" ;;
  diff)      shift; cmd_diff "$@" ;;
  diff-pair) shift; cmd_diff_pair "$@" ;;
  show)      shift; cmd_show "$@" ;;
  levels)    shift; cmd_levels "$@" ;;
  list)      cmd_list ;;
  ""|-h|--help|help) usage ;;
  *) echo "unknown command: $1" >&2; usage; exit 1 ;;
esac
