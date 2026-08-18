package main

import (
	"os"
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/explainerror"
)

func init() {
	register("explain-error", "flix check / test の出力を要約し処方箋 1 行を添える (標準入力)", cmdExplainError)
}

// cmdExplainError はパイプのフィルタ。
//
// WhyNot: --json を持たないのは、読み手が人 (check に落ちた人) だけで、
// 出力そのものが make check の画面になるため。
func cmdExplainError(out, errOut *strings.Builder, rest []string, _ bool) int {
	code, err := explainerror.Run(out, repoRoot(), rest, os.Stdin)
	return orAbort(errOut, code, err)
}
