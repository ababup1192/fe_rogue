package renderbudget

// 規約データ (bin/lint-rules/check-render-budget.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// RulesPath は規約データの置き場（リポジトリの根からの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "check-render-budget.json")

type rulesFile struct {
	DefaultCap  *int64   `json:"defaultCap"`
	DriftFactor *float64 `json:"driftFactor"`
	DriftFloor  *int64   `json:"driftFloor"`
}

// Rules は検査が使う規約。すべて JSON から来る。
type Rules struct {
	DefaultCap  int64
	DriftFactor float64
	DriftFloor  int64
}

// LoadRules は規約データを読む。
// WhyNot: 読めないときに既定値へ倒さないのは、規約ファイルを消しただけで
// 上限が別の数に化けたまま緑になる穴を作らないため。呼ぶ側は必ずエラーで止める。
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
	case f.DefaultCap == nil:
		missing = "defaultCap"
	case f.DriftFactor == nil:
		missing = "driftFactor"
	case f.DriftFloor == nil:
		missing = "driftFloor"
	}
	if missing != "" {
		return nil, fmt.Errorf("規約ファイルに %s がありません (%s)", missing, path)
	}
	return &Rules{
		DefaultCap:  *f.DefaultCap,
		DriftFactor: *f.DriftFactor,
		DriftFloor:  *f.DriftFloor,
	}, nil
}
