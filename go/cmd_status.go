package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/status"
)

func init() {
	register("status", "現状 1 画面 (テスト記録・スナップショット・チケット・git)", cmdStatus)
}

// statusResult は --json 用のまとめ。
type statusResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdStatus(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	// WhyNot: --root を規約データの置き場にしないのは、Python 版がカレントを起点に
	// 走査する道具で、差し替えたいのは「見に行く先」の方だから。規約データは
	// バイナリの居場所（engine のリポ）から読む。
	target, rest, hasRoot := declValueFlag(rest, "--root")
	nowText, rest, hasNow := declValueFlag(rest, "--now")

	var opts status.Options
	if hasRoot {
		opts.Root = target
	}
	if hasNow {
		now, err := status.ParseNow(nowText)
		if err != nil {
			return orAbort(errOut, 2, err)
		}
		opts.Now = now
	}

	var body, errBody strings.Builder
	code, err := status.Run(&body, &errBody, repoRoot(), dropJSONFlag(rest), opts)
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, statusResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
