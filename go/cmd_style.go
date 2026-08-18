package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/style"
)

func init() {
	register("style", "焼いた PNG の画風の軸がズレていないか", cmdStyle)
}

// styleResult は --json 用のまとめ。
type styleResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdStyle(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	var body, errBody strings.Builder
	code, err := style.Run(&body, &errBody, repoRoot(), dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, styleResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
