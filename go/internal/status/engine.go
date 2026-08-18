package status

// engine の場所とバージョンの解決。
//
// bin/status.py の read_engine_dir / read_engine_version と bin/fge の同名関数は
// 同じ解決順（環境変数 ENGINE → local.mk）を持っている。Go 側では 1 か所にまとめて、
// 呼ぶ側が置き場（local.mk を探すディレクトリ）だけを渡す。

import (
	"os"
	"path/filepath"
)

// 「先頭の空白 ENGINE 空白 [?:]* = 空白 値」。値の末尾の空白は落とす。
var engineLineRe = compilePySpace(`^\s*ENGINE\s*[?:]*=\s*(.+?)\s*$`)

// Makefile の「VERSION := 値」。
var versionLineRe = compilePySpace(`^VERSION\s*:=\s*(\S+)`)

// ReadEngineDir は base（Python 版のカレントに当たる）から見た engine の場所。
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
