package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/checkd"
)

func init() {
	register("checkd", "flix check / flix test を常駐 repl で速くする (詳細は docs/checkd.md)",
		func(out, errOut *strings.Builder, rest []string, _ bool) int {
			code, err := checkd.Run(out, errOut, repoRoot(), rest)
			return orAbort(errOut, code, err)
		})
}
