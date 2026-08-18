package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/renderbudget"
)

func init() {
	register("check-render-budget", "1 場面が組んだ描き物の数が予算の内側か", cmdRenderBudget)
}

// renderBudgetResult は --json 用のまとめ。
type renderBudgetResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdRenderBudget(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	// --root は規約データ (bin/lint-rules/) を読む先。裁く相手のゲームの根は
	// Python 版と同じく第 1 引数なので、この 2 つを混ぜない。
	rulesRoot, rest := declRootFlag(rest)
	var body, errBody strings.Builder
	code, err := renderbudget.Run(&body, &errBody, rulesRoot, dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, renderBudgetResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
