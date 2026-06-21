#!/usr/bin/env bash
# B7: -v prints a readable AST. Freeze the format against a golden so any
# accidental change to the dump shape is caught. -s stops after the dump.
prog="${TMPDIR:-/tmp}/ast_dump_$$.lator"
printf 'n is 3\nbig is items where price > 50\n' > "$prog"
got="$("$COMPI" "$prog" -v -s 2>/dev/null)"
rm -f "$prog"
read -r -d '' want << 'GOLDEN'
syntax OK
PROGRAM
  ASSIGN
    ID "n"
    INT 3
  ASSIGN
    ID "big"
    FILTER
      ID "items"
      CMP >
        ID "price"
        INT 50
GOLDEN
[ "$got" = "$want" ]
