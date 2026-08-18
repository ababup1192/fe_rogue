package f32

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// 正本は bin/lint-f32.py の EXEMPT。JSON がそこからずれていないかを機械で見る。
// WhyNot: 目視の約束にしないのは、除外を Python 側だけ直したときに Go 版だけが
// 古い判定のまま緑を出すため。

// pythonExempt は bin/lint-f32.py の EXEMPT = { ... } を読む。
// WhyNot: 正規表現 1 本にしないのは、値が複数行の文字列リテラルの連結で書かれていて
// 行ごとに切ると理由が途中で切れるため。
func pythonExempt(t *testing.T) map[string]string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(repoRoot(), "bin", "lint-f32.py"))
	if err != nil {
		t.Fatal(err)
	}
	src := string(data)
	head := strings.Index(src, "\nEXEMPT = {")
	if head < 0 {
		t.Fatal("bin/lint-f32.py に EXEMPT が無い")
	}
	body := src[head+len("\nEXEMPT = {"):]
	tail := strings.Index(body, "\n}")
	if tail < 0 {
		t.Fatal("bin/lint-f32.py の EXEMPT の閉じ括弧が見つからない")
	}
	body = body[:tail]

	out := map[string]string{}
	key, value := "", ""
	inValue := false
	for i := 0; i < len(body); {
		switch c := body[i]; {
		case c == '#':
			for i < len(body) && body[i] != '\n' {
				i++
			}
		case c == ':':
			inValue = true
			i++
		case c == ',':
			if key != "" {
				out[key] = value
			}
			key, value, inValue = "", "", false
			i++
		case c == '"':
			lit, next := pyString(t, body, i)
			if inValue {
				value += lit
			} else {
				key += lit
			}
			i = next
		default:
			i++
		}
	}
	if key != "" {
		out[key] = value
	}
	return out
}

// pyString は body[i] から始まる Python の文字列リテラルを読む。
func pyString(t *testing.T, body string, i int) (string, int) {
	t.Helper()
	var b strings.Builder
	i++ // 開きの "
	for i < len(body) {
		c := body[i]
		if c == '\\' && i+1 < len(body) {
			switch body[i+1] {
			case 'n':
				b.WriteByte('\n')
			case 't':
				b.WriteByte('\t')
			default:
				b.WriteByte(body[i+1])
			}
			i += 2
			continue
		}
		if c == '"' {
			return b.String(), i + 1
		}
		b.WriteByte(c)
		i++
	}
	t.Fatal("bin/lint-f32.py の文字列リテラルが閉じていない")
	return "", i
}

func TestRulesMatchPython(t *testing.T) {
	want := pythonExempt(t)
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	if len(rules.Exempt) != len(want) {
		t.Fatalf("除外の件数が %d (bin/lint-f32.py は %d)", len(rules.Exempt), len(want))
	}
	for key, reason := range want {
		got, ok := rules.Exempt[key]
		if !ok {
			t.Errorf("%s が bin/lint-rules/f32.json に無い", key)
			continue
		}
		if got != reason {
			t.Errorf("%s の理由がずれている\n JSON:   %s\n Python: %s", key, got, reason)
		}
	}
}

func TestLoadRulesWithoutFile(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーが返らない")
	}
}

func TestLoadRulesWithoutExemptKey(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"exempts": {}}`)
	if _, err := LoadRules(root); err == nil {
		t.Fatal("exempt が無いのにエラーが返らない")
	}
}

func TestLoadRulesWithBrokenJSON(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"exempt": `)
	if _, err := LoadRules(root); err == nil {
		t.Fatal("壊れた JSON でエラーが返らない")
	}
}

func TestLoadRulesWithoutReason(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"exempt": {"A.b": ""}}`)
	if _, err := LoadRules(root); err == nil {
		t.Fatal("理由が空なのにエラーが返らない")
	}
}

func TestRepoRulesAreValidJSON(t *testing.T) {
	data, err := os.ReadFile(filepath.Join(repoRoot(), RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	var any map[string]any
	if err := json.Unmarshal(data, &any); err != nil {
		t.Fatal(err)
	}
}

func writeRules(t *testing.T, root, body string) {
	t.Helper()
	path := filepath.Join(root, RulesPath)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}
