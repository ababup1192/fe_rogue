package apidiff

// 突き合わせを他のコマンドからも呼べるようにした口。migration-notes が使う。

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/pxlib"
)

// Compute は from（タグ）と to（空なら作業ツリー）の pub 面を突き合わせて返す。
func Compute(root, from, to string) (Result, error) {
	rules, err := LoadRules(root)
	if err != nil {
		return Result{}, err
	}
	res := newResult()
	res.From = from
	res.To = versionLabelOf(root, to)

	if from == "none" {
		return res, nil
	}

	beforeRoot, cleanup, err := exportSources(root, from)
	if err != nil {
		return Result{}, err
	}
	defer cleanup()

	afterRoot := root
	if to != "" {
		dir, c, exportErr := exportSources(root, to)
		if exportErr != nil {
			return Result{}, exportErr
		}
		defer c()
		afterRoot = dir
	}

	fillDiff(&res, beforeRoot, afterRoot, rules.DocKinds)
	return res, nil
}

// PreviousTag は 1 つ前のリリースのタグを、fail-open した告知と共に返す。
func PreviousTag(root string) (string, string, error) { return fetchPreviousTag(root) }

// PreviousTagOrNone は 1 つ前のリリースのタグを返す。前のタグが 1 つも無ければ "none"。
//
// WhyNot: タグが無いときにエラーにしないのは、make bump が VERSION と全 flix.toml を
// 書き換えた後にこれを呼ぶため。初リリースでそこが止まると、書き換え済みで異常終了する。
//
// WhyNot: エラーをまとめて "none" に倒さないのは、git や Makefile が読めないだけの
// 本当のエラーまで「初リリース」と読んでしまうため。前のタグが無いと確かめられたときだけ倒す。
func PreviousTagOrNone(root string) (string, string, error) {
	tag, notice, err := fetchPreviousTag(root)
	if err != nil && noEarlierTag(root) {
		return "none", notice, nil
	}
	return tag, notice, err
}

// noEarlierTag は Makefile の VERSION より前のタグが 1 つも無いか。確かめられなければ false。
func noEarlierTag(root string) bool {
	current, ok := makefileVersion(root)
	if !ok {
		return false
	}
	stdout, err := exec.Command("git", "-C", root, "tag", "--list", "v*").Output()
	if err != nil {
		return false
	}
	currentVal := parseVersion(current)
	for _, line := range pxlib.SplitLines(string(stdout)) {
		v := parseVersion(strings.TrimPrefix(strings.TrimSpace(line), "v"))
		if v != nil && versionLess(v, currentVal) {
			return false
		}
	}
	return true
}

// MakefileVersion は Makefile の `VERSION := x.y.z` を読む。
func MakefileVersion(root string) (string, bool) { return makefileVersion(root) }

// QualifiedName は「Mod.名前」。追随例を探す grep の鍵に使う。
//
// WhyNot: Name に既に mod が付いているとき重ねないのは、eff の op が
// `mod GameLogger { pub eff GameLogger { ... } }` の形だと Mod=GameLogger・
// Name=GameLogger.info になり、GameLogger.GameLogger.info という無い名前になるため。
func (c Change) QualifiedName() string {
	if i := strings.Index(c.Name, "."); i > 0 && c.Name[:i] == c.Mod {
		return c.Name
	}
	return fmt.Sprintf("%s.%s", c.Mod, c.Name)
}
