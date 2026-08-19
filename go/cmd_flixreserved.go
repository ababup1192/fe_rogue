package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/flixreserved"
)

func init() {
	// WhyNot: engineOnly にしないのは、配った先のゲームでも同じ穴を踏むため
	// (踏むと型検査が終わらなくなるので、ゲーム側でこそ効く)。
	register("flix-reserved",
		"Flix の予約語を識別子に使っていないか (踏むと型検査が終わらなくなる)",
		cmdFlixReserved)
}

func cmdFlixReserved(out, errOut *strings.Builder, rest []string, _ bool) int {
	root, rest := declRootFlag(rest)
	code, err := flixreserved.Run(out, errOut, root, rest)
	return orAbort(errOut, code, err)
}
