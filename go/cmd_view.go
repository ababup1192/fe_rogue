package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/view"
)

func init() {
	register("view", "View が矩形と円だけになっていないか", cmdView)
}

// viewResult は --json 用のまとめ。
type viewResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdView(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	var body, errBody strings.Builder
	code, err := view.Run(&body, &errBody, repoRoot(), dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, viewResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
