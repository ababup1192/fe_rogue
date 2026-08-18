package main

// 外部依存ゼロを機械で守る。
// WhyNot: 目視の約束にしないのは、依存は 1 行の go get で静かに入るため。

import (
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestGoModHasNoRequire(t *testing.T) {
	data, err := os.ReadFile("go.mod")
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range strings.Split(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "require") {
			t.Errorf("go.mod に require がある: %s", trimmed)
		}
	}
}

func TestGoSumIsEmpty(t *testing.T) {
	info, err := os.Stat("go.sum")
	if os.IsNotExist(err) {
		return
	}
	if err != nil {
		t.Fatal(err)
	}
	if info.Size() != 0 {
		t.Errorf("go.sum が %d バイト — 外部依存が入っている", info.Size())
	}
}

var stdlibPath = regexp.MustCompile(`^[a-z0-9_/]+$`)

const modulePath = "github.com/ababup1192/flix_game_engine/go"

func TestAllDepsAreStdlib(t *testing.T) {
	out, err := exec.Command("go", "list", "-deps", "./...").Output()
	if err != nil {
		t.Skipf("go list が動かない環境: %v", err)
	}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		p := strings.TrimSpace(line)
		if p == "" || p == modulePath || strings.HasPrefix(p, modulePath+"/") {
			continue
		}
		// 標準ライブラリのパスはドメインを持たない (ドットを含まない先頭要素)。
		head := strings.SplitN(p, "/", 2)[0]
		if strings.Contains(head, ".") {
			t.Errorf("標準ライブラリでない依存: %s", p)
		}
	}
}

func TestNoHardcodedPathSeparator(t *testing.T) {
	// パス組み立てはすべて filepath.Join を通す。
	bad := regexp.MustCompile(`filepath\.Join\([^)]*\\\\`)
	err := filepath.WalkDir(".", func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(d.Name(), ".go") {
			return err
		}
		data, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		if bad.Match(data) {
			t.Errorf("%s: パス区切りを直書きしている", p)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}
