package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/genrules"
)

func init() {
	registerEngineOnly("gen-rules", "docs/ の規約から .claude/rules/*.md を作る", cmdGenRules)
}

// genRulesResult は --json 用のまとめ。
type genRulesResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdGenRules(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)
	// --out は書き出し先の差し替え。突き合わせのときリポの .claude/rules を
	// 上書きしないための口（生成物どうしを別の場所で比べる）。
	outBase, rest, _ := declValueFlag(rest, "--out")

	var body, errBody strings.Builder
	code, err := genrules.Run(&body, &errBody, root, dropJSONFlag(rest), genrules.Options{OutBase: outBase})
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, genRulesResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
