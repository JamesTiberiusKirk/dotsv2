#!/usr/bin/env bash
# Args: <repo-root> <cache-dir>
set -euo pipefail
root="$1"; cache="$2"
here="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$cache"

"$here/build-proto.sh" "$root" "$cache/proto-symbols.tsv" &
"$here/build-gql.sh"   "$root" "$cache" &
wait
