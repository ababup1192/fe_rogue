package apireleased

// 規約データ (bin/lint-rules/check-api-released.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// RulesPath は規約データの置き場（リポジトリのルートからの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "check-api-released.json")

type rulesFile struct {
	// Packages は fpkg として配るパッケージ。配下の src/ を見る。
	Packages *[]string `json:"packages"`
}

// Rules は検査が使う規約。すべて JSON から来る。
type Rules struct {
	Packages []string
}

// LoadRules は規約データを読む。
// WhyNot: 読めないときに既定のパッケージ一覧へ倒さないのは、規約ファイルを消しただけで
// 「見に行く先が減って全部緑」になる穴を作らないため。
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
	if f.Packages == nil || len(*f.Packages) == 0 {
		return nil, fmt.Errorf("規約ファイルに packages がありません (%s)", path)
	}
	return &Rules{Packages: *f.Packages}, nil
}
