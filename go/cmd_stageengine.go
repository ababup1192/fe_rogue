package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/stageengine"
)

func init() {
	registerEngineOnly("stage-engine", "同梱 engine 一式を組み立てる (Studio / bundle-zip の共通の口)", cmdStageEngine)
}

// stageEngineResult は --json 用のまとめ。
type stageEngineResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdStageEngine(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)

	var body, errBody strings.Builder
	code, err := stageengine.Run(&body, &errBody, root, dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, stageEngineResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
