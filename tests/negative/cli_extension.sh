#!/usr/bin/env bash
# .lator extension is enforced by the CLI
tmp=$(mktemp /tmp/XXXX.txt); echo 'x is 5' > "$tmp"
"$COMPI" "$tmp" 2>/tmp/e; code=$?
rm -f "$tmp"
[ $code -eq 1 ] && grep -q "extension" /tmp/e
