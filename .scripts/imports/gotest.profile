# ---- init completion (safe) ----
if ! typeset -f compinit >/dev/null; then
  autoload -Uz compinit
fi
compinit -i

# ---- collect Test* + subtests (incl. table-driven) from ./... ----
_grun_collect_tests() {
  command -v go >/dev/null 2>&1 || { echo "go not found in PATH" >&2; return 1; }

  local tmp="${TMPDIR:-/tmp}/grun_list_$$.go"
  cat >"$tmp" <<'EOF'
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type tableDef struct {
	ident  string
	fields map[string]int     // field name -> index
	rows   [][]string         // strings per row by index
}

func main() {
	root := "."
	if len(os.Args) > 1 {
		root = os.Args[1]
	}
	fset := token.NewFileSet()
	tests := map[string]struct{}{}

	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil { return nil }
		if d.IsDir() {
			name := d.Name()
			if name == "vendor" || strings.HasPrefix(name, ".git") || name == "node_modules" || name == "bin" || name == "dist" {
				return filepath.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(path, "_test.go") { return nil }

		file, err := parser.ParseFile(fset, path, nil, parser.SkipObjectResolution)
		if err != nil { return nil }

		tables := findTables(file)

		for _, decl := range file.Decls {
			fn, ok := decl.(*ast.FuncDecl)
			if !ok || fn.Name == nil || fn.Body == nil { continue }
			name := fn.Name.Name
			if strings.HasPrefix(name, "Test") {
				tests[name] = struct{}{}
				collectInFunc(fn.Body, []string{name}, tests, tables, nil)
			}
		}
		return nil
	})

	out := make([]string, 0, len(tests))
	for k := range tests { out = append(out, k) }
	sort.Strings(out)
	for _, t := range out { fmt.Println(t) }
}

type loopCtx map[string]*tableDef // loop var ident ("tt") -> tableDef

// collectInFunc walks statements, tracking range loops like "for _, tt := range tests { ... }"
// so that t.Run(tt.name, ...) can be expanded from the right table.
func collectInFunc(node ast.Node, chain []string, acc map[string]struct{}, tables map[string]*tableDef, ctx loopCtx) {
	if ctx == nil { ctx = loopCtx{} }

	ast.Inspect(node, func(n ast.Node) bool {
		switch x := n.(type) {
		case *ast.RangeStmt:
			// match: for _, tt := range tests { ... }
			lhs := ""
			if id, ok := x.Value.(*ast.Ident); ok && id != nil {
				lhs = id.Name // tt
			}
			rhsIdent := ""
			if id, ok := x.X.(*ast.Ident); ok && id != nil {
				rhsIdent = id.Name // tests
			}
			if lhs != "" && rhsIdent != "" {
				if td, ok := tables[rhsIdent]; ok {
					// push ctx for this loop body
					newCtx := loopCtx{}
					for k, v := range ctx { newCtx[k] = v }
					newCtx[lhs] = td
					collectInFunc(x.Body, chain, acc, tables, newCtx)
					return false
				}
			}
			// otherwise, just descend
			return true

		case *ast.CallExpr:
			// look for <something>.Run(arg0, fn)
			sel, ok := x.Fun.(*ast.SelectorExpr)
			if !ok || sel.Sel == nil || sel.Sel.Name != "Run" { return true }
			if len(x.Args) < 1 { return true }

			// CASE A: literal name
			if lit, ok := x.Args[0].(*ast.BasicLit); ok {
				if lit.Kind == token.STRING {
					if name, err := strconv.Unquote(lit.Value); err == nil && name != "" {
						next := append(append([]string{}, chain...), name)
						acc[strings.Join(next, "/")] = struct{}{}
						// descend into body if present
						if len(x.Args) >= 2 {
							if fn, ok := x.Args[1].(*ast.FuncLit); ok && fn.Body != nil {
								collectInFunc(fn.Body, next, acc, tables, ctx)
							}
						}
					}
				}
				return true
			}

			// CASE B: selector like tt.name
			if selArg, ok := x.Args[0].(*ast.SelectorExpr); ok {
				base, baseOK := selArg.X.(*ast.Ident)
				field := selArg.Sel.Name
				if baseOK {
					if td, ok := ctx[base.Name]; ok {
						if idx, ok := td.fields[field]; ok {
							for _, row := range td.rows {
								if idx < len(row) && row[idx] != "" {
									next := append(append([]string{}, chain...), row[idx])
									acc[strings.Join(next, "/")] = struct{}{}
								}
							}
						}
					}
				}
				// still visit body for deeper literals
				if len(x.Args) >= 2 {
					if fn, ok := x.Args[1].(*ast.FuncLit); ok && fn.Body != nil {
						collectInFunc(fn.Body, chain, acc, tables, ctx)
					}
				}
				return true
			}
			return true
		}
		return true
	})
}

// findTables gathers simple table literals:
//   tests := []struct{ name string; ... }{
//       {name: "A"}, {name: "B"},
//   }
// and positional form: {"A"}, {"B"} (field order respected)
func findTables(file *ast.File) map[string]*tableDef {
	res := map[string]*tableDef{}

	add := func(name string, fields map[string]int, cl *ast.CompositeLit) {
		td := &tableDef{ident: name, fields: fields}
		// map field->index complete set
		max := -1
		for _, idx := range fields { if idx > max { max = idx } }
		for _, elt := range cl.Elts {
			row := make([]string, max+1)
			if elem, ok := elt.(*ast.CompositeLit); ok {
				if len(elem.Elts) > 0 {
					switch elem.Elts[0].(type) {
					case *ast.KeyValueExpr:
						for _, e := range elem.Elts {
							if kv, ok := e.(*ast.KeyValueExpr); ok {
								if key, ok := kv.Key.(*ast.Ident); ok {
									if s, ok := asString(kv.Value); ok {
										if idx, ok := fields[key.Name]; ok && idx < len(row) {
											row[idx] = s
										}
									}
								}
							}
						}
					default:
						for i, e := range elem.Elts {
							if s, ok := asString(e); ok && i < len(row) {
								row[i] = s
							}
						}
					}
				}
			}
			td.rows = append(td.rows, row)
		}
		res[name] = td
	}

	ast.Inspect(file, func(n ast.Node) bool {
		switch x := n.(type) {
		case *ast.AssignStmt:
			// tests := []struct{...}{...}
			if len(x.Lhs) == 1 && len(x.Rhs) == 1 {
				lhs, lok := x.Lhs[0].(*ast.Ident)
				cl, cok := x.Rhs[0].(*ast.CompositeLit)
				if lok && cok {
					if arr, ok := cl.Type.(*ast.ArrayType); ok {
						if st, ok := arr.Elt.(*ast.StructType); ok {
							fields := map[string]int{}
							for i, f := range st.Fields.List {
								for _, nm := range f.Names {
									fields[nm.Name] = i
								}
							}
							add(lhs.Name, fields, cl)
						}
					}
				}
			}
		case *ast.ValueSpec:
			// var tests = []struct{...}{...}
			for i, v := range x.Values {
				if cl, ok := v.(*ast.CompositeLit); ok {
					if arr, ok := cl.Type.(*ast.ArrayType); ok {
						if st, ok := arr.Elt.(*ast.StructType); ok {
							fields := map[string]int{}
							for i2, f := range st.Fields.List {
								for _, nm := range f.Names {
									fields[nm.Name] = i2
								}
							}
							if i < len(x.Names) {
								add(x.Names[i].Name, fields, cl)
							}
						}
					}
				}
			}
		}
		return true
	})
	return res
}

func asString(n ast.Expr) (string, bool) {
	if bl, ok := n.(*ast.BasicLit); ok && bl.Kind == token.STRING {
		s, err := strconv.Unquote(bl.Value)
		return s, err == nil
	}
	return "", false
}
EOF

  local out
  out=$(go run "$tmp" . 2>/dev/null)
  rm -f "$tmp"

  if [[ -n "$out" ]]; then
    printf "%s\n" "$out"
    return 0
  fi

  # Fallback: top-level tests at least
  go test -list . ./... 2>/dev/null | awk '/^Test/ {print $1}' | sort -u
}

# ---- grun: defaults to ./...; no pkg arg ----
#   grun            -> fzf picker of all tests (runs selection)
#   grun <regex>    -> go test ./... -run "<regex>"
#   grun <args...>  -> pass through to `go test`
grun() {
  if [[ $# -eq 0 ]]; then
    local testname
    testname=$(_grun_collect_tests | fzf --prompt="Pick test> " --height=40% --reverse)
    [[ -z "$testname" ]] && return 0   # aborted
    echo "▶ go test ./... -run ^${testname}\$"
    go test ./... -run "^${testname}\$"
    return $?
  fi

  if [[ $# -eq 1 ]]; then
    go test ./... -run "$1"
  else
    go test "$@"
  fi
}

# ---- completion: suggest first-arg only ----
_grun() {
  if [[ -z "${CURRENT:-}" || "$CURRENT" != 2 ]]; then
    return 0
  fi
  local out
  out=$(_grun_collect_tests)
  [[ -z "$out" ]] && return 0
  local -a tests
  tests=(${(f)out})
  compadd -- $tests
}
compdef _grun grun
