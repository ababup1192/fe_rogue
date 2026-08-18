package anim

// 規約データ (bin/lint-rules/anim.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// RulesPath は規約データの置き場（リポジトリの根からの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "anim.json")

type rulesFile struct {
	MaxPopShare      *float64          `json:"maxPopShare"`
	MaxAreaDrift     *float64          `json:"maxAreaDrift"`
	MaxBob           *int              `json:"maxBob"`
	MinSideRatio     *float64          `json:"minSideRatio"`
	MaxSideRatio     *float64          `json:"maxSideRatio"`
	MinBackIoU       *float64          `json:"minBackIou"`
	FootTolerance    *int              `json:"footTolerance"`
	ChangeShareSlack *int              `json:"changeShareSlack"`
	Transparent      []string          `json:"transparent"`
	Rules            []string          `json:"rules"`
	Directions       map[string]string `json:"directions"`
	GameRoots        []string          `json:"gameRoots"`
	ExcludedDirs     []string          `json:"excludedDirs"`
}

// Rules は検査が使う規約。すべて JSON から来る。
type Rules struct {
	MaxPopShare      float64
	MaxAreaDrift     float64
	MaxBob           int
	MinSideRatio     float64
	MaxSideRatio     float64
	MinBackIoU       float64
	FootTolerance    int
	ChangeShareSlack int
	Transparent      map[rune]bool
	Names            []string
	Directions       map[string]string
	GameRoots        []string
	ExcludedDirs     map[string]bool
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
	case f.MaxPopShare == nil:
		missing = "maxPopShare"
	case f.MaxAreaDrift == nil:
		missing = "maxAreaDrift"
	case f.MaxBob == nil:
		missing = "maxBob"
	case f.MinSideRatio == nil:
		missing = "minSideRatio"
	case f.MaxSideRatio == nil:
		missing = "maxSideRatio"
	case f.MinBackIoU == nil:
		missing = "minBackIou"
	case f.FootTolerance == nil:
		missing = "footTolerance"
	case f.ChangeShareSlack == nil:
		missing = "changeShareSlack"
	case len(f.Transparent) == 0:
		missing = "transparent"
	case len(f.Rules) == 0:
		missing = "rules"
	case len(f.Directions) == 0:
		missing = "directions"
	case len(f.GameRoots) == 0:
		missing = "gameRoots"
	case len(f.ExcludedDirs) == 0:
		missing = "excludedDirs"
	}
	if missing != "" {
		return nil, fmt.Errorf("規約ファイルに %s がありません (%s)", missing, path)
	}
	transparent := map[rune]bool{}
	for _, s := range f.Transparent {
		for _, r := range s {
			transparent[r] = true
		}
	}
	excluded := map[string]bool{}
	for _, d := range f.ExcludedDirs {
		excluded[d] = true
	}
	return &Rules{
		MaxPopShare:      *f.MaxPopShare,
		MaxAreaDrift:     *f.MaxAreaDrift,
		MaxBob:           *f.MaxBob,
		MinSideRatio:     *f.MinSideRatio,
		MaxSideRatio:     *f.MaxSideRatio,
		MinBackIoU:       *f.MinBackIoU,
		FootTolerance:    *f.FootTolerance,
		ChangeShareSlack: *f.ChangeShareSlack,
		Transparent:      transparent,
		Names:            f.Rules,
		Directions:       f.Directions,
		GameRoots:        f.GameRoots,
		ExcludedDirs:     excluded,
	}, nil
}
