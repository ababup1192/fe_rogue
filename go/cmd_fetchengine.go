package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/fetchengine"
)

func init() {
	// WhyNot: engineOnly にしないのは、これを呼ぶのが Studio が置き場へ写した engine の
	// 側だから。engine のリポの中でしか使えない形にすると self-update から呼べない。
	register("fetch-engine",
		"公開されている engine の zip を落として置き場へ組み立てる (Studio の self-update 用)",
		cmdFetchEngine)
}

func cmdFetchEngine(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	code, err := fetchengine.Run(out, errOut, dropJSONFlag(rest), asJSON)
	return orAbort(errOut, code, err)
}
