package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/anim"
)

func init() {
	register("anim", "コマ列の飛び・体積・接地と 4 方向のそろい", cmdAnim)
}

// animResult は --json 用のまとめ。
type animResult struct {
	Lines []string `json:"lines"`
	Exit  int      `json:"exit"`
}

func cmdAnim(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	var body strings.Builder
	code, err := anim.Run(&body, repoRoot(), dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, animResult{splitLines(body.String()), code})
		return code
	}
	out.WriteString(body.String())
	return code
}
