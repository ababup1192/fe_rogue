package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/prunetools"
)

func init() {
	registerEngineOnly("prune-stale-tools", "Go 移行で役目を終えた Python の道具をゲームから消す (一度きり)",
		cmdPruneStaleTools)
}

// pruneStaleToolsResult は --json 用のまとめ。
type pruneStaleToolsResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdPruneStaleTools(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)
	var body, errBody strings.Builder
	code, err := prunetools.Run(&body, &errBody, root, dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, pruneStaleToolsResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
