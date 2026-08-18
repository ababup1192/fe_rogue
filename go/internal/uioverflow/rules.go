package uioverflow

// 規約データ (bin/lint-rules/ui-overflow.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// RulesPath は規約データの置き場（リポジトリの根からの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "ui-overflow.json")

// anonymousName は name の無いノードの呼び名（規約ではなく表示の文面）。
const anonymousName = "(無名)"

type rulesFile struct {
	GameRoots    []string `json:"gameRoots"`
	ExcludedDirs []string `json:"excludedDirs"`
	Suffix       *string  `json:"suffix"`
	ExemptKey    *string  `json:"exemptKey"`
	ExemptMarker *string  `json:"exemptMarker"`
	TextWidget   *string  `json:"textWidget"`
	WrapAuto     *string  `json:"wrapAuto"`
	GrowWidth    *string  `json:"growWidth"`
}

// Rules は検査が使う規約。すべて JSON から来る。
type Rules struct {
	GameRoots    []string
	ExcludedDirs []string
	Suffix       string
	ExemptKey    string
	ExemptMarker string
	TextWidget   string
	WrapAuto     string
	GrowWidth    string
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
	case f.GameRoots == nil:
		missing = "gameRoots"
	case f.ExcludedDirs == nil:
		missing = "excludedDirs"
	case f.Suffix == nil:
		missing = "suffix"
	case f.ExemptKey == nil:
		missing = "exemptKey"
	case f.ExemptMarker == nil:
		missing = "exemptMarker"
	case f.TextWidget == nil:
		missing = "textWidget"
	case f.WrapAuto == nil:
		missing = "wrapAuto"
	case f.GrowWidth == nil:
		missing = "growWidth"
	}
	if missing != "" {
		return nil, fmt.Errorf("規約ファイルに %s がありません (%s)", missing, path)
	}
	return &Rules{
		GameRoots:    f.GameRoots,
		ExcludedDirs: f.ExcludedDirs,
		Suffix:       *f.Suffix,
		ExemptKey:    *f.ExemptKey,
		ExemptMarker: *f.ExemptMarker,
		TextWidget:   *f.TextWidget,
		WrapAuto:     *f.WrapAuto,
		GrowWidth:    *f.GrowWidth,
	}, nil
}
