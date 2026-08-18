package style

// 規約データ (bin/lint-rules/style.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// RulesPath は規約データの置き場（リポジトリの根からの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "style.json")

// HandLimits は画素で描く 2 本（coarse / fine）のしきい値。
type HandLimits struct {
	AaWarn     float64 `json:"aaWarn"`
	AaBad      float64 `json:"aaBad"`
	GridWarn   float64 `json:"gridWarn"`
	GridBad    float64 `json:"gridBad"`
	CoverWarn  int     `json:"coverWarn"`
	CoverBad   int     `json:"coverBad"`
	ColorsWarn int     `json:"colorsWarn"`
	ColorsBad  int     `json:"colorsBad"`
}

// SmoothLimits はなめらかな絵のしきい値（注意だけを出す）。
type SmoothLimits struct {
	AaMin     float64 `json:"aaMin"`
	GridMax   float64 `json:"gridMax"`
	ColorsMin int     `json:"colorsMin"`
}

// HandGuess はファイル名から描き手を当てるための語。
type HandGuess struct {
	Hand  string   `json:"hand"`
	Words []string `json:"words"`
}

type rulesFile struct {
	SoftStep       *int                   `json:"softStep"`
	StepEdges      []int                  `json:"stepEdges"`
	StepLabels     []string               `json:"stepLabels"`
	MaxUnit        *int                   `json:"maxUnit"`
	GridFound      *float64               `json:"gridFound"`
	EllipseIoU     *float64               `json:"ellipseIou"`
	RegionMin      *float64               `json:"regionMin"`
	RegionCap      *int                   `json:"regionCap"`
	RegionQuant    *int                   `json:"regionQuant"`
	BlockNames     [][]string             `json:"blockNames"`
	Hands          map[string]*HandLimits `json:"hands"`
	Smooth         *SmoothLimits          `json:"smooth"`
	EllipseWarn    *float64               `json:"ellipseWarn"`
	SameAa         *float64               `json:"sameAa"`
	SameColorRatio *float64               `json:"sameColorRatio"`
	HandHints      map[string]string      `json:"handHints"`
	HandGuess      []HandGuess            `json:"handGuess"`
	HandNames      []string               `json:"handNames"`
}

// Rules は検査が使う規約。すべて JSON から来る。
type Rules struct {
	SoftStep       int
	StepEdges      [3]int
	StepLabels     [4]string
	MaxUnit        int
	GridFound      float64
	EllipseIoU     float64
	RegionMin      float64
	RegionCap      int
	RegionQuant    int
	BlockNames     [3][3]string
	Hands          map[string]*HandLimits
	Smooth         SmoothLimits
	EllipseWarn    float64
	SameAa         float64
	SameColorRatio float64
	HandHints      map[string]string
	HandGuess      []HandGuess
	HandNames      []string
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
	case f.SoftStep == nil:
		missing = "softStep"
	case len(f.StepEdges) != 3:
		missing = "stepEdges"
	case len(f.StepLabels) != 4:
		missing = "stepLabels"
	case f.MaxUnit == nil:
		missing = "maxUnit"
	case f.GridFound == nil:
		missing = "gridFound"
	case f.EllipseIoU == nil:
		missing = "ellipseIou"
	case f.RegionMin == nil:
		missing = "regionMin"
	case f.RegionCap == nil:
		missing = "regionCap"
	case f.RegionQuant == nil:
		missing = "regionQuant"
	case len(f.BlockNames) != 3:
		missing = "blockNames"
	case f.Hands["coarse"] == nil || f.Hands["fine"] == nil:
		missing = "hands"
	case f.Smooth == nil:
		missing = "smooth"
	case f.EllipseWarn == nil:
		missing = "ellipseWarn"
	case f.SameAa == nil:
		missing = "sameAa"
	case f.SameColorRatio == nil:
		missing = "sameColorRatio"
	case len(f.HandHints) == 0:
		missing = "handHints"
	case len(f.HandGuess) == 0:
		missing = "handGuess"
	case len(f.HandNames) == 0:
		missing = "handNames"
	}
	if missing != "" {
		return nil, fmt.Errorf("規約ファイルに %s がありません (%s)", missing, path)
	}
	r := &Rules{
		SoftStep:       *f.SoftStep,
		MaxUnit:        *f.MaxUnit,
		GridFound:      *f.GridFound,
		EllipseIoU:     *f.EllipseIoU,
		RegionMin:      *f.RegionMin,
		RegionCap:      *f.RegionCap,
		RegionQuant:    *f.RegionQuant,
		Hands:          f.Hands,
		Smooth:         *f.Smooth,
		EllipseWarn:    *f.EllipseWarn,
		SameAa:         *f.SameAa,
		SameColorRatio: *f.SameColorRatio,
		HandHints:      f.HandHints,
		HandGuess:      f.HandGuess,
		HandNames:      f.HandNames,
	}
	copy(r.StepEdges[:], f.StepEdges)
	copy(r.StepLabels[:], f.StepLabels)
	for y, row := range f.BlockNames {
		if len(row) != 3 {
			return nil, fmt.Errorf("規約ファイルの blockNames は 3x3 で書いてください (%s)", path)
		}
		copy(r.BlockNames[y][:], row)
	}
	return r, nil
}

// isHandName は --hand に渡してよい名前か。
func (r *Rules) isHandName(hand string) bool {
	for _, n := range r.HandNames {
		if n == hand {
			return true
		}
	}
	return false
}
