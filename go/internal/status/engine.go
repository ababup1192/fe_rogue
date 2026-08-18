package status

// engine の場所とバージョンの解決。
//
// 解決順は 環境変数 ENGINE → local.mk。呼ぶ側は置き場（local.mk を探すディレクトリ）
// だけを渡す。
//
// WhyNot: 呼ぶ側ごとに解決を書かないのは、同じ順で読まないと fge と status で
// 見ている engine が食い違うため。

import (
	"os"
	"path/filepath"
)

// 「先頭の空白 ENGINE 空白 [?:]* = 空白 値」。値の末尾の空白は落とす。
var engineLineRe = compilePySpace(`^\s*ENGINE\s*[?:]*=\s*(.+?)\s*$`)

// Makefile の「VERSION := 値」。
var versionLineRe = compilePySpace(`^VERSION\s*:=\s*(\S+)`)

// ReadEngineDir は base（ゲームのリポの根）から見た engine の場所。
// 環境変数 ENGINE → base/local.mk の順で読む。見つからなければ空文字。
func ReadEngineDir(base string) string {
	if v := os.Getenv("ENGINE"); v != "" {
		return v
	}
	text, err := readTextPy(filepath.Join(base, "local.mk"))
	if err != nil {
		return ""
	}
	for _, line := range pyFileLines(text) {
		if m := engineLineRe.FindStringSubmatch(line); m != nil {
			return m[1]
		}
	}
	return ""
}

// ReadEngineVersion は engine の Makefile から VERSION := を読む。
// 読めなければ空文字（fail-open）。
func ReadEngineVersion(engine string) string {
	text, err := readTextPy(filepath.Join(engine, "Makefile"))
	if err != nil {
		return ""
	}
	for _, line := range pyFileLines(text) {
		if m := versionLineRe.FindStringSubmatch(line); m != nil {
			return m[1]
		}
	}
	return ""
}
