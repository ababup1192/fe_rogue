package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/updateplan"
)

func init() {
	// WhyNot: engineOnly にするのは、古いバージョンの pub 面を git のタグから取り出すため。
	// ゲームのリポにも Studio 同梱の木にも .git が無いので、そこでは走らない。
	// （バージョンごとのスナップショットを配れば外でも走るが、それはまだ無い）
	registerEngineOnly("update-plan",
		"ゲーム 1 本を新しい engine へ載せ替える指示書を書く", cmdUpdatePlan)
}

func cmdUpdatePlan(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)
	code, err := updateplan.Run(out, errOut, root, dropJSONFlag(rest))
	return orAbort(errOut, code, err)
}
