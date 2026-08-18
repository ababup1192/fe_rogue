package explainerror

// explain-error — flix check / test の出力を要約し、既知のエラーに処方箋 1 行を添える。
//
//	flix check > check.log 2>&1; code=$?
//	bin/fge explain-error --status $code --log check.log < check.log
//
// 成功は 1 行、失敗は「最初のエラー全文 + 残りの file:line 一覧 + 件数 + ログの場所」
// まで絞る。
//
// WhyNot: エラーブロック (`-- ` 見出し) が 1 つも読み取れない失敗出力を要約しないのは、
// 未知の形式を黙って削ると読み手が全文の cat に戻り、絞った意味が消えるため。

import (
	"fmt"
	"io"
	"strconv"
	"strings"
	"unicode"
)

// block は 1 つのエラーブロックの見出し。
type block struct {
	index  int    // 見出しの行番号
	label  string // エラー種別 (例: Type Error [E5252])
	path   string // ファイル
	lineno string // 行番号 (読めなければ空)
}

// Options は要約の引数。
type Options struct {
	Status    int    // check の終了コード
	HasStatus bool   // --status が渡されたか
	LogPath   string // 全文の置き場所として案内するパス (空なら案内しない)
}

// ParseArgs は --status / --log を読む。
//
// WhyNot: 知らない引数をエラーにしないのは、この道具がパイプの途中に居て、
// 引数の解釈で落ちると check の結果そのものが読めなくなるため。
func ParseArgs(args []string) Options {
	var o Options
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--status":
			i++
			if i < len(args) {
				if n, err := strconv.Atoi(args[i]); err == nil {
					o.Status, o.HasStatus = n, true
				}
			}
		case "--log":
			i++
			if i < len(args) {
				o.LogPath = args[i]
			}
		}
	}
	return o
}

// Run は標準入力を読んで要約を 1 つ書き出す。
func Run(out io.Writer, root string, args []string, in io.Reader) (int, error) {
	rules, err := LoadRules(root)
	if err != nil {
		return 2, err
	}
	data, err := io.ReadAll(in)
	if err != nil {
		return 2, fmt.Errorf("標準入力を読めません: %v", err)
	}
	fmt.Fprintln(out, Summarize(rules, string(data), ParseArgs(args)))
	return 0, nil
}

// Summarize は check の出力 1 本を要約した文字列を返す。
func Summarize(r *Rules, text string, o Options) string {
	lines := splitLines(r.Ansi.ReplaceAllString(text, ""))
	blocks := parseBlocks(r, lines)
	failed := len(blocks) > 0
	if o.HasStatus {
		failed = o.Status != 0
	}

	if !failed {
		note := ""
		if len(blocks) > 0 {
			where := ""
			if o.LogPath != "" {
				where = " — 全文は " + o.LogPath
			}
			note = fmt.Sprintf(" (警告 %d 件%s)", len(blocks), where)
		}
		return "[check] OK" + note
	}
	if len(blocks) == 0 {
		return rstrip(text)
	}

	out := []string{blockText(lines, blocks, 0)}
	if len(blocks) > 1 {
		out = append(out, "", fmt.Sprintf("残り %d 件:", len(blocks)-1))
		for _, b := range blocks[1:] {
			loc := b.path
			if b.lineno != "" {
				loc = b.path + ":" + b.lineno
			}
			out = append(out, fmt.Sprintf("  %s — %s", loc, b.label))
		}
	}
	if tail := lastLineWith(lines, r.ErrorCountMark); tail != "" {
		out = append(out, "", strings.TrimSpace(tail))
	}
	if o.LogPath != "" {
		out = append(out, "全文: "+o.LogPath)
	}
	// 処方箋は「いま表示している 1 件目」に対して引く。1 件目に当たりが無いときだけ
	// 残りの見出し行へ下がる。
	tip := Prescribe(r, out[0])
	if tip == "" {
		var heads []string
		for _, b := range blocks[1:] {
			heads = append(heads, lines[b.index])
		}
		tip = Prescribe(r, strings.Join(heads, "\n"))
	}
	if tip != "" {
		out = append(out, fmt.Sprintf(r.TipFormat, tip))
	}
	return strings.Join(out, "\n")
}

// FirstErrorBlock は Flix の出力から最初のエラーブロックだけ抜く。
// 次の見出しか maxLines 行のどちらか早い方で切る。見出しが 1 つも無ければ末尾
// tailLines 行を返す（フックが「何も出せない」で終わらないため）。
func FirstErrorBlock(r *Rules, text string, maxLines, tailLines int) string {
	lines := splitLines(r.Ansi.ReplaceAllString(text, ""))
	start := -1
	for i, l := range lines {
		if strings.HasPrefix(l, "-- ") {
			start = i
			break
		}
	}
	if start < 0 {
		from := len(lines) - tailLines
		if from < 0 {
			from = 0
		}
		return rstrip(strings.Join(lines[from:], "\n"))
	}
	blockLines := []string{lines[start]}
	for _, l := range lines[start+1:] {
		if strings.HasPrefix(l, "-- ") || len(blockLines) >= maxLines {
			break
		}
		blockLines = append(blockLines, l)
	}
	return rstrip(strings.Join(blockLines, "\n"))
}

// Prescribe は本文に最初に当たった処方箋 1 行を返す (無ければ空)。
func Prescribe(r *Rules, text string) string {
	for _, p := range r.Prescriptions {
		if strings.Contains(text, p.Key) {
			return p.Tip
		}
	}
	return ""
}

func parseBlocks(r *Rules, lines []string) []block {
	var blocks []block
	for i, line := range lines {
		m := r.Head.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		b := block{index: i, label: strings.TrimSpace(m[1]), path: m[2]}
		end := i + r.HeadLookahead
		if end > len(lines) {
			end = len(lines)
		}
		for _, l := range lines[i+1 : end] {
			if r.Head.MatchString(l) {
				break
			}
			if n := r.Lineno.FindStringSubmatch(l); n != nil {
				b.lineno = n[1]
				break
			}
		}
		blocks = append(blocks, b)
	}
	return blocks
}

func blockText(lines []string, blocks []block, idx int) string {
	start := blocks[idx].index
	end := len(lines)
	if idx+1 < len(blocks) {
		end = blocks[idx+1].index
	}
	return rstrip(strings.Join(lines[start:end], "\n"))
}

func lastLineWith(lines []string, mark string) string {
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.Contains(lines[i], mark) {
			return lines[i]
		}
	}
	return ""
}

func rstrip(s string) string { return strings.TrimRightFunc(s, unicode.IsSpace) }

// splitLines は本文を行に割る。
// WhyNot: 末尾の改行 1 つだけを落とすのは、空行で終わる出力の最後の空行を
// 数え落とさないため。
func splitLines(s string) []string {
	s = strings.ReplaceAll(s, "\r\n", "\n")
	if s == "" {
		return nil
	}
	s = strings.TrimSuffix(s, "\n")
	return strings.Split(s, "\n")
}
