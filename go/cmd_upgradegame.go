package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/upgradegame"
)

func init() {
	// WhyNot: engineOnly にするのは、載せ替える元の fpkg が engine のリポにしか無く、
	// 当たる非互換の数え上げが古いバージョンの pub 面を git のタグから取り出すため。
	registerEngineOnly("upgrade-game",
		"ゲーム 1 本を新しい engine へ載せ替える (check が緑なら agents-pack も配る)",
		cmdUpgradeGame)
}

func cmdUpgradeGame(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)
	code, err := upgradegame.Run(out, errOut, root, dropJSONFlag(rest), asJSON)
	return orAbort(errOut, code, err)
}
