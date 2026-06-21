#!/usr/bin/env bash
# Regression: many unique scalar identifiers must compile without hanging.
# Two defects caused an infinite linear-probe loop in the symbol table:
#   1. str_eq wrote bl, corrupting sym_lookup's probe index (rbx).
#   2. the probe had no full-table guard, so a saturated table looped forever.
# 200 unique ids stay within the 256-slot table, so the result must be a
# clean exit 0 -- never a hang. timeout turns a regression into a failure
# instead of a hung suite. The temp file must end in .lator (check_ext).
prog="${TMPDIR:-/tmp}/symtable_many_ids_$$.lator"
for i in $(seq 0 199); do echo "a$i is 1"; done > "$prog"
timeout 10 "$COMPI" "$prog" >/dev/null 2>&1
code=$?
rm -f "$prog"
[ "$code" -eq 0 ]
