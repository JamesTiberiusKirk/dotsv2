#!/usr/bin/env bash
# Args: <repo-root> <out-file>
# Output TSV: <symbol>\t<file>:<line>
set -euo pipefail
root="$1"; out="$2"
cd "$root"

dirs=()
[ -d protos ] && dirs+=(protos)
[ -d modules ] && dirs+=(modules)
if [ ${#dirs[@]} -eq 0 ]; then : > "$out"; exit 0; fi

{
  # message/service/enum declarations (top-level + nested both get matched)
  rg -n --no-heading -o -P -g '*.proto' \
    '^(?:\s*)(?:message|service|enum)\s+\K[A-Za-z_][A-Za-z0-9_]*' \
    "${dirs[@]}" 2>/dev/null \
    | awk -F: 'BEGIN{OFS="\t"} { sym=$NF; print sym, $1":"$2 }'

  # rpc methods
  rg -n --no-heading -o -P -g '*.proto' \
    '^\s*rpc\s+\K[A-Za-z_][A-Za-z0-9_]*' \
    "${dirs[@]}" 2>/dev/null \
    | awk -F: 'BEGIN{OFS="\t"} { sym=$NF; print sym, $1":"$2 }'
} > "$out"
