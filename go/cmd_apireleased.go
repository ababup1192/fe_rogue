package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/apireleased"
)

func init() {
	register("check-api-released", "digest にあってリリース済みの版に無い宣言", cmdAPIReleased)
}

// apiReleasedResult は --json 用のまとめ。
type apiReleasedResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdAPIReleased(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)

	var body, errBody strings.Builder
	code, err := apireleased.Run(&body, &errBody, root, dropJSONFlag(rest), apireleased.Options{})
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, apiReleasedResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
