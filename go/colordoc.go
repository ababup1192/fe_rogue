package main

// 色票 (theme / paletteFile / inline palette) を解く土台。
// palette サブコマンドと sil サブコマンドが共有する。

import (
	"encoding/json"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// paletteExcludedDirs は lint-palette.py の EXCLUDED_DIRS。
var paletteExcludedDirs = map[string]bool{
	"build": true, "lib": true, ".git": true, "gallery": true,
	".devbox": true, "node_modules": true, "archive": true,
}

// spriteExcludedDirs は lint-sprite.py の EXCLUDED_DIRS (archive を含まない)。
var spriteExcludedDirs = map[string]bool{
	"build": true, "lib": true, ".git": true, "gallery": true,
	".devbox": true, "node_modules": true,
}

var colorWrapKeys = []string{"hex", "color", "value"}

var gameRoots = []string{"templates"}

func readJSON(path string) any {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var v any
	if json.Unmarshal(data, &v) != nil {
		return nil
	}
	return v
}

func asObject(v any) (map[string]any, bool) {
	m, ok := v.(map[string]any)
	return m, ok
}

func isHexColor(text string) bool {
	body := strings.TrimPrefix(text, "#")
	if len(body) != 6 {
		return false
	}
	for _, c := range body {
		if !strings.ContainsRune("0123456789abcdefABCDEF", c) {
			return false
		}
	}
	return true
}

func isFloats3(v any) bool {
	arr, ok := v.([]any)
	if !ok || len(arr) != 3 {
		return false
	}
	for _, x := range arr {
		if _, ok := x.(float64); !ok {
			return false
		}
	}
	return true
}

func floats3(v any) [3]float64 {
	arr := v.([]any)
	return [3]float64{arr[0].(float64), arr[1].(float64), arr[2].(float64)}
}

// isColor は Studio の colorHexOf と同じ方言で「色として読めるか」を見る。
func isColor(v any) bool {
	if s, ok := v.(string); ok {
		return isHexColor(s)
	}
	if m, ok := asObject(v); ok {
		_, hasHSV := m["hsv"]
		_, hasRGB := m["rgb"]
		if hasHSV && !hasRGB {
			return isFloats3(m["hsv"])
		}
		if hasRGB && !hasHSV {
			return isFloats3(m["rgb"])
		}
		for _, k := range colorWrapKeys {
			if inner, ok := m[k]; ok && isColor(inner) {
				return true
			}
		}
	}
	return false
}

// hexOfValue は色として読める値から "#rrggbb" を取り出す (hsv/rgb 表記は対象外)。
func hexOfValue(v any) string {
	if s, ok := v.(string); ok && isHexColor(s) {
		return "#" + strings.ToLower(strings.TrimPrefix(s, "#"))
	}
	if m, ok := asObject(v); ok {
		for _, k := range colorWrapKeys {
			if inner, ok := m[k]; ok {
				if found := hexOfValue(inner); found != "" {
					return found
				}
			}
		}
	}
	return ""
}

func colorNamesOf(v any) map[string]bool {
	names := map[string]bool{}
	m, ok := asObject(v)
	if !ok {
		return names
	}
	for name, value := range m {
		if isColor(value) {
			names[name] = true
		}
	}
	if nested, ok := asObject(m["colors"]); ok {
		for name, value := range nested {
			if isColor(value) {
				names[name] = true
			}
		}
	}
	return names
}

// walkJSON は game_dir 配下の .json を game_dir 相対で集める。
func walkJSON(gameDir string, excluded map[string]bool) []string {
	var found []string
	var rec func(dir string)
	rec = func(dir string) {
		entries, err := os.ReadDir(dir)
		if err != nil {
			return
		}
		var dirs, files []string
		for _, e := range entries {
			if e.IsDir() {
				if !excluded[e.Name()] {
					dirs = append(dirs, e.Name())
				}
			} else if strings.HasSuffix(e.Name(), ".json") {
				files = append(files, e.Name())
			}
		}
		sort.Strings(files)
		for _, f := range files {
			rel, _ := filepath.Rel(gameDir, filepath.Join(dir, f))
			found = append(found, rel)
		}
		sort.Strings(dirs)
		for _, d := range dirs {
			rec(filepath.Join(dir, d))
		}
	}
	rec(gameDir)
	sort.Strings(found)
	return found
}

// gameDirsOf は templates/* を挙げる。空なら fallback が真のとき自分自身を挙げる。
// WhyNot: 空のまま返すと「検査したが問題なし」と見分けが付かず、ゲートが黙って通る。
func gameDirsOf(root string, fallback func() bool) []string {
	var dirs []string
	for _, group := range gameRoots {
		groupDir := filepath.Join(root, group)
		entries, err := os.ReadDir(groupDir)
		if err != nil {
			continue
		}
		var names []string
		for _, e := range entries {
			names = append(names, e.Name())
		}
		sort.Strings(names)
		for _, name := range names {
			rel := group + "/" + name
			if info, err := os.Stat(filepath.Join(root, rel)); err == nil && info.IsDir() {
				dirs = append(dirs, rel)
			}
		}
	}
	if len(dirs) == 0 && fallback() {
		dirs = append(dirs, ".")
	}
	return dirs
}

func hasDir(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func hasFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

// --- 実色への変換 (sil が使う) -------------------------------------------

// RGBA は 8bit の色。
type RGBA [4]byte

func rgbaOfHex(hex string) RGBA {
	body := strings.TrimPrefix(hex, "#")
	var out RGBA
	for i := 0; i < 3; i++ {
		v, _ := strconv.ParseUint(body[i*2:i*2+2], 16, 8)
		out[i] = byte(v)
	}
	out[3] = 255
	return out
}

func rgbaOfFloats(v [3]float64) RGBA {
	var out RGBA
	for i := 0; i < 3; i++ {
		// WhyNot: math.Round ではなく RoundToEven。Python の round() は
		// ちょうど半分を偶数側へ寄せるので、ここを変えると色が 1 段ずれる。
		n := math.RoundToEven(v[i] * 255)
		if n < 0 {
			n = 0
		}
		if n > 255 {
			n = 255
		}
		out[i] = byte(n)
	}
	out[3] = 255
	return out
}

// rgbaOfHSV は engine/src/core/Color.flix の hsv と同じ変換 (h は 1 周 = 1.0)。
func rgbaOfHSV(h, s, v float64) RGBA {
	h6 := (h - math.Floor(h)) * 6.0
	f := h6 - math.Floor(h6)
	p, q, u := v*(1-s), v*(1-s*f), v*(1-s*(1-f))
	switch {
	case h6 < 1:
		return rgbaOfFloats([3]float64{v, u, p})
	case h6 < 2:
		return rgbaOfFloats([3]float64{q, v, p})
	case h6 < 3:
		return rgbaOfFloats([3]float64{p, v, u})
	case h6 < 4:
		return rgbaOfFloats([3]float64{p, q, v})
	case h6 < 5:
		return rgbaOfFloats([3]float64{u, p, v})
	default:
		return rgbaOfFloats([3]float64{v, p, q})
	}
}

// rgbaOfValue は色 1 値を RGBA にする。読めなければ ok=false。
func rgbaOfValue(v any) (RGBA, bool) {
	if found := hexOfValue(v); found != "" {
		return rgbaOfHex(found), true
	}
	if m, ok := asObject(v); ok {
		_, hasHSV := m["hsv"]
		_, hasRGB := m["rgb"]
		if isFloats3(m["rgb"]) && !hasHSV {
			return rgbaOfFloats(floats3(m["rgb"])), true
		}
		if isFloats3(m["hsv"]) && !hasRGB {
			c := floats3(m["hsv"])
			return rgbaOfHSV(c[0], c[1], c[2]), true
		}
		for _, k := range colorWrapKeys {
			if inner, ok := m[k]; ok {
				if got, ok := rgbaOfValue(inner); ok {
					return got, true
				}
			}
		}
	}
	return RGBA{}, false
}

func colorMapOf(v any) map[string]RGBA {
	found := map[string]RGBA{}
	m, ok := asObject(v)
	if !ok {
		return found
	}
	sources := []map[string]any{m}
	if nested, ok := asObject(m["colors"]); ok {
		sources = append(sources, nested)
	}
	for _, src := range sources {
		for name, value := range src {
			if got, ok := rgbaOfValue(value); ok {
				found[name] = got
			}
		}
	}
	return found
}
