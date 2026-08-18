package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/apiindex"
)

func init() {
	register("check-api-index", "pub def を持つモジュールが索引に載っているか", cmdAPIIndex)
}

// apiIndexResult は --json 用のまとめ。
type apiIndexResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdAPIIndex(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)

	var body, errBody strings.Builder
	code, err := apiindex.Run(&body, &errBody, root, dropJSONFlag(rest), apiindex.Options{})
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, apiIndexResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
