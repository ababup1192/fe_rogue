package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/apidigest"
)

func init() {
	registerEngineOnly("api-digest", "engine の pub 面を 1 枚のダイジェストへ書き出す", cmdAPIDigest)
}

// apiDigestResult は --json 用のまとめ。
type apiDigestResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdAPIDigest(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)
	var body, errBody strings.Builder
	code, err := apidigest.Run(&body, &errBody, root, dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, apiDigestResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
