// Package checkd は flix check / flix test の常駐高速化。
//
// flix repl をパッケージごとに裏で 1 つだけ立てて温めておき、`:check` や `:test` を
// 使い回すことで、毎回 JVM とコンパイラを立ち上げ直す時間 (数秒) を省く。
// 見た目と終了コードは素の `bin/flix check` / `bin/flix test` と同じに揃える。
//
// 常駐が無い/壊れている/応答しない時は、黙って素の CLI に落ちる。
// 速さより結果の正しさを常に優先する。
//
// WhyNot: OS 固有の仕組み (Unix ドメインソケット・シグナル) で組まないのは、
// Windows で同じ物が無く、そこだけ別の作りになるため。repl とは素のパイプで話し、
// 常駐とは 127.0.0.1 の TCP で話す。
package checkd

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/ababup1192/flix_game_engine/go/internal/hooks"
)

// Usage は引数を読めなかったときに出す使い方。
const Usage = `使い方: fge checkd [パッケージdir]   # check する (省略時はカレント)
        fge checkd --test [dir]      # test する (check と同じ常駐 repl を使う)
        fge checkd --stop [dir]      # そのパッケージの常駐を止める
        fge checkd --stop-all        # 常駐を全部止める
`

// ansi は端末の飾り。repl の出力から落として、CLI と同じ字面に揃える。
var ansi = regexp.MustCompile("\x1b\\[[0-9;?]*[a-zA-Z]|\x1b\\][^\x07]*\x07|\x1b[=>]")

// Run は fge checkd の入口。out が check の出力、errOut が経過の記録。
func Run(out, errOut *strings.Builder, root string, args []string) (int, error) {
	r, err := hooks.LoadRules(root)
	if err != nil {
		return 2, err
	}
	switch {
	case len(args) > 0 && args[0] == "--daemon":
		if len(args) < 2 {
			fmt.Fprint(errOut, Usage)
			return 2, nil
		}
		return serve(r, root, pkgDirOf(args[1])), nil
	case len(args) > 0 && args[0] == "--stop-all":
		return stopAll(r, out), nil
	case len(args) > 0 && args[0] == "--stop":
		arg := ""
		if len(args) > 1 {
			arg = args[1]
		}
		return stop(r, out, pkgDirOf(arg), false), nil
	}
	verb := "check"
	if len(args) > 0 && args[0] == "--test" {
		verb, args = "test", args[1:]
	}
	if len(args) > 0 && strings.HasPrefix(args[0], "--") {
		fmt.Fprint(errOut, Usage)
		return 2, nil
	}
	arg := ""
	if len(args) > 0 {
		arg = args[0]
	}
	pkg := pkgDirOf(arg)
	if !isFile(filepath.Join(pkg, "flix.toml")) {
		fmt.Fprintf(errOut, "[checkd] %s に flix.toml がありません\n", pkg)
		return 2, nil
	}
	return clientRun(r, out, errOut, root, pkg, verb), nil
}

// pkgDirOf は引数 (空ならカレント) を symlink を解いた絶対パスにする。
func pkgDirOf(arg string) string {
	if arg == "" {
		arg, _ = os.Getwd()
	}
	abs, err := filepath.Abs(arg)
	if err != nil {
		abs = arg
	}
	if real, err := filepath.EvalSymlinks(abs); err == nil {
		return real
	}
	return abs
}

// stateDir はそのパッケージの状態の置き場 (無ければ作る)。
func stateDir(r *hooks.Rules, pkg string) string {
	d := hooks.StateDir(r, pkg)
	_ = os.MkdirAll(d, 0o755)
	return d
}

func isFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

func isExec(path string) bool {
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() {
		return false
	}
	return info.Mode().Perm()&0o111 != 0
}

func seconds(v float64) time.Duration {
	return time.Duration(v * float64(time.Second))
}
