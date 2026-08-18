package style

import (
	"testing"

	"github.com/ababup1192/flix_game_engine/go/internal/pxlib"
)

// 何を見るか: 測りの 4 つの数（格子適合・面の切り出し・楕円・覆う色数）が
// Python 版と同じ定義で出ること。

// solid は 1 色ずつ塗り分けた絵を組む（col は x, y から色を返す）。
func solid(w, h int, col func(x, y int) (byte, byte, byte)) *pxlib.Image {
	im := &pxlib.Image{W: w, H: h, Pix: make([]byte, w*h*4)}
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			r, g, b := col(x, y)
			o := (y*w + x) * 4
			im.Pix[o], im.Pix[o+1], im.Pix[o+2], im.Pix[o+3] = r, g, b, 255
		}
	}
	return im
}

func TestGridFitCountsOnlyChanges(t *testing.T) {
	// 4 画素ごとに色が変わる縞。unit=4 なら段は全部格子に乗る。
	im := solid(16, 4, func(x, _ int) (byte, byte, byte) {
		v := byte((x / 4) * 60)
		return v, v, v
	})
	if got := gridFit(im, 4); got != 1.0 {
		t.Errorf("unit=4 の生の適合率が %v (期待 1)", got)
	}
	if got := gridFit(im, 3); got >= 1.0 {
		t.Errorf("unit=3 の生の適合率が %v (期待 1 未満)", got)
	}
}

func TestGridScoreIsNoneForUnit1(t *testing.T) {
	im := solid(4, 4, func(int, int) (byte, byte, byte) { return 0, 0, 0 })
	if _, ok := gridScore(im, 1); ok {
		t.Error("unit=1 で格子適合率が出ている (Python は None)")
	}
	if _, ok := gridScore(im, 2); !ok {
		t.Error("unit=2 で格子適合率が出ていない")
	}
}

func TestCoverCountStopsAtNinetyPercent(t *testing.T) {
	counts := map[uint32]int{1: 90, 2: 5, 3: 5}
	if got := coverCount(counts, 100); got != 1 {
		t.Errorf("90%% を覆う色数が %d (期待 1)", got)
	}
	if got := coverCount(map[uint32]int{1: 50, 2: 45, 3: 5}, 100); got != 2 {
		t.Errorf("90%% を覆う色数が %d (期待 2)", got)
	}
}

// 正方形は Python 版でも「楕円そのもの」に数えられる (IoU 0.8915920840735931)。
// 判定の甘さごと写す。
func TestEllipseIOUOfSquareMatchesPython(t *testing.T) {
	var square []int32
	for y := 0; y < 10; y++ {
		for x := 0; x < 10; x++ {
			square = append(square, int32(y*10+x))
		}
	}
	if iou := regionEllipseIOU(square, 10); iou != 0.8915920840735931 {
		t.Errorf("正方形の IoU が %v (Python は 0.8915920840735931)", iou)
	}
}

func TestFindRegionsDropsSmallAndCaps(t *testing.T) {
	rules, err := LoadRules(repoRoot())
	if err != nil {
		t.Fatal(err)
	}
	// 左半分と右半分の 2 面。min_area を 100 にすると 8x8 の面は落ちる。
	im := solid(16, 16, func(x, _ int) (byte, byte, byte) {
		if x < 8 {
			return 0, 0, 0
		}
		return 255, 255, 255
	})
	q := rules.quantize(im)
	if got := len(rules.findRegions(q, 16, 16, 100)); got != 2 {
		t.Errorf("面の数が %d (期待 2)", got)
	}
	if got := len(rules.findRegions(q, 16, 16, 200)); got != 0 {
		t.Errorf("小さい面が落ちていない: %d", got)
	}
}
