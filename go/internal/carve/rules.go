package carve

// 閾値・既定値・色は bin/lint-rules/carve.json から読む。Go 側に写しを持たない。
//
// WhyNot: 既定値を Go に埋めないのは、無いときに黙って 0 で動き出すと
// 「表が読めなかった」と「そういう値だった」を見分けられなくなるため。
// 読めなければ理由を出して止まる。

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Profile は体型のつまみ。
type Profile struct {
	FeetShare   float64 `json:"feetShare"`
	HeadRatio   float64 `json:"headRatio"`
	HipRatio    float64 `json:"hipRatio"`
	CoreTrimPct int     `json:"coreTrimPct"`
	TubeMargin  int     `json:"tubeMargin"`
	ToneStep    int     `json:"toneStep"`
	Tool        string  `json:"tool"`
	Reach       int     `json:"reach"`
	LiftAt      float64 `json:"liftAt"`
	CrumbLimit  int     `json:"crumbLimit"`
}

// Rules は carve.json を読んだ物。
type Rules struct {
	Profile   Profile `json:"profile"`
	Alpha     int     `json:"alpha"`
	QuantStep int     `json:"quantizeStep"`
	Backdrop  struct {
		Coarse       int `json:"coarse"`
		LightMin     int `json:"lightMin"`
		LightSpread  int `json:"lightSpread"`
		EdgeTolerant int `json:"edgeTolerance"`
	} `json:"backdrop"`
	Spans struct {
		Step  int `json:"step"`
		Least int `json:"least"`
	} `json:"spans"`
	BoundsStep   int `json:"boundsStep"`
	SamplePoints int `json:"samplePoints"`
	DarkPatch    struct {
		MaxLevel int     `json:"maxLevel"`
		Share    float64 `json:"share"`
	} `json:"darkPatch"`
	LegendChars   string `json:"legendChars"`
	CarveDefaults struct {
		Size   string `json:"size"`
		Colors int    `json:"colors"`
	} `json:"carveDefaults"`
	AdoptDefaults struct {
		Size   string `json:"size"`
		Order  string `json:"order"`
		Swing  int    `json:"swing"`
		Colors int    `json:"colors"`
		Dip    int    `json:"dip"`
	} `json:"adoptDefaults"`
	Adopt struct {
		LegFloorShare  float64 `json:"legFloorShare"`
		LegNearShare   float64 `json:"legNearShare"`
		ShearNearShare float64 `json:"shearNearShare"`
		ShearLiftAt    float64 `json:"shearLiftAt"`
		BottomGap      int     `json:"bottomGap"`
		Scales         []int   `json:"scales"`
		Background     RGBA    `json:"background"`
	} `json:"adopt"`
	Render struct {
		SmallSide  int `json:"smallSide"`
		SmallScale int `json:"smallScale"`
		BigScale   int `json:"bigScale"`
	} `json:"render"`
	Gif struct {
		Delay  int `json:"delay"`
		Cycles []struct {
			Name   string   `json:"name"`
			Frames []string `json:"frames"`
		} `json:"cycles"`
	} `json:"gif"`
	Sheet struct {
		Background RGBA `json:"background"`
	} `json:"sheet"`

	GifCycles []GifCycle
	GifDelay  int
	SheetBack RGBA
}

// LoadRules は bin/lint-rules/carve.json を読む。
func LoadRules(root string) (*Rules, error) {
	path := filepath.Join(root, "bin", "lint-rules", "carve.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("規約が読めません: %v", err)
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, fmt.Errorf("規約が読めません (%s): %v", path, err)
	}
	for _, key := range []string{"profile", "alpha", "quantizeStep", "backdrop",
		"spans", "boundsStep", "samplePoints", "darkPatch", "legendChars",
		"carveDefaults", "adoptDefaults", "adopt", "render", "gif", "sheet"} {
		if _, ok := raw[key]; !ok {
			return nil, fmt.Errorf("規約に %s がありません (%s)", key, path)
		}
	}
	var profileKeys map[string]json.RawMessage
	if err := json.Unmarshal(raw["profile"], &profileKeys); err != nil {
		return nil, fmt.Errorf("規約の profile が読めません (%s): %v", path, err)
	}
	for _, key := range []string{"feetShare", "headRatio", "hipRatio", "coreTrimPct",
		"tubeMargin", "toneStep", "tool", "reach", "liftAt", "crumbLimit"} {
		if _, ok := profileKeys[key]; !ok {
			return nil, fmt.Errorf("規約の profile に %s がありません (%s)", key, path)
		}
	}
	rules := &Rules{}
	if err := json.Unmarshal(data, rules); err != nil {
		return nil, fmt.Errorf("規約が読めません (%s): %v", path, err)
	}
	if rules.LegendChars == "" || rules.SamplePoints <= 0 || len(rules.Adopt.Scales) == 0 {
		return nil, fmt.Errorf("規約の値が空です (%s)", path)
	}
	rules.GifDelay = rules.Gif.Delay
	rules.SheetBack = rules.Sheet.Background
	for _, c := range rules.Gif.Cycles {
		rules.GifCycles = append(rules.GifCycles, GifCycle{Name: c.Name, Frames: c.Frames})
	}
	return rules, nil
}
