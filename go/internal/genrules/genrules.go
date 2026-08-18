package genrules

// genrules — docs/ の規約から .claude/rules/*.md を作る。
//
//	fge-go gen-rules              生成する
//	fge-go gen-rules --check      ずれていないか検査する（書かない）
//	fge-go gen-rules --out DIR    .claude/rules と agents-pack/rules を DIR の下へ書く
//	fge-go gen-rules --root DIR   元の doc を読む先を差し替える
//
// --out はリポの生成物を上書きせずに突き合わせるための口。

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// universalNewlines は行末（\r\n・\r）を \n に均す。
// WhyNot: 生バイトのまま比べないのは、CRLF で置かれた rules を中身が同じでも
// 違うと見てしまい、毎回書き直しになるため。
func universalNewlines(s string) string {
	s = strings.ReplaceAll(s, "\r\n", "\n")
	return strings.ReplaceAll(s, "\r", "\n")
}

// render は 1 本のルールの本文（見出し + 元の doc）を組む。
func (r *Rules) render(root string, spec RuleSpec) (string, error) {
	data, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(spec.Src)))
	if err != nil {
		return "", err
	}
	head := []string{"---", "paths:"}
	for _, g := range spec.Globs {
		// WhyNot: %q を使わないのは、中身をそのまま二重引用符で挟むだけにするため。
		// エスケープすると glob に \ や " が入ったとき字面が変わる。
		head = append(head, `  - "`+g+`"`)
	}
	head = append(head, "---", "", strings.ReplaceAll(r.Banner, "{src}", spec.Src), "")
	return strings.Join(head, "\n") + string(data), nil
}

// Options は書き出し先の差し替え。OutBase が空なら root の下へ書く。
type Options struct {
	OutBase string
}

// Run は生成（または --check）を走らせて終了コードを返す。
// err が返ったとき呼ぶ側は必ず止まる（規約を読めないまま緑にしない）。
func Run(out, errOut *strings.Builder, root string, args []string, opts Options) (int, error) {
	rules, err := LoadRules(root)
	if err != nil {
		return 2, err
	}
	check := false
	for _, a := range args {
		if a == "--check" {
			check = true
		}
	}
	outBase := opts.OutBase
	if outBase == "" {
		outBase = root
	}

	var stale []string
	for _, outRel := range rules.OutDirs {
		outDir := filepath.Join(outBase, filepath.FromSlash(outRel))
		if !check {
			if err := os.MkdirAll(outDir, 0o755); err != nil {
				return 2, fmt.Errorf("書き出し先を作れません: %v", err)
			}
		}
		for _, spec := range rules.Rules {
			src := filepath.Join(root, filepath.FromSlash(spec.Src))
			if info, err := os.Stat(src); err != nil || !info.Mode().IsRegular() {
				fmt.Fprintf(errOut, "元の doc がありません: %s\n", spec.Src)
				return 1, nil
			}
			want, err := rules.render(root, spec)
			if err != nil {
				return 2, fmt.Errorf("元の doc を読めません: %v", err)
			}
			dest := filepath.Join(outDir, filepath.FromSlash(spec.Out))
			have, haveOK := "", false
			if info, err := os.Stat(dest); err == nil && info.Mode().IsRegular() {
				data, err := os.ReadFile(dest)
				if err != nil {
					return 2, fmt.Errorf("生成物を読めません: %v", err)
				}
				have, haveOK = universalNewlines(string(data)), true
			}
			if haveOK && have == want {
				continue
			}
			if check {
				stale = append(stale, fmt.Sprintf("%s/%s が %s とずれています", outRel, spec.Out, spec.Src))
				continue
			}
			if err := os.WriteFile(dest, []byte(want), 0o644); err != nil {
				return 2, fmt.Errorf("書き出せません: %v", err)
			}
			fmt.Fprintf(out, "wrote %s/%s <- %s\n", outRel, spec.Out, spec.Src)
		}
	}

	if len(stale) > 0 {
		for _, line := range stale {
			fmt.Fprintln(errOut, line)
		}
		fmt.Fprintln(errOut, "`make rules` で作り直してください。")
		return 1, nil
	}
	if check {
		fmt.Fprintln(out, "[gen-rules] OK: .claude/rules と agents-pack/rules は docs/ と一致しています")
	}
	return 0, nil
}
