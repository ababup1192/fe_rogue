package genrules

// 規約データ (bin/lint-rules/gen-rules.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// RulesPath は規約データの置き場（リポジトリの根からの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "gen-rules.json")

// RuleSpec は 1 本のルール。out が出力名・src が元の doc・globs が効かせたいファイル。
type RuleSpec struct {
	Out   string   `json:"out"`
	Src   string   `json:"src"`
	Globs []string `json:"globs"`
}

type rulesFile struct {
	Banner  *string     `json:"banner"`
	Rules   *[]RuleSpec `json:"rules"`
	OutDirs *[]string   `json:"outDirs"`
}

// Rules は生成が使う規約。すべて JSON から来る。
type Rules struct {
	Banner  string
	Rules   []RuleSpec
	OutDirs []string
}

// LoadRules は規約データを読む。
// WhyNot: 読めないときに既定値へ倒さないのは、規約ファイルを消しただけで
// 中身の違う rules を黙って書き出す穴を作らないため。呼ぶ側は必ずエラーで止める。
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
	case f.Banner == nil:
		missing = "banner"
	case f.Rules == nil:
		missing = "rules"
	case f.OutDirs == nil:
		missing = "outDirs"
	}
	if missing != "" {
		return nil, fmt.Errorf("規約ファイルに %s がありません (%s)", missing, path)
	}
	for _, r := range *f.Rules {
		if r.Out == "" || r.Src == "" {
			return nil, fmt.Errorf("規約ファイルの rules に out か src が無い項目があります (%s)", path)
		}
	}
	return &Rules{Banner: *f.Banner, Rules: *f.Rules, OutDirs: *f.OutDirs}, nil
}
