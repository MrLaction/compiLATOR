#!/usr/bin/env bash
# -s runs syntax stage only
f=$(dirname "$0")/../positive/basics.lator
out=$("$COMPI" "$f" -s); code=$?
[ $code -eq 0 ] && [ "$out" = "syntax OK" ]
