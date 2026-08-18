package hooks

// フックへ標準入力で届くペイロード（エージェントが渡す JSON）の読み取り。
//
// WhyNot: 決め打ちの構造体 1 つに落とさないのは、編集ツールの入力の形が
// エージェントごとに違い（Claude Code は tool_input.file_path、apply_patch は
// tool_input.command にパッチ本文）、知らない形を読めた気になって取り落とすため。

import (
	"encoding/json"
	"io"
	"strings"
)

// Payload は届いた JSON。読めなかったときは空。
type Payload map[string]any

// ReadPayload は標準入力の JSON を読む。形が読めなければ空と false。
func ReadPayload(in io.Reader) (Payload, bool) {
	data, err := io.ReadAll(in)
	if err != nil {
		return Payload{}, false
	}
	var p Payload
	if err := json.Unmarshal(data, &p); err != nil || p == nil {
		return Payload{}, false
	}
	return p, true
}

func (p Payload) str(key string) string {
	if v, ok := p[key].(string); ok {
		return v
	}
	return ""
}

func (p Payload) sub(key string) Payload {
	if v, ok := p[key].(map[string]any); ok {
		return Payload(v)
	}
	return Payload{}
}

// Bool はその印が真か（無ければ false）。
func (p Payload) Bool(key string) bool {
	v, ok := p[key].(bool)
	return ok && v
}

// SessionID はこのセッションの ID（取れなければ空）。
func (p Payload) SessionID() string { return p.str("session_id") }

// TranscriptPath は会話ログの置き場（取れなければ空）。
func (p Payload) TranscriptPath() string { return p.str("transcript_path") }

// EditedPath は編集されたファイルのパスを 1 つ拾う（取れなければ空）。
func (p Payload) EditedPath() string {
	ti, tr := p.sub("tool_input"), p.sub("tool_response")
	for _, cand := range []string{
		ti.str("file_path"), ti.str("path"),
		tr.str("file_path"), tr.str("path"),
		p.str("file_path"), p.str("path"),
	} {
		if cand != "" {
			return cand
		}
	}
	return ""
}

// EditedPaths は編集されたファイルのパスを全部拾う。
// file_path / path が来る形（Edit・Write）を先に見て、どちらも無く command が
// 文字列で来る形（apply_patch）だけパッチ本文としても読む。
func (p Payload) EditedPaths(r *Rules) []string {
	ti := p.sub("tool_input")
	if path := ti.str("file_path"); path != "" {
		return []string{path}
	}
	if path := ti.str("path"); path != "" {
		return []string{path}
	}
	if command := ti.str("command"); command != "" {
		return patchPaths(r, command)
	}
	return nil
}

// patchPaths は apply_patch のパッチ本文からファイルのパスを全部取り出す。
// WhyNot: 先頭の 1 件で止めないのは、1 つのパッチが複数ファイルを含みうるため。
func patchPaths(r *Rules, command string) []string {
	var out []string
	for _, line := range strings.Split(command, "\n") {
		for _, prefix := range r.Checkd.PatchFilePrefixes {
			if strings.HasPrefix(line, prefix) {
				if p := strings.TrimSpace(strings.TrimPrefix(line, prefix)); p != "" {
					out = append(out, p)
				}
				break
			}
		}
	}
	return out
}
