package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/fallback"
)

func init() {
	register("fallback", "読み込みの途中で bug! していないか", cmdFallback)
}

// fallbackResult は --json 用のまとめ。
type fallbackResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdFallback(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	var body, errBody strings.Builder
	code, err := fallback.Run(&body, &errBody, repoRoot(), dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, fallbackResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
