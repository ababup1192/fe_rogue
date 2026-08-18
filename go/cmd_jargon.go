package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/jargon"
)

func init() {
	register("jargon", "独自の比喩語が新しく入っていないか", cmdJargon)
}

// jargonResult は --json 用のまとめ。
type jargonResult struct {
	Lines []string `json:"lines"`
	Exit  int      `json:"exit"`
}

func cmdJargon(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	var body strings.Builder
	code, err := jargon.Run(&body, errOut, repoRoot(), dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, jargonResult{splitLines(body.String()), code})
		return code
	}
	out.WriteString(body.String())
	return code
}
