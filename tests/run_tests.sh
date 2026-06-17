#!/usr/bin/env bash
# compiLATOR test harness (T1).
# Tiers:
#   tests/positive/  must succeed today and forever (regression guard)
#   tests/negative/  must fail today with the asserted diagnostics
#   tests/xfail/     SPEC-mandated behavior, currently failing; one per TODO B-item.
#                    Reported as XFAIL; an unexpected pass (XPASS) means a fix
#                    landed -> promote the test to positive/negative.
# Per-test sidecars (all optional except .exit):
#   NAME.exit  expected exit code (required)
#   NAME.out   exact expected stdout
#   NAME.err   each non-empty line must appear as a substring of stderr
# Custom tests: NAME.sh is executed with $COMPI set; script exit 0 = pass.
# Lexer golden: tests/lexer/tokens.src vs tests/lexer/tokens.golden (exact stdout).

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPI="$ROOT/bin/compi"
LEXER="$ROOT/bin/lexer"
export COMPI

pass=0; fail=0; xfail=0; xpass=0
failed_names=""

run_case() {  # $1=file.lator -> sets CHECK_OK, fills DETAIL
    local f="$1" base="${1%.lator}"
    local want_exit; want_exit="$(cat "$base.exit")"
    local out err code
    out="$(cd "$ROOT/tests" && "$COMPI" "$f" 2>/tmp/case_err)"; code=$?
    err="$(tr -d '\000' < /tmp/case_err)"
    CHECK_OK=1; DETAIL=""
    if [ "$code" -ne "$want_exit" ]; then
        CHECK_OK=0; DETAIL="exit $code, expected $want_exit"
    fi
    if [ -f "$base.out" ] && [ "$out" != "$(cat "$base.out")" ]; then
        CHECK_OK=0; DETAIL="$DETAIL; stdout mismatch"
    fi
    if [ -f "$base.err" ]; then
        while IFS= read -r frag || [ -n "$frag" ]; do
            [ -z "$frag" ] && continue
            case "$err" in *"$frag"*) ;; *) CHECK_OK=0; DETAIL="$DETAIL; stderr missing: '$frag'";; esac
        done < "$base.err"
    fi
}

tier() {  # $1=dir $2=mode(strict|xfail)
    local dir="$ROOT/tests/$1" mode="$2" f name
    [ -d "$dir" ] || return 0
    for f in "$dir"/*.lator; do
        [ -e "$f" ] || continue
        name="$1/$(basename "$f")"
        run_case "$f"
        if [ "$mode" = strict ]; then
            if [ "$CHECK_OK" = 1 ]; then pass=$((pass+1)); echo "PASS  $name"
            else fail=$((fail+1)); failed_names="$failed_names $name"; echo "FAIL  $name ($DETAIL)"; fi
        else
            if [ "$CHECK_OK" = 1 ]; then xpass=$((xpass+1)); echo "XPASS $name  <-- fix landed: promote this test"
            else xfail=$((xfail+1)); echo "XFAIL $name"; fi
        fi
    done
    for f in "$dir"/*.sh; do
        [ -e "$f" ] || continue
        name="$1/$(basename "$f")"
        if bash "$f" >/dev/null 2>&1; then pass=$((pass+1)); echo "PASS  $name"
        else fail=$((fail+1)); failed_names="$failed_names $name"; echo "FAIL  $name"; fi
    done
}

# lexer golden
if [ -f "$ROOT/tests/lexer/tokens.golden" ]; then
    got="$("$LEXER" < "$ROOT/tests/lexer/tokens.src")"
    if [ "$got" = "$(cat "$ROOT/tests/lexer/tokens.golden")" ]; then
        pass=$((pass+1)); echo "PASS  lexer/tokens golden"
    else
        fail=$((fail+1)); failed_names="$failed_names lexer/tokens"; echo "FAIL  lexer/tokens golden (stdout mismatch)"
    fi
fi

tier positive strict
tier negative strict
tier xfail xfail

echo
echo "summary: $pass passed, $fail failed, $xfail xfail, $xpass xpass"
[ -n "$failed_names" ] && echo "failed:$failed_names"
[ "$fail" -eq 0 ] || exit 1
exit 0