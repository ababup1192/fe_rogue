package stageengine

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeRules(t *testing.T, root, body string) {
	t.Helper()
	dir := filepath.Join(root, "bin", "lint-rules")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "stage-engine.json"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
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

func TestLoadRulesWithoutFile(t *testing.T) {
	if _, err := LoadRules(t.TempDir()); err == nil {
		t.Fatal("規約ファイルが無いのにエラーになりません")
	}
}

func TestLoadRulesWithBrokenJSON(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, "{ this is not json")
	if _, err := LoadRules(root); err == nil {
		t.Fatal("壊れた JSON なのにエラーになりません")
	}
}

func TestLoadRulesWithEmptyItems(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"items": []}`)
	if _, err := LoadRules(root); err == nil {
		t.Fatal("items が空なのにエラーになりません")
	}
}

func TestLoadRulesWithUnknownFlagSource(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"items": [{"src": "@nope", "dest": "bin/nope"}]}`)
	if _, err := LoadRules(root); err == nil {
		t.Fatal("知らない @ 元なのにエラーになりません")
	}
}

// TestMissingItemStops は一覧に在る物がリポに無いとき、痩せたまま組み上げずに止まることを見る。
func TestMissingItemStops(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"items": [{"src": "docs/glossary.md", "dest": "docs/glossary.md"}]}`)
	var out, errOut strings.Builder
	code, err := Run(&out, &errOut, root, []string{"--out", filepath.Join(t.TempDir(), "bundle")})
	if err != nil {
		t.Fatal(err)
	}
	if code != 1 {
		t.Fatalf("終了コードが 1 ではありません: %d", code)
	}
	if !strings.Contains(errOut.String(), "docs/glossary.md が見つかりません") {
		t.Fatalf("欠けた物の名前が出ていません: %q", errOut.String())
	}
}

// TestOptionalItemIsSkipped は元を渡されていない任意の物が黙って飛ばされることを見る。
func TestOptionalItemIsSkipped(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"items": [{"src": "@maven-seed/cache", "dest": "lib/cache", "optional": true}]}`)
	out := filepath.Join(t.TempDir(), "bundle")
	var body, errBody strings.Builder
	// 照合 (check-refs) は偽リポに規約が無いので 2 で止まる。ここで見たいのはその手前。
	Run(&body, &errBody, root, []string{"--out", out})
	if _, err := os.Stat(filepath.Join(out, "lib", "cache")); !os.IsNotExist(err) {
		t.Fatal("元を渡していないのに lib/cache が出来ています")
	}
}

// TestWindowsSkipsBashOnly は --windows で bash 前提の物だけが外れることを見る。
func TestWindowsSkipsBashOnly(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"items": [
	  {"src": "bin/reference-check.sh", "dest": "bin/reference-check.sh", "skipOnWindows": true},
	  {"src": "docs/glossary.md", "dest": "docs/glossary.md"}
	]}`)
	writeFile(t, filepath.Join(root, "docs", "glossary.md"), "glossary\n")
	out := filepath.Join(t.TempDir(), "bundle")
	var body, errBody strings.Builder
	Run(&body, &errBody, root, []string{"--out", out, "--windows"})
	if _, err := os.Stat(filepath.Join(out, "docs", "glossary.md")); err != nil {
		t.Fatalf("Windows で外れない物が運ばれていません: %v", err)
	}
	if _, err := os.Stat(filepath.Join(out, "bin", "reference-check.sh")); !os.IsNotExist(err) {
		t.Fatal("bash 前提の物が Windows のバンドルに入っています")
	}
}

// TestPruneDirsAreNotCopied は運ばないフォルダ名 (lib / build / .devbox) が落ちることを見る。
func TestPruneDirsAreNotCopied(t *testing.T) {
	root := t.TempDir()
	writeRules(t, root, `{"items": [
	  {"src": "templates", "dest": "templates", "pruneDirs": ["lib", "build"]}
	]}`)
	writeFile(t, filepath.Join(root, "templates", "a", "Makefile"), "all:\n")
	writeFile(t, filepath.Join(root, "templates", "a", "build", "x.class"), "x")
	writeFile(t, filepath.Join(root, "templates", "a", "lib", "x.fpkg"), "x")
	out := filepath.Join(t.TempDir(), "bundle")
	var body, errBody strings.Builder
	Run(&body, &errBody, root, []string{"--out", out})
	if _, err := os.Stat(filepath.Join(out, "templates", "a", "Makefile")); err != nil {
		t.Fatalf("テンプレの中身が運ばれていません: %v", err)
	}
	for _, name := range []string{"build", "lib"} {
		if _, err := os.Stat(filepath.Join(out, "templates", "a", name)); !os.IsNotExist(err) {
			t.Fatalf("%s が運ばれています", name)
		}
	}
}

// TestUnknownArgStops は綴り違いの引数が黙って無視されないことを見る。
func TestUnknownArgStops(t *testing.T) {
	var out, errOut strings.Builder
	if _, err := Run(&out, &errOut, t.TempDir(), []string{"--outt", "x"}); err == nil {
		t.Fatal("知らない引数なのにエラーになりません")
	}
}
