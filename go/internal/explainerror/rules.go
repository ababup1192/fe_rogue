package explainerror

// 規約データ (bin/lint-rules/explain-error.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
)

// RulesPath は規約データの置き場（リポジトリの根からの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "explain-error.json")

// Prescription はエラー文中のキーと、それに添える平易な 1 行。
type Prescription struct {
	Key string `json:"key"`
	Tip string `json:"tip"`
}

type rulesFile struct {
	Prescriptions  []Prescription `json:"prescriptions"`
	TipFormat      *string        `json:"tipFormat"`
	ErrorCountMark *string        `json:"errorCountMark"`
	HeadPattern    *string        `json:"headPattern"`
	LinenoPattern  *string        `json:"linenoPattern"`
	AnsiPattern    *string        `json:"ansiPattern"`
	HeadLookahead  *int           `json:"headLookahead"`
}

// Rules は要約が使う規約。すべて JSON から来る。
type Rules struct {
	Prescriptions  []Prescription
	TipFormat      string
	ErrorCountMark string
	HeadLookahead  int
	Head           *regexp.Regexp
	Lineno         *regexp.Regexp
	Ansi           *regexp.Regexp
}

// LoadRules は規約データを読む。
// WhyNot: 読めないときに既定値へ倒さないのは、規約ファイルを消しただけで
// 処方箋の表が空のまま黙って動き、落とし穴の案内が消えるため。
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
	case len(f.Prescriptions) == 0:
		missing = "prescriptions"
	case f.TipFormat == nil:
		missing = "tipFormat"
	case f.ErrorCountMark == nil:
		missing = "errorCountMark"
	case f.HeadPattern == nil:
		missing = "headPattern"
	case f.LinenoPattern == nil:
		missing = "linenoPattern"
	case f.AnsiPattern == nil:
		missing = "ansiPattern"
	case f.HeadLookahead == nil:
		missing = "headLookahead"
	}
	if missing != "" {
		return nil, fmt.Errorf("規約ファイルに %s がありません (%s)", missing, path)
	}
	for i, p := range f.Prescriptions {
		if p.Key == "" || p.Tip == "" {
			return nil, fmt.Errorf("prescriptions[%d] に key か tip がありません (%s)", i, path)
		}
	}
	r := &Rules{
		Prescriptions:  f.Prescriptions,
		TipFormat:      *f.TipFormat,
		ErrorCountMark: *f.ErrorCountMark,
		HeadLookahead:  *f.HeadLookahead,
	}
	for _, spec := range []struct {
		name string
		src  string
		dst  **regexp.Regexp
	}{
		{"headPattern", *f.HeadPattern, &r.Head},
		{"linenoPattern", *f.LinenoPattern, &r.Lineno},
		{"ansiPattern", *f.AnsiPattern, &r.Ansi},
	} {
		re, err := regexp.Compile(spec.src)
		if err != nil {
			return nil, fmt.Errorf("規約ファイルの %s が正規表現として壊れています (%s): %v",
				spec.name, path, err)
		}
		*spec.dst = re
	}
	return r, nil
}
