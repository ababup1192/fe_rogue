package stageengine

// What: Studio の self-update が「入れ替えても持ち越す物」を導く印（owner）が、
// 実データで狙いどおりの 3 つだけに付いていること。

import (
	"path/filepath"
	"runtime"
	"sort"
	"testing"
)

// repoRoot はテストから見たリポジトリのルート (go/internal/stageengine の 3 つ上)。
func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("テストの置き場が分かりません")
	}
	return filepath.Join(filepath.Dir(file), "..", "..", "..")
}

// engine の self-update は engine フォルダを丸ごと入れ替える。ここに印が無い物は
// 新しい engine で上書きされるので、Studio 側が中身を決める物に印が落ちると、
// 更新後の Studio でゲームのビルドが通らなくなる。
func TestOnlyStudioOwnedItemsAreCarriedOver(t *testing.T) {
	rules, err := LoadRules(repoRoot(t))
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, it := range rules.Items {
		if it.OwnedByStudio() {
			got = append(got, it.Dest)
		}
	}
	sort.Strings(got)
	want := []string{"bin/flix", "lib/cache", "lib/external"}
	if len(got) != len(want) {
		t.Fatalf("持ち越す物=%v (欲しい %v)", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("持ち越す物=%v (欲しい %v)", got, want)
			break
		}
	}
}

// bin/flix.jar は engine が中身を決める。ラッパと名前が似ているので取り違えやすい。
func TestFlixJarIsOverwrittenNotCarriedOver(t *testing.T) {
	rules, err := LoadRules(repoRoot(t))
	if err != nil {
		t.Fatal(err)
	}
	for _, it := range rules.Items {
		if it.Dest == "bin/flix.jar" && it.OwnedByStudio() {
			t.Error("bin/flix.jar を持ち越しています（古いコンパイラのまま残ります）")
		}
	}
}
