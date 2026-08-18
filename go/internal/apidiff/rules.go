package apidiff

// 規約データ (bin/lint-rules/api-diff.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// RulesPath は規約データの置き場（リポジトリのルートからの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "api-diff.json")

type rulesFile struct {
	// DocKinds は engine が読む Doc の種。schema があるかどうかで診られるかが決まる。
	DocKinds *[]string `json:"docKinds"`
}

// Rules は検査が使う規約。すべて JSON から来る。
type Rules struct {
	DocKinds []string
}

// LoadRules は規約データを読む。
//
// WhyNot: 読めないときに既定の一覧へ倒さないのは、規約ファイルを消しただけで
// 「診られない Doc の種は 1 つもありません」と嘘の緑を出す穴を作らないため。
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
	if f.DocKinds == nil || len(*f.DocKinds) == 0 {
		return nil, fmt.Errorf("規約ファイルに docKinds がありません (%s)", path)
	}
	return &Rules{DocKinds: *f.DocKinds}, nil
}
