package carve

// 工程の絵を 4 方向 × コマの一覧に並べる。
//
//	fge-go carve-sheet 2_陰影

import (
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// SheetViews は一覧に並べる向き。
var SheetViews = []string{"front", "east", "back", "west"}

// SheetFrames は一覧に並べるコマ。
var SheetFrames = []string{"idle", "walk_0", "walk_1", "walk_2", "walk_3",
	"swing_0", "swing_1", "swing_2",
	"jump_0", "jump_1", "jump_2"}

// ReadPNGSheet は RGBA8 の PNG を読む。
//
// WhyNot: pxlib.ReadPNG に寄せないのは、こちらが 4 チャンネル決め打ちで
// 色票つきを読めないため。読める絵の範囲まで含めて写す。
func ReadPNGSheet(path string) (int, int, [][]RGBA, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, 0, nil, err
	}
	pos, w, h := 8, 0, 0
	var idat []byte
	for pos+8 <= len(data) {
		ln := int(binary.BigEndian.Uint32(data[pos : pos+4]))
		kind := string(data[pos+4 : pos+8])
		switch kind {
		case "IHDR":
			w = int(binary.BigEndian.Uint32(data[pos+8 : pos+12]))
			h = int(binary.BigEndian.Uint32(data[pos+12 : pos+16]))
		case "IDAT":
			idat = append(idat, data[pos+8:pos+8+ln]...)
		}
		pos += 12 + ln
	}
	zr, err := zlib.NewReader(bytes.NewReader(idat))
	if err != nil {
		return 0, 0, nil, err
	}
	raw, err := io.ReadAll(zr)
	if err != nil {
		return 0, 0, nil, err
	}
	stride := w * 4
	rows := make([][]RGBA, 0, h)
	prev := make([]byte, stride)
	i := 0
	for y := 0; y < h; y++ {
		filt := raw[i]
		i++
		line := make([]byte, stride)
		copy(line, raw[i:i+stride])
		i += stride
		for x := 0; x < stride; x++ {
			var a, c int
			if x >= 4 {
				a, c = int(line[x-4]), int(prev[x-4])
			}
			b := int(prev[x])
			switch filt {
			case 1:
				line[x] = byte((int(line[x]) + a) & 255)
			case 2:
				line[x] = byte((int(line[x]) + b) & 255)
			case 3:
				line[x] = byte((int(line[x]) + (a+b)/2) & 255)
			case 4:
				p := a + b - c
				pa, pb, pc := absInt(p-a), absInt(p-b), absInt(p-c)
				near := c
				if pa <= pb && pa <= pc {
					near = a
				} else if pb <= pc {
					near = b
				}
				line[x] = byte((int(line[x]) + near) & 255)
			}
		}
		prev = line
		row := make([]RGBA, w)
		for x := 0; x < w; x++ {
			row[x] = RGBA{int(line[x*4]), int(line[x*4+1]), int(line[x*4+2]), int(line[x*4+3])}
		}
		rows = append(rows, row)
	}
	return w, h, rows, nil
}

func absInt(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

// RunSheet は carve-sheet の入口。root は assets / gallery を置く根。
func RunSheet(out *strings.Builder, root string, args []string, rules *Rules) (int, error) {
	stage := "2_陰影"
	if len(args) > 0 {
		stage = args[0]
	}
	var made []string
	bodies, err := sortedDir(filepath.Join(root, "gallery"))
	if err != nil {
		return 1, err
	}
	for _, body := range bodies {
		home := filepath.Join(root, "gallery", body, stage)
		if !isDir(home) {
			continue
		}
		type tile struct {
			w, h int
			px   [][]RGBA
		}
		var tiles []tile
		for _, v := range SheetViews {
			for _, f := range SheetFrames {
				w, h, px, err := ReadPNGSheet(filepath.Join(home, fmt.Sprintf("%s_%s.png", v, f)))
				if err != nil {
					return 1, err
				}
				tiles = append(tiles, tile{w, h, px})
			}
		}
		tw, th := 0, 0
		for _, t := range tiles {
			if t.w > tw {
				tw = t.w
			}
			if t.h > th {
				th = t.h
			}
		}
		cols := len(SheetFrames) * len(SheetViews)
		canvas := make([][]RGBA, th)
		for y := range canvas {
			row := make([]RGBA, tw*cols)
			for x := range row {
				row[x] = rules.SheetBack
			}
			canvas[y] = row
		}
		for i, t := range tiles {
			ox := i*tw + (tw-t.w)/2
			oy := th - t.h
			for y := 0; y < t.h; y++ {
				for x := 0; x < t.w; x++ {
					if t.px[y][x][3] != 0 {
						canvas[oy+y][ox+x] = t.px[y][x]
					}
				}
			}
		}
		path := filepath.Join(root, "gallery", fmt.Sprintf("_一覧_%s_%s.png", body, stage))
		if err := os.WriteFile(path, PNGOf(tw*cols, th, canvas), 0o644); err != nil {
			return 1, err
		}
		rel, _ := filepath.Rel(root, path)
		made = append(made, rel)
	}
	fmt.Fprintln(out, strings.Join(made, "\n"))
	return 0, nil
}

func sortedDir(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	sort.Strings(names)
	return names, nil
}

func isDir(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}
