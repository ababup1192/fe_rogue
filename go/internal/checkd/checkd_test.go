package checkd

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/ababup1192/flix_game_engine/go/internal/hooks"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	return root
}

func loadRules(t *testing.T) *hooks.Rules {
	t.Helper()
	r, err := hooks.LoadRules(repoRoot(t))
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestExitCodeOfCheckIsGreenWithoutErrorHeading(t *testing.T) {
	if got := exitCodeOf("check", "Hello.\n"); got != 0 {
		t.Errorf("エラー見出しの無い check は 0 のはず: %d", got)
	}
}

func TestExitCodeOfCheckReadsErrorHeading(t *testing.T) {
	text := "-- Resolution Error [E2136] ---- src/World.flix\n\n>> Undefined name.\n"
	if got := exitCodeOf("check", text); got != 1 {
		t.Errorf("エラー見出しがあれば 1 のはず: %d", got)
	}
}

func TestExitCodeOfTestReadsSummary(t *testing.T) {
	if got := exitCodeOf("test", "Passed: 12, Failed: 0.\n"); got != 0 {
		t.Errorf("全部通ったテストは 0 のはず: %d", got)
	}
}

func TestExitCodeOfTestFailsWhenSomeFailed(t *testing.T) {
	if got := exitCodeOf("test", "Passed: 11, Failed: 1.\n"); got != 1 {
		t.Errorf("失敗のあるテストは 1 のはず: %d", got)
	}
}

func TestExitCodeOfTestIsUnknownWithoutSummary(t *testing.T) {
	if got := exitCodeOf("test", "途中で切れた出力\n"); got >= 0 {
		t.Errorf("まとめ行が無ければ負 (素の CLI へ) のはず: %d", got)
	}
}

func TestScrubDropsPromptAndSentinel(t *testing.T) {
	raw := []byte("flix> Hello.\nflix> zzz7 は番兵\n")
	if got := scrub(raw, "zzz7"); got != "Hello.\n" {
		t.Errorf("プロンプトと番兵の行が残っています: %q", got)
	}
}

func TestScrubDropsProgressDots(t *testing.T) {
	if got := scrub([]byte("=>....\nHello.\n"), "zzz1"); got != "Hello.\n" {
		t.Errorf("進捗ドットが残っています: %q", got)
	}
}

func TestScrubKeepsLastPaintOfOverwrittenLine(t *testing.T) {
	if got := scrub([]byte("古い\r新しい\n"), "zzz1"); got != "新しい\n" {
		t.Errorf("行頭に戻って上書きされた字が残っています: %q", got)
	}
}

func TestScrubDropsAnsiColors(t *testing.T) {
	if got := scrub([]byte("\x1b[31mHello.\x1b[0m\n"), "zzz1"); got != "Hello.\n" {
		t.Errorf("端末の飾りが残っています: %q", got)
	}
}

func TestRSSLimitHonorsEnv(t *testing.T) {
	r := loadRules(t)
	t.Setenv(*r.Checkd.Daemon.RSSLimit.EnvVar, "5000")
	if got := rssLimitMB(r); got != 5000 {
		t.Errorf("環境変数の上書きが効いていません: %d", got)
	}
}

// TestHeapCapFitsUnderRSSLimit は repl の蓋が使い捨ての線の内側にあることを見る。
// WhyNot: 蓋の値そのものを pin しないのは、機械の大きさで動くため。守りたいのは
// 「蓋 < 線」という関係の方（破れると repl が毎回捨てられ、常駐が 1 度も効かない）。
func TestHeapCapFitsUnderRSSLimit(t *testing.T) {
	r := loadRules(t)
	t.Setenv(*r.Checkd.Daemon.RSSLimit.EnvVar, "2000")
	if heapCapMB(r) >= rssLimitMB(r) {
		t.Errorf("蓋 %dMB が線 %dMB の内側にありません", heapCapMB(r), rssLimitMB(r))
	}
}

// TestHeapCapNeverBelowMin は小さい機械でも repl が動く広さを残すことを見る。
func TestHeapCapNeverBelowMin(t *testing.T) {
	r := loadRules(t)
	t.Setenv(*r.Checkd.Daemon.RSSLimit.EnvVar, "1")
	if got := heapCapMB(r); got != *r.Checkd.Daemon.HeapMinMB {
		t.Errorf("下限を割っています: %d", got)
	}
}

// TestOutOfMemoryFallsBackToPlainCLI は蓋が足りなかったときに偽の赤を出さないことを見る。
func TestOutOfMemoryFallsBackToPlainCLI(t *testing.T) {
	txt := "java.lang.OutOfMemoryError: Java heap space\n"
	if got := exitCodeOf("check", txt); got >= 0 {
		t.Errorf("素の CLI へ投げ直すはずが %d を返しました", got)
	}
}

func TestRSSLimitNeverBelowFloor(t *testing.T) {
	r := loadRules(t)
	t.Setenv(*r.Checkd.Daemon.RSSLimit.EnvVar, "1")
	viable := *r.Checkd.Daemon.HeapMinMB + *r.Checkd.Daemon.HeapHeadroomMB
	if got := rssLimitMB(r); got < *r.Checkd.Daemon.RSSLimit.FloorMB || got < viable {
		t.Errorf("下限を割っています: %d (floorMB %d / heapMinMB + headroom %d)",
			got, *r.Checkd.Daemon.RSSLimit.FloorMB, viable)
	}
}

// TestDaemonViableRejectsOversizedBudget は repl 1 本の予算すら収まらない機械で
// 常駐を見送ること (素の CLI へ落ちること) を見る。
func TestDaemonViableRejectsOversizedBudget(t *testing.T) {
	r := loadRules(t)
	big := 1 << 30
	r.Checkd.Daemon.HeapMinMB = &big
	if hooks.DaemonViable(r) {
		t.Error("どんな機械にも収まらない予算なのに常駐しようとしています")
	}
	t.Setenv(*r.Checkd.Daemon.RSSLimit.EnvVar, "4096")
	if !hooks.DaemonViable(r) {
		t.Error("環境変数で rssLimit を明示したのに常駐が拒まれています")
	}
}

// TestWarmTimeoutSecDefaultsWhenMissing は warmTimeoutSec の無い古い hooks.json でも
// 起動できること (1 リリースの間の軟着陸) を見る。
func TestWarmTimeoutSecDefaultsWhenMissing(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join(repoRoot(t), hooks.RulesPath))
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	delete(doc["checkd"].(map[string]any)["daemon"].(map[string]any), "warmTimeoutSec")
	stripped, err := json.Marshal(doc)
	if err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, filepath.Dir(hooks.RulesPath)), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, hooks.RulesPath), stripped, 0o644); err != nil {
		t.Fatal(err)
	}
	r, err := hooks.LoadRules(root)
	if err != nil {
		t.Fatalf("キー無しで読めるはずが: %v", err)
	}
	if got := *r.Checkd.Daemon.WarmTimeoutSec; got != 240 {
		t.Errorf("既定値 240 になっていません: %v", got)
	}
}

func TestIdleSecHonorsEnv(t *testing.T) {
	r := loadRules(t)
	t.Setenv(*r.Checkd.Daemon.IdleEnvVar, "42")
	if got := idleSec(r).Seconds(); got != 42 {
		t.Errorf("環境変数の上書きが効いていません: %v", got)
	}
}

func TestFlixBinPrefersPackageLocalWrapper(t *testing.T) {
	pkg := t.TempDir()
	if err := os.MkdirAll(filepath.Join(pkg, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	local := filepath.Join(pkg, "bin", "flix")
	if err := os.WriteFile(local, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if got := flixBin("/nonexistent", pkg); got != local {
		t.Errorf("パッケージ足元の bin/flix を優先していません: %s", got)
	}
}

func TestFlixBinReadsEngineFromLocalMk(t *testing.T) {
	engine := t.TempDir()
	if err := os.MkdirAll(filepath.Join(engine, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(engine, "bin", "flix")
	if err := os.WriteFile(want, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	pkg := t.TempDir()
	if err := os.WriteFile(filepath.Join(pkg, "local.mk"),
		[]byte("ENGINE := "+engine+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("ENGINE", "")
	if got := flixBin("/nonexistent", pkg); got != want {
		t.Errorf("local.mk の ENGINE を見ていません: %s", got)
	}
}
