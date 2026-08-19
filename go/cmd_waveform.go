package main

import (
	"fmt"
	"strings"
)

func init() {
	register("waveform", "WAV を波形＋スペクトログラムの 1 枚に描き出す", cmdWaveform)
}

func cmdWaveform(out, errOut *strings.Builder, rest []string, asJSON bool) int {
	outPath := ""
	var paths []string
	for i := 0; i < len(rest); i++ {
		switch {
		case rest[i] == "--out" && i+1 < len(rest):
			outPath = rest[i+1]
			i++
		case strings.HasPrefix(rest[i], "--out="):
			outPath = strings.TrimPrefix(rest[i], "--out=")
		case strings.HasPrefix(rest[i], "--"):
		default:
			paths = append(paths, rest[i])
		}
	}
	if len(paths) == 0 {
		fmt.Fprintln(errOut, "使い方: fge waveform <wavファイル|フォルダ...> --out <PNGのパス>")
		return 2
	}
	return runWaveform(out, errOut, paths, outPath, asJSON)
}
