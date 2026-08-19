package view

// 規約データ (bin/lint-rules/view.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/ababup1192/flix_game_engine/go/internal/pxlib"
)

// RulesPath は規約データの置き場（リポジトリのルートからの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "view.json")

type rulesFile struct {
	RectPattern  *string `json:"rectPattern"`
	RichPattern  *string `json:"richPattern"`
	MinDraws     *int    `json:"minDraws"`
	RectPct      *int    `json:"rectPct"`
	Destinations *string `json:"destinations"`
}

// Rules は検査が使う規約。すべて JSON から来る。
type Rules struct {
	Rect         *pxlib.PyRegexp
	Rich         *pxlib.PyRegexp
	MinDraws     int
	RectPct      int
	Destinations string
}

// LoadRules は規約データを読む。
// WhyNot: 読めないときに既定値へ倒さないのは、規約ファイルを消しただけで
// 検査が黙って緑になる穴を作らないため。呼ぶ側は必ずエラーで止める。
func LoadRules(root string) (*Rules, error) {
	path := filepath.Join(root, RulesPath)
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("規約ファイルを読めません: %v", err)
	}
	var f rulesFile
	if err := json.Unmarshal(data, &f); err != nil {
		return nil, fmt.Errorf("規約ファイルが JSON として壊れています (%s): %v", path, err)
	}
	missing := ""
	switch {
	case f.RectPattern == nil:
		missing = "rectPattern"
	case f.RichPattern == nil:
		missing = "richPattern"
	case f.MinDraws == nil:
		missing = "minDraws"
	case f.RectPct == nil:
		missing = "rectPct"
	case f.Destinations == nil:
		missing = "destinations"
	}
	if missing != "" {
		return nil, fmt.Errorf("規約ファイルに %s がありません (%s)", missing, path)
	}
	rect, err := pxlib.CompilePy(*f.RectPattern)
	if err != nil {
		return nil, fmt.Errorf("規約ファイルの rectPattern が正規表現として壊れています (%s): %v", path, err)
	}
	rich, err := pxlib.CompilePy(*f.RichPattern)
	if err != nil {
		return nil, fmt.Errorf("規約ファイルの richPattern が正規表現として壊れています (%s): %v", path, err)
	}
	return &Rules{
		Rect:         rect,
		Rich:         rich,
		MinDraws:     *f.MinDraws,
		RectPct:      *f.RectPct,
		Destinations: *f.Destinations,
	}, nil
}
