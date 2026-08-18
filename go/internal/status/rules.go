package status

// 規約データ (bin/lint-rules/status.json) の読み込み。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// RulesPath は規約データの置き場（リポジトリの根からの相対）。
var RulesPath = filepath.Join("bin", "lint-rules", "status.json")

type rulesFile struct {
	MaxLines           *int     `json:"maxLines"`
	BuildWarnEntries   *int     `json:"buildWarnEntries"`
	Sections           []string `json:"sections"`
	AgeJustNowSeconds  *float64 `json:"ageJustNowSeconds"`
	AgeMinuteSeconds   *float64 `json:"ageMinuteSeconds"`
	AgeHourSeconds     *float64 `json:"ageHourSeconds"`
	GitLogCount        *int     `json:"gitLogCount"`
	GreensShown        *int     `json:"greensShown"`
	ReferenceBadShown  *int     `json:"referenceBadShown"`
	BudgetDetailLines  *int     `json:"budgetDetailLines"`
	TicketsShown       *int     `json:"ticketsShown"`
	TicketSummaryWidth *int     `json:"ticketSummaryWidth"`
	NotesShown         *int     `json:"notesShown"`
	NotesWidth         *int     `json:"notesWidth"`
	TestLogsDir        *string  `json:"testLogsDir"`
	BuildGlobs         []string `json:"buildGlobs"`
	BuildDirs          []string `json:"buildDirs"`
}

// Rules は 1 画面の組み立てが使う規約。すべて JSON から来る。
//
// WhyNot: 節の並びを map にしないのは、Python の dict が書いた順を保つのに対し
// Go の map は並びを持たないため。並びが意味を持つ物は配列で受ける。
type Rules struct {
	MaxLines           int
	BuildWarnEntries   int
	Sections           []string
	AgeJustNowSeconds  float64
	AgeMinuteSeconds   float64
	AgeHourSeconds     float64
	GitLogCount        int
	GreensShown        int
	ReferenceBadShown  int
	BudgetDetailLines  int
	TicketsShown       int
	TicketSummaryWidth int
	NotesShown         int
	NotesWidth         int
	TestLogsDir        string
	BuildGlobs         []string
	BuildDirs          []string
}

// LoadRules は規約データを読む。
// WhyNot: 読めないときに既定値へ倒さないのは、規約ファイルを消しただけで
// 画面が黙って別物になる穴を作らないため。呼ぶ側は必ずエラーで止める。
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
	case f.MaxLines == nil:
		missing = "maxLines"
	case f.BuildWarnEntries == nil:
		missing = "buildWarnEntries"
	case f.Sections == nil:
		missing = "sections"
	case f.AgeJustNowSeconds == nil:
		missing = "ageJustNowSeconds"
	case f.AgeMinuteSeconds == nil:
		missing = "ageMinuteSeconds"
	case f.AgeHourSeconds == nil:
		missing = "ageHourSeconds"
	case f.GitLogCount == nil:
		missing = "gitLogCount"
	case f.GreensShown == nil:
		missing = "greensShown"
	case f.ReferenceBadShown == nil:
		missing = "referenceBadShown"
	case f.BudgetDetailLines == nil:
		missing = "budgetDetailLines"
	case f.TicketsShown == nil:
		missing = "ticketsShown"
	case f.TicketSummaryWidth == nil:
		missing = "ticketSummaryWidth"
	case f.NotesShown == nil:
		missing = "notesShown"
	case f.NotesWidth == nil:
		missing = "notesWidth"
	case f.TestLogsDir == nil:
		missing = "testLogsDir"
	case f.BuildGlobs == nil:
		missing = "buildGlobs"
	case f.BuildDirs == nil:
		missing = "buildDirs"
	}
	if missing != "" {
		return nil, fmt.Errorf("規約ファイルに %s がありません (%s)", missing, path)
	}
	return &Rules{
		MaxLines:           *f.MaxLines,
		BuildWarnEntries:   *f.BuildWarnEntries,
		Sections:           f.Sections,
		AgeJustNowSeconds:  *f.AgeJustNowSeconds,
		AgeMinuteSeconds:   *f.AgeMinuteSeconds,
		AgeHourSeconds:     *f.AgeHourSeconds,
		GitLogCount:        *f.GitLogCount,
		GreensShown:        *f.GreensShown,
		ReferenceBadShown:  *f.ReferenceBadShown,
		BudgetDetailLines:  *f.BudgetDetailLines,
		TicketsShown:       *f.TicketsShown,
		TicketSummaryWidth: *f.TicketSummaryWidth,
		NotesShown:         *f.NotesShown,
		NotesWidth:         *f.NotesWidth,
		TestLogsDir:        *f.TestLogsDir,
		BuildGlobs:         f.BuildGlobs,
		BuildDirs:          f.BuildDirs,
	}, nil
}
