package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/apidiff"
)

func init() {
	registerEngineOnly("api-diff", "2 つのバージョンの pub 面を突き合わせて壊れた物を出す", cmdAPIDiff)
}

func cmdAPIDiff(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)
	if asJSON {
		rest = append(dropJSONFlag(rest), "--json")
	}
	code, err := apidiff.Run(out, errOut, root, rest)
	return orAbort(errOut, code, err)
}
