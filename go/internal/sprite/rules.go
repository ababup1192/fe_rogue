package sprite

// 規約データ (bin/lint-rules/sprite.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// RulesPath は規約データの置き場（リポジトリの根からの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "sprite.json")

type rulesFile struct {
	Rules              []string `json:"rules"`
	TransparentChars   []string `json:"transparentChars"`
	ExcludedDirs       []string `json:"excludedDirs"`
	MaxColors          *int     `json:"maxColors"`
	MaxColorsBig       *int     `json:"maxColorsBig"`
	BigSide            *int     `json:"bigSide"`
	TextureFill        *float64 `json:"textureFill"`
	MinOrphanCells     *int     `json:"minOrphanCells"`
	MinConnectCells    *int     `json:"minConnectCells"`
	ConnectShown       *int     `json:"connectShown"`
	JaggyMinCount      *int     `json:"jaggyMinCount"`
	BandingMinRun      *int     `json:"bandingMinRun"`
	SilhouetteMinOcc   *float64 `json:"silhouetteMinOcc"`
	DeltaEMin          *float64 `json:"deltaEMin"`
	ExemptPattern      *string  `json:"exemptPattern"`
	ExemptParenPattern *string  `json:"exemptParenPattern"`
}

// Rules は検査が使う規約。すべて JSON から来る。
type Rules struct {
	RuleNames        []string
	TransparentChars map[rune]bool
	ExcludedDirs     map[string]bool
	MaxColors        int
	MaxColorsBig     int
	BigSide          int
	TextureFill      float64
	MinOrphanCells   int
	MinConnectCells  int
	ConnectShown     int
	JaggyMinCount    int
	BandingMinRun    int
	SilhouetteMinOcc float64
	DeltaEMin        float64

	exempt      *regexp.Regexp
	exemptParen *regexp.Regexp
}

// pyWhitespace は Unicode の空白すべてに当たる文字クラス。
//
// WhyNot: Go の \s をそのまま使えないのは、ASCII の 5 文字しか見ないため。
// 全角空白を挟んだ「対象外　(orphan)」を除外記法として読めなくなる。
const pyWhitespace = `[\t\n\v\f\r\x{1c}-\x{1f}\x{85}\p{Z}]`

func compilePyWS(pattern string) (*regexp.Regexp, error) {
	return regexp.Compile(strings.ReplaceAll(pattern, `\s`, pyWhitespace))
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
	case len(f.Rules) == 0:
		missing = "rules"
	case len(f.TransparentChars) == 0:
		missing = "transparentChars"
	case len(f.ExcludedDirs) == 0:
		missing = "excludedDirs"
	case f.MaxColors == nil:
		missing = "maxColors"
	case f.MaxColorsBig == nil:
		missing = "maxColorsBig"
	case f.BigSide == nil:
		missing = "bigSide"
	case f.TextureFill == nil:
		missing = "textureFill"
	case f.MinOrphanCells == nil:
		missing = "minOrphanCells"
	case f.MinConnectCells == nil:
		missing = "minConnectCells"
	case f.ConnectShown == nil:
		missing = "connectShown"
	case f.JaggyMinCount == nil:
		missing = "jaggyMinCount"
	case f.BandingMinRun == nil:
		missing = "bandingMinRun"
	case f.SilhouetteMinOcc == nil:
		missing = "silhouetteMinOcc"
	case f.DeltaEMin == nil:
		missing = "deltaEMin"
	case f.ExemptPattern == nil:
		missing = "exemptPattern"
	case f.ExemptParenPattern == nil:
		missing = "exemptParenPattern"
	}
	if missing != "" {
		return nil, fmt.Errorf("規約ファイルに %s がありません (%s)", missing, path)
	}
	exempt, err := compilePyWS(*f.ExemptPattern)
	if err != nil {
		return nil, fmt.Errorf("規約ファイルの exemptPattern が正規表現として壊れています (%s): %v", path, err)
	}
	exemptParen, err := compilePyWS(*f.ExemptParenPattern)
	if err != nil {
		return nil, fmt.Errorf("規約ファイルの exemptParenPattern が正規表現として壊れています (%s): %v", path, err)
	}

	transparent := map[rune]bool{}
	for _, s := range f.TransparentChars {
		for _, r := range s {
			transparent[r] = true
		}
	}
	excluded := map[string]bool{}
	for _, d := range f.ExcludedDirs {
		excluded[d] = true
	}
	return &Rules{
		RuleNames:        f.Rules,
		TransparentChars: transparent,
		ExcludedDirs:     excluded,
		MaxColors:        *f.MaxColors,
		MaxColorsBig:     *f.MaxColorsBig,
		BigSide:          *f.BigSide,
		TextureFill:      *f.TextureFill,
		MinOrphanCells:   *f.MinOrphanCells,
		MinConnectCells:  *f.MinConnectCells,
		ConnectShown:     *f.ConnectShown,
		JaggyMinCount:    *f.JaggyMinCount,
		BandingMinRun:    *f.BandingMinRun,
		SilhouetteMinOcc: *f.SilhouetteMinOcc,
		DeltaEMin:        *f.DeltaEMin,
		exempt:           exempt,
		exemptParen:      exemptParen,
	}, nil
}
