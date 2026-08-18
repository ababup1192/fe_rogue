package syncagents

// syncagents — agents-pack をゲームのリポへ配る (bin/sync-agents.py と同じ出力)。
//
//	fge-go sync-agents --game DIR [--version V]
//	fge-go sync-agents --check-manifest
//	fge-go sync-agents --root DIR      配り元のリポを差し替える
//
// 配る物の一覧は agents-pack/manifest.json を読むだけで、この道具は持たない。

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"unicode"
	"unicode/utf8"

	"github.com/ababup1192/flix_game_engine/go/internal/pxlib"
)

// manifestKeys の並びは bin/sync-agents.py の for key in (...) と同じ。
const (
	keyCopy = iota
	keyCopyIfAbsent
	keyCopyDirs
)

// manifestEntry は manifest の 1 項目。src は engine から・dst はゲームからの相対パス。
type manifestEntry struct{ src, dst string }

// Run は配り (または --check-manifest) を走らせて終了コードを返す。
// err が返ったとき呼ぶ側は必ず止まる（Python 版がその場で落ちる所）。
func Run(out, errOut *strings.Builder, root string, args []string) (int, error) {
	opts, code, done := parseArgs(out, errOut, args)
	if done {
		return code, nil
	}
	rules, err := LoadRules(root)
	if err != nil {
		return 2, err
	}
	// WhyNot: 渡された根をそのまま使わないのは、Python 側の ROOT が
	// Path(__file__).resolve() で symlink を辿った絶対パスになっていて、
	// 読めなかったファイルの名前を出すときに字面が変わるため。
	root = pyResolve(root)
	if opts.checkManifest {
		return checkManifest(errOut, root, rules)
	}
	if opts.game == "" {
		fmt.Fprintln(errOut, "error: GAME を指定してください (make sync-agents GAME=/path/to/game)")
		return 1, nil
	}
	return syncGame(out, errOut, root, rules, opts.game, opts.version)
}

// loadManifest は manifest を読んで 3 つのキーぶんの項目を返す。
// 返るエラーが *pyErr なら Python 版が画面へ出す側・そうでなければ Python 版が落ちる側。
func loadManifest(root string, r *Rules) (map[int][]manifestEntry, error) {
	path := pyJoin(root, r.ManifestPath)
	data, err := os.ReadFile(fsPath(path))
	if err != nil {
		return nil, &pyErr{pyOSErrorText(err, path)}
	}
	if !utf8.Valid(data) {
		return nil, fmt.Errorf("%s が UTF-8 として読めません", path)
	}
	v, err := pyJSONLoads(string(data))
	if err != nil {
		return nil, err
	}
	d, ok := v.(*pyDict)
	if !ok {
		return nil, fmt.Errorf("%s の中身が dict ではありません", path)
	}
	m := map[int][]manifestEntry{}
	for i, key := range r.ManifestKeys {
		raw, _ := d.get(key)
		list, ok := raw.(pyList)
		if !ok {
			return nil, &pyErr{fmt.Sprintf("manifest に %s 配列がありません", key)}
		}
		for _, e := range list {
			ed, ok := e.(*pyDict)
			if !ok || !ed.has("src") || !ed.has("dst") {
				return nil, &pyErr{fmt.Sprintf("%s の要素に src / dst がありません: %s", key, pyStr(e))}
			}
			src, _ := ed.get("src")
			dst, _ := ed.get("dst")
			srcS, srcOK := src.(string)
			dstS, dstOK := dst.(string)
			if !srcOK || !dstOK {
				return nil, fmt.Errorf("%s の要素の src / dst が文字列ではありません: %s", key, pyRepr(e))
			}
			m[i] = append(m[i], manifestEntry{src: srcS, dst: dstS})
		}
	}
	return m, nil
}

// checkManifest は manifest が正しい JSON か・src が全部あるかだけを見る。
func checkManifest(errOut *strings.Builder, root string, r *Rules) (int, error) {
	m, err := loadManifest(root, r)
	if err != nil {
		var pe *pyErr
		if errors.As(err, &pe) {
			fmt.Fprintf(errOut, "[sync-agents] NG: agents-pack/manifest.json が読めません: %s\n", pe.text)
			return 1, nil
		}
		return 2, err
	}
	bad := 0
	for i, key := range r.ManifestKeys {
		for _, e := range m[i] {
			if !pyExists(pyJoin(root, e.src)) {
				fmt.Fprintf(errOut, "[sync-agents] NG: manifest の %s が指す %s が engine に実在しません\n", key, e.src)
				bad = 1
			}
		}
	}
	links, err := checkSkillLinks(errOut, root, r)
	if err != nil {
		return 2, err
	}
	return bad | links, nil
}

// checkSkillLinks は配る markdown が指す .claude/skills/<名前>/ が実在するかを見る。
func checkSkillLinks(errOut *strings.Builder, root string, r *Rules) (int, error) {
	names, err := skillDirNames(root, r)
	if err != nil {
		return 0, err
	}
	have := map[string]bool{}
	for _, n := range names {
		have[n] = true
	}
	bad := 0
	for _, rel := range r.SkillLinkRoots {
		dir := pyJoin(root, rel)
		if !pyIsDir(dir) {
			continue
		}
		files, err := mdFilesSorted(dir)
		if err != nil {
			return 0, err
		}
		for _, f := range files {
			text, err := readTextStrict(pyJoin(dir, f))
			if err != nil {
				return 0, err
			}
			for _, name := range linkedSkills(r, text) {
				if have[name] {
					continue
				}
				fmt.Fprintf(errOut, "[sync-agents] NG: %s が指す .claude/skills/%s/ は agents-pack/skills に実在しません\n",
					pyJoin(rel, f), name)
				bad = 1
			}
		}
	}
	return bad, nil
}

// linkedSkills は本文が指している skill の名前を重複なし・名前順で返す。
func linkedSkills(r *Rules, text string) []string {
	seen := map[string]bool{}
	var names []string
	for _, m := range r.SkillLink.FindAllStringSubmatch(text, -1) {
		if !seen[m[1]] {
			seen[m[1]] = true
			names = append(names, m[1])
		}
	}
	sort.Strings(names)
	return names
}

// syncGame は 1 本のゲームへ配る。
func syncGame(out, errOut *strings.Builder, root string, r *Rules, gameArg, version string) (int, error) {
	game := pyPath(gameArg)
	if !pyIsDir(game) {
		fmt.Fprintf(errOut, "error: ゲームのフォルダが見つかりません: %s\n", game)
		return 1, nil
	}
	m, err := loadManifest(root, r)
	if err != nil {
		return 2, err
	}

	body, err := buildAgentsMD(root, r, game, version)
	if err != nil {
		return 2, err
	}
	if err := writeTextLF(pyJoin(game, r.AgentsMd), body); err != nil {
		return 2, err
	}
	if err := writeTextLF(pyJoin(game, r.ClaudeMd), r.ClaudeMdBody); err != nil {
		return 2, err
	}

	for _, e := range m[keyCopyDirs] {
		dst := pyJoin(game, e.dst)
		if err := os.MkdirAll(fsPath(dst), 0o777); err != nil {
			return 2, err
		}
		if err := copyDir(pyJoin(root, e.src), dst); err != nil {
			return 2, err
		}
	}
	skills, err := skillDirNames(root, r)
	if err != nil {
		return 2, err
	}
	for _, name := range skills {
		fmt.Fprintf(out, "[sync-agents] skill: %s\n", name)
	}

	for _, e := range m[keyCopy] {
		if err := copyFile(pyJoin(root, e.src), pyJoin(game, e.dst)); err != nil {
			return 2, err
		}
	}

	for _, e := range m[keyCopyIfAbsent] {
		dst := pyJoin(game, e.dst)
		if pyExists(dst) {
			continue
		}
		if err := copyFile(pyJoin(root, e.src), dst); err != nil {
			return 2, err
		}
		fmt.Fprintf(out, "[sync-agents] hooks: %s を配りました (既存があるときは上書きしない)\n", e.dst)
	}

	ruleNames, err := dirEntryNames(pyJoin(root, r.RulesDir))
	if err != nil {
		return 2, err
	}
	fmt.Fprintf(out, "[sync-agents] rules: %s\n", strings.Join(ruleNames, " "))
	var lints []string
	for _, e := range m[keyCopy] {
		if strings.HasPrefix(pyName(e.dst), r.LintPrefix) {
			lints = append(lints, e.dst)
		}
	}
	fmt.Fprintf(out, "[sync-agents] lint: %s\n", strings.Join(lints, " "))
	fmt.Fprintln(out, "[sync-agents] checkd: bin/checkd + .claude/hooks/after-flix-edit.py")
	fmt.Fprintln(out, "[sync-agents] 呼び口: bin/fge (検査・要約はここへ委譲。一覧は bin/fge)")
	fmt.Fprintln(out, "[sync-agents] ゲート: bin/precommit.py + bin/githooks/pre-commit (配線は make hooks)")
	fmt.Fprintf(out, "[sync-agents] wrote %s/AGENTS.md + CLAUDE.md\n", game)
	return 0, nil
}

// buildAgentsMD は AGENTS.md の全文を組む。
func buildAgentsMD(root string, r *Rules, game, version string) (string, error) {
	parts := []string{
		fmt.Sprintf("<!-- generated by flix_game_engine agents-pack (engine v%s)."+
			" 編集しないで。共通部は engine の agents-pack/AGENTS.core.md、"+
			"ゲーム固有部は AGENTS.local.md を編集して再 sync -->", version),
		"",
	}
	core, err := readTextStrict(pyJoin(root, r.CoreDoc))
	if err != nil {
		return "", err
	}
	// WhyNot: TrimSuffix ではなく TrimRight なのは、Python の rstrip("\n") が
	// 末尾の改行を 1 つではなく全部落とすため。
	parts = append(parts, strings.TrimRight(core, "\n"), "",
		"## 配られているスキル一覧（sync-agents が自動生成。手で編集しない）", "")
	skills, err := skillDirNames(root, r)
	if err != nil {
		return "", err
	}
	skillsDir := pyJoin(root, r.SkillsDir)
	for _, name := range skills {
		desc, err := skillDescription(pyJoin(pyJoin(skillsDir, name), r.SkillFile))
		if err != nil {
			return "", err
		}
		parts = append(parts, fmt.Sprintf("- `.claude/skills/%s/%s` — %s",
			name, r.SkillFile, triggerSentence(r, desc)))
	}
	local := pyJoin(game, r.LocalDoc)
	if pyIsFile(local) {
		text, err := readTextStrict(local)
		if err != nil {
			return "", err
		}
		parts = append(parts, "", strings.TrimRight(text, "\n"))
	}
	return strings.Join(parts, "\n") + "\n", nil
}

// skillDescription は frontmatter の description: の 1 行目（囲みの " は外す）を返す。
// 読めない SKILL.md は空文字にする。
func skillDescription(path string) (string, error) {
	data, err := os.ReadFile(fsPath(path))
	if err != nil {
		return "", nil
	}
	if !utf8.Valid(data) {
		return "", fmt.Errorf("%s が UTF-8 として読めません", path)
	}
	const head = "description:"
	for _, line := range pxlib.SplitLines(string(data)) {
		if !strings.HasPrefix(line, head) {
			continue
		}
		desc := pyStrip(line[len(head):])
		desc = strings.TrimPrefix(desc, `"`)
		desc = strings.TrimSuffix(desc, `"`)
		return desc, nil
	}
	return "", nil
}

// triggerSentence は description から「いつ使うか」の 1 文だけを取り出す。
func triggerSentence(r *Rules, desc string) string {
	var parts []string
	for _, s := range strings.Split(desc, r.SentenceSep) {
		if pyStrip(s) != "" {
			parts = append(parts, s)
		}
	}
	if len(parts) == 0 {
		return desc
	}
	for _, s := range parts {
		if strings.HasSuffix(pyRStrip(s), r.TriggerSuffix) {
			return pyStrip(s) + r.SentenceSep
		}
	}
	return pyStrip(parts[0]) + r.SentenceSep
}

// skillDirNames は agents-pack/skills の直下にあるフォルダの名前を名前順で返す。
func skillDirNames(root string, r *Rules) ([]string, error) {
	dir := pyJoin(root, r.SkillsDir)
	f, err := os.Open(fsPath(dir))
	if err != nil {
		return nil, err
	}
	entries, err := f.Readdirnames(-1)
	f.Close()
	if err != nil {
		return nil, err
	}
	var names []string
	for _, name := range entries {
		if pyIsDir(pyJoin(dir, name)) {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	return names, nil
}

// dirEntryNames は 1 段だけ読んで名前を名前順で返す（Path.iterdir と同じ範囲）。
func dirEntryNames(dir string) ([]string, error) {
	f, err := os.Open(fsPath(dir))
	if err != nil {
		return nil, err
	}
	names, err := f.Readdirnames(-1)
	f.Close()
	if err != nil {
		return nil, err
	}
	sort.Strings(names)
	return names, nil
}

// mdFilesSorted は dir の下の *.md を Python の sorted(rglob) と同じ並びで返す。
// 返るのは dir からの相対パス。
func mdFilesSorted(dir string) ([]string, error) {
	var found []string
	err := walkRel(dir, "", func(rel string, isDir bool) {
		if !isDir && strings.HasSuffix(rel, ".md") {
			found = append(found, rel)
		}
	})
	if err != nil {
		return nil, err
	}
	// WhyNot: sort.Strings で字面を比べないのは、Python の Path が要素ごとに比べるため
	// （"a-x/c.md" と "a/b.md" の順が字面比べだと入れ替わる）。
	sort.Slice(found, func(i, j int) bool {
		return partsLess(strings.Split(found[i], "/"), strings.Split(found[j], "/"))
	})
	return found, nil
}

func partsLess(a, b []string) bool {
	for i := 0; i < len(a) && i < len(b); i++ {
		if a[i] != b[i] {
			return a[i] < b[i]
		}
	}
	return len(a) < len(b)
}

// walkRel は Python の rglob("*") と同じ範囲を歩く（symlink のフォルダへは入らない）。
func walkRel(root, rel string, visit func(rel string, isDir bool)) error {
	dir := root
	if rel != "" {
		dir = pyJoin(root, rel)
	}
	f, err := os.Open(fsPath(dir))
	if err != nil {
		return nil
	}
	names, err := f.Readdirnames(-1)
	f.Close()
	if err != nil {
		return nil
	}
	for _, name := range names {
		childRel := name
		if rel != "" {
			childRel = rel + "/" + name
		}
		full := pyJoin(root, childRel)
		isDir := pyIsDir(full)
		visit(childRel, isDir)
		if !isDir || isSymlink(full) {
			continue
		}
		if err := walkRel(root, childRel, visit); err != nil {
			return err
		}
	}
	return nil
}

// copyDir は src の中身を dst へ重ね書きする。
func copyDir(src, dst string) error {
	var failed error
	err := walkRel(src, "", func(rel string, isDir bool) {
		if failed != nil {
			return
		}
		if isDir {
			failed = os.MkdirAll(fsPath(pyJoin(dst, rel)), 0o777)
			return
		}
		failed = copyFile(pyJoin(src, rel), pyJoin(dst, rel))
	})
	if err != nil {
		return err
	}
	return failed
}

// copyFile は中身と実行ビットを写す（配った先で bin/checkd がそのまま実行できるように）。
func copyFile(src, dst string) error {
	if err := os.MkdirAll(fsPath(pyParent(dst)), 0o777); err != nil {
		return err
	}
	info, err := os.Stat(fsPath(src))
	if err != nil {
		return err
	}
	data, err := os.ReadFile(fsPath(src))
	if err != nil {
		return err
	}
	if err := os.WriteFile(fsPath(dst), data, 0o666); err != nil {
		return err
	}
	return os.Chmod(fsPath(dst), info.Mode().Perm())
}

// writeTextLF は改行を LF のまま書く。
func writeTextLF(path, text string) error {
	return os.WriteFile(fsPath(path), []byte(text), 0o666)
}

// readTextStrict は Python の read_bytes().decode("utf-8") と同じ厳しさで読む。
func readTextStrict(path string) (string, error) {
	data, err := os.ReadFile(fsPath(path))
	if err != nil {
		return "", err
	}
	if !utf8.Valid(data) {
		return "", fmt.Errorf("%s が UTF-8 として読めません", path)
	}
	return string(data), nil
}

// pyPath は Python の str(Path(s))。
func pyPath(s string) string { return pxlib.PosixPath(s) }

// pyResolve は Python の Path(s).resolve()。
func pyResolve(s string) string {
	if abs, err := filepath.Abs(fsPath(s)); err == nil {
		s = abs
	}
	if real, err := filepath.EvalSymlinks(fsPath(s)); err == nil {
		s = real
	}
	return pyPath(s)
}

// pyJoin は Python の Path(base) / rel。rel が絶対なら rel が勝つ。
func pyJoin(base, rel string) string {
	if strings.HasPrefix(rel, "/") {
		return pyPath(rel)
	}
	return pyPath(base + "/" + rel)
}

// pyName は Python の Path(p).name。
// WhyNot: filepath.Base を使わないのは、末尾が / のとき Python が親の名前を返すのに対し
// Go は "/" を返すなど食い違うため。
func pyName(p string) string {
	_, parts := pxlib.PathParts(p)
	if len(parts) == 0 {
		return ""
	}
	return parts[len(parts)-1]
}

// pyParent は Python の Path(p).parent。
func pyParent(p string) string {
	anchor, parts := pxlib.PathParts(p)
	if len(parts) > 0 {
		parts = parts[:len(parts)-1]
	}
	joined := strings.Join(parts, "/")
	if anchor == "" {
		if joined == "" {
			return "."
		}
		return joined
	}
	return anchor + joined
}

func fsPath(p string) string { return filepath.FromSlash(p) }

func pyExists(p string) bool {
	_, err := os.Stat(fsPath(p))
	return err == nil
}

func pyIsDir(p string) bool {
	info, err := os.Stat(fsPath(p))
	return err == nil && info.IsDir()
}

func pyIsFile(p string) bool {
	info, err := os.Stat(fsPath(p))
	return err == nil && info.Mode().IsRegular()
}

func isSymlink(p string) bool {
	info, err := os.Lstat(fsPath(p))
	return err == nil && info.Mode()&os.ModeSymlink != 0
}

// pyOSErrorText は Python の str(OSError)。
// WhyNot: Go の err.Error() をそのまま出せないのは、strerror の頭が Python では
// 大文字・Go では小文字で、パスの囲み方も違うため。
func pyOSErrorText(err error, path string) string {
	var errno syscall.Errno
	if errors.As(err, &errno) {
		text := errno.Error()
		if r := []rune(text); len(r) > 0 {
			text = string(unicode.ToUpper(r[0])) + string(r[1:])
		}
		return fmt.Sprintf("[Errno %d] %s: %s", int(errno), text, pyReprString(path))
	}
	return err.Error()
}

// pyStr は Python の str(v)。文字列だけは repr と違って囲みが付かない。
func pyStr(v pyValue) string {
	if s, ok := v.(string); ok {
		return s
	}
	return pyRepr(v)
}

// pyIsSpace は Python の str.isspace()。
// WhyNot: unicode.IsSpace をそのまま使わないのは、Python が 0x1c〜0x1f も空白と数えるため。
func pyIsSpace(r rune) bool {
	if r >= 0x1c && r <= 0x1f {
		return true
	}
	return unicode.IsSpace(r)
}

func pyStrip(s string) string  { return strings.TrimFunc(s, pyIsSpace) }
func pyRStrip(s string) string { return strings.TrimRightFunc(s, pyIsSpace) }
