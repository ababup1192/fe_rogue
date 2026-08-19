package main

import (
	"strings"

	"github.com/ababup1192/flix_game_engine/go/internal/migrationnotes"
)

func init() {
	registerEngineOnly("migration-notes",
		"1 つ前のリリースからの非互換と、engine 自身の追随例を 1 枚へ焼く", cmdMigrationNotes)
}

// migrationNotesResult は --json 用のまとめ。
type migrationNotesResult struct {
	Lines  []string `json:"lines"`
	Errors []string `json:"errors"`
	Exit   int      `json:"exit"`
}

func cmdMigrationNotes(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	root, rest := declRootFlag(rest)
	var body, errBody strings.Builder
	code, err := migrationnotes.Run(&body, &errBody, root, dropJSONFlag(rest))
	code = orAbort(errOut, code, err)
	if asJSON {
		emitJSON(out, migrationNotesResult{splitLines(body.String()), splitLines(errBody.String()), code})
		return code
	}
	out.WriteString(body.String())
	errOut.WriteString(errBody.String())
	return code
}
