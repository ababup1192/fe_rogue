package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/carve"
)

func init() {
	register("carve", "3 面図から立体を彫り出し、4 方向へ描き直す", cmdCarve)
	register("adopt", "外から来た絵を 4 方向 × 歩き 3 コマに仕立てる", cmdAdopt)
	register("carve-pngread", "PNG の大きさ・中身・色数を出す", cmdCarvePNGRead)
	register("carve-render", "sprite.json の文字格子を PNG に描く", cmdCarveRender)
	register("carve-gifs", "コマの PNG を並べて動く GIF にする", cmdCarveGifs)
	register("carve-sheet", "工程の絵を 4 方向 × コマの一覧に並べる", cmdCarveSheet)
}

// carveResult は --json 用のまとめ。
type carveResult struct {
	Lines []string `json:"lines"`
	Exit  int      `json:"exit"`
}

// carveScriptDir は carve の書き出し先を数える起点 (bin/)。
//
// WhyNot: 実行したディレクトリを使わないのは、adopt / render / gifs / sheet の
// 書き出し先が、呼んだ場所によって動いてしまうため。
func carveScriptDir() string {
	return filepath.Join(repoRoot(), "bin")
}

func runCarveCmd(out, errOut *strings.Builder, asJSON bool,
	fn func(*strings.Builder, *carve.Rules) (int, error)) int {
	rules, err := carve.LoadRules(repoRoot())
	if err != nil {
		fmt.Fprintf(errOut, "fge-go: %v\n", err)
		return 2
	}
	var body strings.Builder
	code, err := fn(&body, rules)
	if err != nil {
		fmt.Fprintf(errOut, "fge-go: %v\n", err)
	}
	if asJSON {
		emitJSON(out, carveResult{splitLines(body.String()), code})
		return code
	}
	out.WriteString(body.String())
	return code
}

func cmdCarve(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	return runCarveCmd(out, errOut, asJSON, func(body *strings.Builder, rules *carve.Rules) (int, error) {
		cwd, err := os.Getwd()
		if err != nil {
			return 1, err
		}
		return carve.RunCarve(body, cwd, dropJSONFlag(rest), rules)
	})
}

func cmdAdopt(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	return runCarveCmd(out, errOut, asJSON, func(body *strings.Builder, rules *carve.Rules) (int, error) {
		return carve.RunAdopt(body, carveScriptDir(), dropJSONFlag(rest), rules)
	})
}

func cmdCarvePNGRead(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	return runCarveCmd(out, errOut, asJSON, func(body *strings.Builder, _ *carve.Rules) (int, error) {
		return carve.RunPNGRead(body, dropJSONFlag(rest))
	})
}

func cmdCarveRender(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	return runCarveCmd(out, errOut, asJSON, func(body *strings.Builder, _ *carve.Rules) (int, error) {
		return carve.RunRender(body, carveScriptDir(), dropJSONFlag(rest))
	})
}

func cmdCarveGifs(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	return runCarveCmd(out, errOut, asJSON, func(body *strings.Builder, rules *carve.Rules) (int, error) {
		return carve.RunGifs(body, carveScriptDir(), dropJSONFlag(rest), rules)
	})
}

func cmdCarveSheet(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	return runCarveCmd(out, errOut, asJSON, func(body *strings.Builder, rules *carve.Rules) (int, error) {
		return carve.RunSheet(body, carveScriptDir(), dropJSONFlag(rest), rules)
	})
}
