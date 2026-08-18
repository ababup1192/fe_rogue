package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/f32"
)

func init() {
	registerEngineOnly("f32", "engine の pub 面に Float32 が出ていないか", cmdF32)
}

// f32Result は --json 用のまとめ。
type f32Result struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdF32(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)
	exemptJSON, rest, hasExempt := declValueFlag(rest, "--exempt-json")

	var opts f32.Options
	if hasExempt {
		// 見本 (testdata/lint/f32/) が除外一覧そのものを差し替えるための口。
		exempt, err := f32.ParseExempt(exemptJSON)
		if err != nil {
			return orAbort(errOut, 2, err)
		}
		opts.Exempt = exempt
	}

	var body, errBody strings.Builder
	code, err := f32.Run(&body, &errBody, root, dropJSONFlag(rest), opts)
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, f32Result{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}

// declRootFlag は `--root DIR` を取り出す。無ければ既定の根。
// WhyNot: 位置引数で受けないのは、位置引数を全部ファイル名として扱うため。
// 見に行く先を差し替える口が無いと、見本 (testdata/lint/) から検査を呼べない。
func declRootFlag(args []string) (string, []string) {
	root, rest, ok := declValueFlag(args, "--root")
	if !ok {
		return repoRoot(), rest
	}
	return root, rest
}

// declValueFlag は `--name 値` / `--name=値` を取り除いて値を返す。
func declValueFlag(args []string, name string) (string, []string, bool) {
	value, found := "", false
	var out []string
	for i := 0; i < len(args); i++ {
		switch {
		case args[i] == name && i+1 < len(args):
			value, found = args[i+1], true
			i++
		case strings.HasPrefix(args[i], name+"="):
			value, found = strings.TrimPrefix(args[i], name+"="), true
		default:
			out = append(out, args[i])
		}
	}
	return value, out, found
}
