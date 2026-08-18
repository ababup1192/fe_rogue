package prunetools

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func repoRoot() string { return filepath.Join("..", "..", "..") }

// 一覧は manifest の copy に載っている .py の写し。写し漏れを機械で見張る。
// WhyNot: 逆向き (StaleTools ⊆ manifest) を見ないのは、.py を engine から消した後は
// manifest から消えて、それでも一覧には残っていてほしいため。
func TestStaleToolsCoverManifest(t *testing.T) {
	data, err := os.ReadFile(filepath.Join(repoRoot(), "agents-pack", "manifest.json"))
	if err != nil {
		t.Fatal(err)
	}
	var m struct {
		Copy []struct{ Src, Dst string } `json:"copy"`
	}
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatal(err)
	}
	have := map[string]bool{}
	for _, rel := range StaleTools {
		have[rel] = true
	}
	for _, e := range m.Copy {
		if strings.HasSuffix(e.Dst, ".py") && !have[e.Dst] {
			t.Errorf("manifest の %s が StaleTools に無い", e.Dst)
		}
	}
}

// engine にまだある道具は消さない (消す順番を間違えたゲームを作らないため)。
func TestKeepsToolsStillInEngine(t *testing.T) {
	// WhyNot: 本物の engine を根に使わないのは、一覧の道具が engine から全部
	// 消えた時点で「まだある」場合を作れなくなり、この見張りが空回りするため。
	root := t.TempDir()
	writeFile(t, filepath.Join(root, ".claude", "hooks", "after-flix-edit.py"), "x")
	game := t.TempDir()
	writeFile(t, filepath.Join(game, ".claude", "hooks", "after-flix-edit.py"), "x")
	var out, errOut strings.Builder
	if code, err := Run(&out, &errOut, root, []string{"--game", game}); err != nil || code != 0 {
		t.Fatalf("code=%d err=%v", code, err)
	}
	if !isFile(filepath.Join(game, ".claude", "hooks", "after-flix-edit.py")) {
		t.Error("engine にまだある道具を消してしまった")
	}
	if !strings.Contains(out.String(), "消す物はありません") {
		t.Errorf("出力が想定と違う: %s", out.String())
	}
}

// engine に無い道具だけを消す。素振りでは消さない。
func TestPrunesOnlyToolsGoneFromEngine(t *testing.T) {
	root := t.TempDir()
	game := t.TempDir()
	writeFile(t, filepath.Join(game, "bin", "status.py"), "x")
	writeFile(t, filepath.Join(game, "bin", "my-tool.sh"), "x")

	var dry, dryErr strings.Builder
	if code, err := Run(&dry, &dryErr, root, []string{"--game", game, "--dry-run"}); err != nil || code != 0 {
		t.Fatalf("code=%d err=%v", code, err)
	}
	if !isFile(filepath.Join(game, "bin", "status.py")) {
		t.Error("素振りなのに消した")
	}
	if !strings.Contains(dry.String(), "消す: bin/status.py") {
		t.Errorf("素振りが消す物を出していない: %s", dry.String())
	}

	var out, errOut strings.Builder
	if code, err := Run(&out, &errOut, root, []string{"--game", game}); err != nil || code != 0 {
		t.Fatalf("code=%d err=%v", code, err)
	}
	if isFile(filepath.Join(game, "bin", "status.py")) {
		t.Error("engine に無い道具が残っている")
	}
	if !isFile(filepath.Join(game, "bin", "my-tool.sh")) {
		t.Error("一覧に無いゲームの道具を消してしまった")
	}
}

func TestMissingGameAborts(t *testing.T) {
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, repoRoot(), []string{"--game", filepath.Join(t.TempDir(), "nope")})
	if err != nil || code != 1 {
		t.Fatalf("code=%d err=%v", code, err)
	}
	if !strings.Contains(errOut.String(), "見つかりません") {
		t.Errorf("理由が出ていない: %s", errOut.String())
	}
}

func TestNoGameAborts(t *testing.T) {
	var out, errOut strings.Builder
	if code, _ := Run(&out, &errOut, repoRoot(), nil); code != 1 {
		t.Fatalf("code=%d", code)
	}
}

func TestUnknownArgAborts(t *testing.T) {
	var out, errOut strings.Builder
	if code, _ := Run(&out, &errOut, repoRoot(), []string{"--bogus"}); code != 2 {
		t.Fatalf("code=%d", code)
	}
}

func writeFile(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}
