package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/uioverflow"
)

func init() {
	register("ui-overflow", "ui.json の text の折り返し宣言漏れ (はみ出す形)", cmdUIOverflow)
}

// uiOverflowResult は --json 用のまとめ。
type uiOverflowResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdUIOverflow(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	var body, errBody strings.Builder
	code, err := uioverflow.Run(&body, &errBody, repoRoot(), dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, uiOverflowResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
