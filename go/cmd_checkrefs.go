package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/checkrefs"
)

func init() {
	register("check-refs", "文章や Makefile が指す先が実在するか", cmdCheckRefs)
}

// checkRefsResult は --json 用のまとめ。
type checkRefsResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdCheckRefs(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)

	var body, errBody strings.Builder
	code, err := checkrefs.Run(&body, &errBody, root, dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, checkRefsResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
