package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/syncagents"
)

func init() {
	register("sync-agents", "agents-pack をゲームのリポへ配る", cmdSyncAgents)
}

// syncAgentsResult は --json 用のまとめ。
type syncAgentsResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdSyncAgents(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)
	var body, errBody strings.Builder
	code, err := syncagents.Run(&body, &errBody, root, dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, syncAgentsResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
