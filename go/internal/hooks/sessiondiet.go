package hooks

// hook-session-diet — 文脈が太ったら「NOTES.md に 3 行残して /clear」を促す。
//
// 毎ツール後に走るので軽さ最優先。会話ログの全解析はせず、末尾だけ読んで
// 最後の usage 行から文脈トークン数を概算する。

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// RunSessionDiet は文脈の太りを測り、段が上がっていれば Claude へ 1 行注入する。
func RunSessionDiet(errOut io.Writer, root string, in io.Reader) int {
	payload, ok := ReadPayload(in)
	if !ok {
		return 0
	}
	r, err := LoadRules(root)
	if err != nil {
		fmt.Fprintf(errOut, "# hook-session-diet: %v\n", err)
		return 2
	}
	transcript, session := payload.TranscriptPath(), payload.SessionID()
	if transcript == "" || session == "" || !isFile(transcript) {
		return 0
	}
	tokens, ok := readContextTokens(r, transcript)
	if !ok || tokens < *r.SessionDiet.ThresholdTokens {
		return 0
	}
	// レベル = しきい値を何段超えたか。
	// WhyNot: 同じ段で 2 度言わないのは、注入そのものが文脈を太らせて逆効果になるため。
	level := (tokens-*r.SessionDiet.ThresholdTokens)/(*r.SessionDiet.StepTokens) + 1
	marker := markerPath(r, session)
	if notifiedLevel(marker) >= level {
		return 0
	}
	_ = os.WriteFile(marker, []byte(strconv.Itoa(level)), 0o644)

	fmt.Fprintf(errOut,
		"# session-diet: 文脈が約%.0f万トークンまで太っています。"+
			"1ターンの費用が上がり続けるので、キリの良い所で NOTES.md 先頭に"+
			"「次やること」3行を書き、ユーザーに /clear を提案してください。\n",
		float64(tokens)/10000.0)
	return 2
}

// readContextTokens は会話ログの末尾から今の文脈トークン数を概算する。
func readContextTokens(r *Rules, path string) (int, bool) {
	f, err := os.Open(path)
	if err != nil {
		return 0, false
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return 0, false
	}
	tail := *r.SessionDiet.TailBytes
	if info.Size() > tail {
		if _, err := f.Seek(info.Size()-tail, io.SeekStart); err != nil {
			return 0, false
		}
	}
	// WhyNot: 途中から読むので先頭行が途切れうる。解釈に失敗した行は捨てる。
	data, err := io.ReadAll(f)
	if err != nil {
		return 0, false
	}
	var last map[string]any
	for _, line := range strings.Split(string(data), "\n") {
		// WhyNot: 全行を JSON として解釈しないのは、毎ツール後に走る道具で重いため。
		if !strings.Contains(line, *r.SessionDiet.UsageMark) {
			continue
		}
		var record map[string]any
		if err := json.Unmarshal([]byte(line), &record); err != nil {
			continue
		}
		message, ok := record["message"].(map[string]any)
		if !ok {
			continue
		}
		usage, ok := message["usage"].(map[string]any)
		if !ok {
			continue
		}
		if _, has := usage[*r.SessionDiet.UsageMark]; has {
			last = usage
		}
	}
	if last == nil {
		return 0, false
	}
	// WhyNot: cache_read だけで足さないのは、初回ターンが cache_creation 側に
	// 大きく積まれ、太っているのに小さく見えるため。
	return num(last["cache_read_input_tokens"]) +
		num(last["cache_creation_input_tokens"]) +
		num(last["input_tokens"]), true
}

func num(v any) int {
	f, ok := v.(float64)
	if !ok {
		return 0
	}
	return int(f)
}

// markerPath は「この段はもう言った」の印の置き場。
// WhyNot: セッション ID をそのままファイル名にしないのは、変な文字が混ざる余地があるため。
func markerPath(r *Rules, session string) string {
	var safe strings.Builder
	for _, c := range session {
		if c == '-' || ('0' <= c && c <= '9') || ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') {
			safe.WriteRune(c)
		}
	}
	return filepath.Join(os.TempDir(), *r.SessionDiet.MarkerPrefix+safe.String())
}

func notifiedLevel(path string) int {
	raw, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		return 0
	}
	return n
}
