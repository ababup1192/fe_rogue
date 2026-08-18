package precommit

// precommit — git commit の直前に走るゲート (bin/precommit.py と同じ出力)。
//
// 自分では何も判定せず、bin/ の検査を順に呼んで結果を束ねる。Python 版は
// 子プロセス (python3 bin/fge <サブコマンド>) を起こすが、Go 版は同じプロセスの
// 中でハンドラを直に呼ぶ。呼び方と並びは bin/lint-rules/precommit.json が持つ。
//
// 出力の並びについて:
// Python の親は print() をまとめ書き (パイプへ出すときは終了時に一括) し、子は
// その場で書く。だから「子の出力が全部先・親の知らせが後」になる。Go 版もこれに
// 合わせて、子の出力は Stdout / Stderr へその場で書き、親の知らせだけを out へ
// 貯めて呼び側 (main) に最後へ書かせる。

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/pxlib"
)

// Lint は 1 本の検査の入口。out が stdout・errOut が stderr へ出す分。
type Lint func(out, errOut *strings.Builder, args []string) int

// Options は Run に渡す道具立て。
type Options struct {
	// Root はリポジトリの根 (絶対パスに直してから使う)。
	Root string
	// Args は Python 版の sys.argv[1:] にあたる引数 (--root は取り除いた後)。
	Args []string
	// Stdout / Stderr は子の検査がその場で書く先。
	Stdout io.Writer
	Stderr io.Writer
	// Lints はサブコマンド名から検査の入口を引く表。
	Lints map[string]Lint
	// Images は「過去から追跡されている絵」の検査 (終了コードだけを見る)。
	Images func(root string) int
}

type runner struct {
	opts   Options
	rules  *Rules
	root   string
	parent *strings.Builder
}

// ResolveRoot は根を絶対パスに直し、途中の symlink も解く。
// WhyNot: filepath.Abs だけで済ませないのは、Python 版の ROOT が Path.resolve()
// (symlink まで解く) で、macOS の /var → /private/var のような食い違いが出ると
// 検査が出すパスの見え方が変わるため。
func ResolveRoot(path string) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", fmt.Errorf("根のパスを解けません: %v", err)
	}
	if real, err := filepath.EvalSymlinks(abs); err == nil {
		return real, nil
	}
	return abs, nil
}

// Run はゲートを走らせる。out には親が出す知らせだけが入る (呼び側が最後に書く)。
func Run(out *strings.Builder, opts Options) (int, error) {
	root, err := ResolveRoot(opts.Root)
	if err != nil {
		return 2, err
	}
	rules, err := LoadRules(root)
	if err != nil {
		return 2, err
	}
	r := &runner{opts: opts, rules: rules, root: root, parent: out}

	// WhyNot: 根へ移ってから走らせるのは、Python 版が子を cwd=ROOT で起こすため。
	// 相対パスのままの検査対象がここで解決される (出力に絶対パスを混ぜない)。
	old, err := os.Getwd()
	if err != nil {
		return 2, fmt.Errorf("いまの場所を取れません: %v", err)
	}
	if err := os.Chdir(root); err != nil {
		return 2, fmt.Errorf("根へ移れません: %v", err)
	}
	defer func() { _ = os.Chdir(old) }()

	staged, err := r.stagedFiles()
	if err != nil {
		return 2, err
	}
	return r.gate(staged)
}

// stagedFiles は今回ステージしたパス。--files が来ていればそちらを使う。
func (r *runner) stagedFiles() ([]string, error) {
	args := r.opts.Args
	// WhyNot: len(args) > 1 を見るのは、Python 版が len(sys.argv) > 2 を見て
	// 「--files だけ」のときはステージを読みに行くため。
	if len(args) > 1 && args[0] == "--files" {
		return args[1:], nil
	}
	cmd := exec.Command("git", "-C", r.root, "diff", "--cached",
		"--name-only", "--diff-filter=ACMR", "-z")
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("git diff --cached が失敗しました: %v", err)
	}
	var paths []string
	for _, p := range strings.Split(string(out), "\x00") {
		if p != "" && !pxlib.InTestdata(p) {
			paths = append(paths, p)
		}
	}
	return paths, nil
}

func (r *runner) gate(staged []string) (int, error) {
	if len(staged) == 0 {
		return 0, nil
	}
	failed := false

	li := r.hasTool(r.rules.StagedImages.Tool)
	problems := r.checkStagedImages(staged, li)
	if len(problems) > 0 {
		failed = true
		fmt.Fprintf(r.parent, "[pre-commit] 画像 %d 件:\n", len(problems))
		for _, m := range problems {
			fmt.Fprintf(r.parent, "  %s\n", m)
		}
	}

	for _, c := range r.rules.Checks {
		matched := selectPaths(staged, c.When)
		if len(matched) == 0 {
			continue
		}
		var args []string
		args = append(args, c.Flags...)
		if c.Pass == "matched" {
			args = append(args, matched...)
		}
		code, err := r.runLint(c, args)
		if err != nil {
			return 2, err
		}
		if code != 0 {
			failed = true
		}
	}

	if len(selectPaths(staged, r.rules.DocsSync.When)) > 0 && r.hasDocsSyncTarget() {
		if r.runMake("-s", r.rules.DocsSync.Target) != 0 {
			failed = true
		}
	}

	if failed {
		fmt.Fprint(r.parent, "[pre-commit] 止めました。直してから再コミット"+
			" (どうしても通すなら git commit --no-verify)\n")
		return 1, nil
	}
	return 0, nil
}

func selectPaths(staged []string, m Matcher) []string {
	var out []string
	for _, p := range staged {
		if m.Match(p) {
			out = append(out, p)
		}
	}
	return out
}

// hasTool は bin/<name> が在るか。無ければ 1 行知らせて false (fail-open)。
func (r *runner) hasTool(name string) bool {
	info, err := os.Stat(filepath.Join(r.root, "bin", name))
	if err == nil && info.Mode().IsRegular() {
		return true
	}
	fmt.Fprintln(r.parent, strings.ReplaceAll(r.rules.FailOpen.ToolMissing, "{name}", name))
	return false
}

// runLint は検査を 1 本走らせる。道具が無ければ 0 (fail-open)。
func (r *runner) runLint(c Check, args []string) (int, error) {
	if !r.hasTool(c.Tool) {
		return 0, nil
	}
	fn := r.opts.Lints[c.Sub]
	if fn == nil {
		return 0, fmt.Errorf("サブコマンド %s の入口がありません (bin/lint-rules/precommit.json)", c.Sub)
	}
	var body, errBody strings.Builder
	code := fn(&body, &errBody, args)
	// WhyNot: stderr を先に書くのは、Python の子が stderr を素通し・stdout を
	// 終了時にまとめて書くため。2>&1 でまとめて受けたときの行順をそろえる。
	io.WriteString(r.opts.Stderr, errBody.String())
	io.WriteString(r.opts.Stdout, body.String())
	return code, nil
}

func human(n int64) string {
	if n >= 1024*1024 {
		return fmt.Sprintf("%.1fMB", float64(n)/1024/1024)
	}
	return fmt.Sprintf("%.0fKB", float64(n)/1024)
}

// checkStagedImages は今回ステージした画像だけを、置き場と大きさの決まりに照らす。
func (r *runner) checkStagedImages(staged []string, li bool) []string {
	var problems []string
	if !li {
		return problems
	}
	s := r.rules.StagedImages
	var imgs []string
	for _, p := range staged {
		if s.IsImage(p) {
			imgs = append(imgs, p)
		}
	}
	for _, p := range imgs {
		if !s.Allowed(p) {
			problems = append(problems, p+" — 追跡してよい置き場ではありません。"+
				"生成した絵は git に入れない決まりです。"+
				"人に見せる絵なら docs/gallery/ へ (上限あり)")
			continue
		}
		var size int64
		if info, err := os.Stat(filepath.Join(r.root, p)); err == nil {
			size = info.Size()
		}
		if strings.HasPrefix(p, s.GalleryPrefix) && size > s.GalleryMaxFileBytes {
			problems = append(problems, fmt.Sprintf("%s が %s — 1 枚の上限 %s (docs/gallery/README.md)",
				p, human(size), human(s.GalleryMaxFileBytes)))
		}
	}
	// 過去分の違反はここでは止めない。画像を触るコミットのときだけ 1 行知らせる。
	if len(imgs) > 0 && len(problems) == 0 {
		if r.opts.Images != nil && r.opts.Images(r.root) != 0 {
			fmt.Fprint(r.parent, "[pre-commit] 注意: 過去から追跡されている絵に違反が残っています"+
				" (このコミットは止めません): python3 bin/fge images で一覧\n")
		}
	}
	return problems
}

// hasDocsSyncTarget は make に配線検査のターゲットが在るか。
// 無い・make 自体が無いなら 1 行知らせてスキップ (fail-open)。
func (r *runner) hasDocsSyncTarget() bool {
	cmd := exec.Command("make", "-q", r.rules.DocsSync.Target)
	cmd.Dir = r.root
	_ = cmd.Run()
	if cmd.ProcessState == nil {
		// 起こせなかった = Python の OSError と同じ位置。
		fmt.Fprintln(r.parent, r.rules.FailOpen.MakeMissing)
		return false
	}
	if cmd.ProcessState.ExitCode() == r.rules.FailOpen.TargetMissingExitCode {
		fmt.Fprintln(r.parent, r.rules.FailOpen.TargetMissing)
		return false
	}
	return true
}

// runMake は出力をそのまま見せて終了コードを返す。
func (r *runner) runMake(args ...string) int {
	cmd := exec.Command("make", args...)
	cmd.Dir = r.root
	cmd.Stdout = r.opts.Stdout
	cmd.Stderr = r.opts.Stderr
	_ = cmd.Run()
	if cmd.ProcessState == nil {
		return 1
	}
	return cmd.ProcessState.ExitCode()
}
