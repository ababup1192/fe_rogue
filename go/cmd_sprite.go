package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/sprite"
)

func init() {
	register("sprite", "ドット絵 (*.sprite.json) の画素の並び", cmdSprite)
}

// spriteResult は --json 用のまとめ。
type spriteResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdSprite(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	var body, errBody strings.Builder
	code, err := sprite.Run(&body, &errBody, repoRoot(), dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, spriteResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
