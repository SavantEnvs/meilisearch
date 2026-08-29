#!/usr/bin/env bash
#
# mayhem/test.sh — behavioral oracle for the Meilisearch filter-parser integration.
#
# Two layers (SPEC §6.3 anti-reward-hacking), BOTH mandatory:
#   1. Unconditional KAT probes: run the dynamically-linked mayhem/kat probe
#      (built by build.sh) on FIXED filter strings and grep its EXACT output values
#      from bash (bash/coreutils are whitelisted by the sabotage shim, so the compare
#      happens where sabotage cannot hide). Missing binary/wrong output = FAIL.
#   2. filter-parser's own assertion suite (cargo test: the insta snapshot /
#      known-answer parser tests), precompiled by build.sh — parsed from libtest's
#      own summary lines, with "no results parsed" a hard failure.
#
# Emits a CTRF summary + a compact `CTRF {...}` stdout line; exit 0 iff failed==0.
# Does NOT compile the world (build.sh did). Every cargo invocation uses an explicit
# +$RUST_CHANNEL — upstream's root rust-toolchain.toml pins stable 1.91.1 and would
# hijack bare cargo.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
RUST_CHANNEL="${RUST_CHANNEL:-nightly-2025-06-01}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

KAT_PASS=0
KAT_FAIL=0

# ── Layer 1: KAT probes (UNCONDITIONAL — a missing probe is a FAILURE, never a skip)
KAT_BIN="$SRC/mayhem/kat/target/release/meili-filter-kat"
KAT_OUT="$("$KAT_BIN" 2>&1)" || KAT_OUT="${KAT_OUT:-<probe did not run>}"
echo "--- KAT probe output ---"
echo "$KAT_OUT"
# Fixed filter string → asserted exact parsed/printed value (see mayhem/kat/src/main.rs).
kat_expect() { # kat_expect <exact line>
  if printf '%s\n' "$KAT_OUT" | grep -qxF "$1"; then
    echo "KAT OK: $1"; KAT_PASS=$((KAT_PASS+1))
  else
    echo "KAT FAIL: expected exact line: $1" >&2; KAT_FAIL=$((KAT_FAIL+1))
  fi
}
kat_expect "KAT1 {channel} = {Ponce}"                                              # simple equality condition
kat_expect "KAT2 {subscribers} = {12}"                                             # numeric value
kat_expect "KAT3 AND[{colour} IN[{green}, {blue}, ], {color} = {green}, ]"          # IN + AND precedence + list render
kat_expect "KAT4 empty=true geoPointErr=true"                                       # Ok(None) on empty; reserved _geoPoint errors

# ── Layer 2: filter-parser's own suite (prebuilt; resolves from the build cache) ──
LOG="$(mktemp)"
env -u RUSTFLAGS -u CFLAGS -u CXXFLAGS cargo +"${RUST_CHANNEL}" test -p filter-parser --no-fail-fast 2>&1 | tee "$LOG"

# libtest summary lines: "test result: ok. N passed; M failed; K ignored; ..."
PASSED=$(grep -hoE '[0-9]+ passed'  "$LOG" | awk '{s+=$1} END{print s+0}')
FAILED=$(grep -hoE '[0-9]+ failed'  "$LOG" | awk '{s+=$1} END{print s+0}')
SKIPPED=$(grep -hoE '[0-9]+ ignored' "$LOG" | awk '{s+=$1} END{print s+0}')
rm -f "$LOG"

# If we parsed nothing, the runner did not actually run — hard failure.
if [ "$((PASSED + FAILED + SKIPPED))" -eq 0 ]; then
  echo "ERROR: no libtest results parsed — test runner did not execute" >&2
  FAILED=$((FAILED + 1))
fi

emit_ctrf "meili-filter-kat+cargo-test" "$((PASSED + KAT_PASS))" "$((FAILED + KAT_FAIL))" "$SKIPPED"
