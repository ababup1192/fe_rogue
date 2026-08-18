package hooks

// hook-art-edit — 絵に関わるファイルを書いた直後に走る検査。
//
// 絵の下限はモデルの判断に任せると飛ばされるので、機械の側から必ず声を出す。
// exit 2 で stderr が Claude に返る（作業自体は止めない）。同じ検査は
// bin/fge palette / bin/fge ui-overflow --strict / bin/fge view でも走らせられる。

import (
	"fmt"
	"io"
	"strings"
)

// Lint は 1 本の検査の呼び方（precommit と同じ形）。
type Lint func(out, errOut *strings.Builder, args []string) int

// RunArtEdit は書かれたファイル 1 つだけを見る。
func RunArtEdit(errOut io.Writer, root string, in io.Reader, lints map[string]Lint) int {
	payload, ok := ReadPayload(in)
	if !ok {
		return 0
	}
	r, err := LoadRules(root)
	if err != nil {
		fmt.Fprintf(errOut, "# hook-art-edit: %v\n", err)
		return 2
	}
	target := payload.sub("tool_input").str("file_path")
	if target == "" || !isFile(target) {
		return 0
	}

	var msgs []string
	for _, c := range r.ArtEdit.Checks {
		// WhyNot: 名前で絞らずファイル名の末尾だけ見るのは、描画の少ないファイルを
		// 落とすのが検査側 (view の下限本数) の仕事で、入口が二重に絞ると
		// どちらが黙らせたのか追えなくなるため。
		if !strings.HasSuffix(target, c.Suffix) {
			continue
		}
		lint, known := lints[c.Sub]
		if !known {
			fmt.Fprintf(errOut, "# hook-art-edit: 知らない検査です: %s\n", c.Sub)
			return 2
		}
		var out, errBody strings.Builder
		args := make([]string, 0, len(c.Args))
		for _, a := range c.Args {
			args = append(args, strings.ReplaceAll(a, "{file}", target))
		}
		if lint(&out, &errBody, args) == 0 {
			continue
		}
		body := strings.TrimSpace(out.String() + errBody.String())
		if c.Prefix == "" {
			msgs = append(msgs, body)
			continue
		}
		msgs = append(msgs, c.Prefix+"\n\n"+body)
	}
	if len(msgs) == 0 {
		return 0
	}
	fmt.Fprintln(errOut, strings.Join(msgs, "\n\n"))
	return 2
}
