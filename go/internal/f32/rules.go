package f32

// 規約データ (bin/lint-rules/f32.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// RulesPath は規約データの置き場（リポジトリの根からの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "f32.json")

type rulesFile struct {
	// Exempt は「残すと決めた Float32」。鍵は "モジュール名.宣言名"、値は残す理由 (1 行必須)。
	// WhyNot: 行番号でなくモジュールと名前で持つのは、上の行が増減しても鍵がずれないため。
	Exempt *map[string]string `json:"exempt"`
}

// Rules は検査が使う規約。すべて JSON から来る。
type Rules struct {
	Exempt map[string]string
}

// LoadRules は規約データを読む。
// WhyNot: 読めないときに空の除外一覧へ倒さないのは、規約ファイルを消しただけで
// 検査の意味が変わる穴を作らないため。呼ぶ側は必ずエラーで止める。
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
	if f.Exempt == nil {
		return nil, fmt.Errorf("規約ファイルに exempt がありません (%s)", path)
	}
	for key, reason := range *f.Exempt {
		if reason == "" {
			return nil, fmt.Errorf("規約ファイルの exempt %q に理由がありません (%s)", key, path)
		}
	}
	return &Rules{Exempt: *f.Exempt}, nil
}

// ParseExempt は `--exempt-json` で渡された除外一覧を読む（見本での差し替え用）。
func ParseExempt(text string) (map[string]string, error) {
	exempt := map[string]string{}
	if err := json.Unmarshal([]byte(text), &exempt); err != nil {
		return nil, fmt.Errorf("--exempt-json が JSON として壊れています: %v", err)
	}
	return exempt, nil
}
