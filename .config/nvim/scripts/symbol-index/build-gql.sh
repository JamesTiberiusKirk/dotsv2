#!/usr/bin/env bash
# Args: <repo-root> <out-dir>
# Writes two files:
#   <out-dir>/resolver-to-gql.tsv   : <MethodName>\t<schemaFile>:<line>
#   <out-dir>/gql-to-resolver.tsv   : <fieldName>\t<resolverFile>:<line>
set -euo pipefail
root="$1"; outdir="$2"
cd "$root"

r2g="$outdir/resolver-to-gql.tsv"
g2r="$outdir/gql-to-resolver.tsv"
: > "$r2g"; : > "$g2r"

[ -d gql-schemas ] || exit 0
[ -d services ] || exit 0

# Resolver methods: TypeResolver.Method -> file:line
# Capture method name only.
tmp_resolvers=$(mktemp)
rg -n --no-heading -o -P -g '*resolvers*.go' \
  'func\s*\(\s*\w+\s+\*?\w+Resolver\s*\)\s*\K[A-Za-z_][A-Za-z0-9_]*' \
  services 2>/dev/null \
  | awk -F: 'BEGIN{OFS="\t"} { print $NF, $1":"$2 }' > "$tmp_resolvers"

# One rg pass: all gql field declarations -> tmp_fields (field<TAB>file:line)
tmp_fields=$(mktemp)
rg -n --no-heading -o -P -g '*.graphql' -g '*.graphqls' \
  '^\s*\K[a-z][A-Za-z0-9_]*(?=\s*[(:])' \
  gql-schemas 2>/dev/null \
  | awk -F: 'BEGIN{OFS="\t"} { print $NF, $1":"$2 }' > "$tmp_fields"

# Join: for each resolver method, lowercase first letter, look up in tmp_fields.
# Use awk hash for O(n+m).
awk -F'\t' '
  BEGIN { OFS="\t" }
  NR==FNR { if (!(($1) in seen)) { fields[$1]=$2; seen[$1]=1 } next }
  {
    method=$1; rloc=$2;
    field=tolower(substr(method,1,1)) substr(method,2);
    if (field in fields) {
      gloc=fields[field];
      print method, gloc >> "'"$r2g"'"
      print field,  rloc >> "'"$g2r"'"
    }
  }
' "$tmp_fields" "$tmp_resolvers"

rm -f "$tmp_resolvers" "$tmp_fields"
