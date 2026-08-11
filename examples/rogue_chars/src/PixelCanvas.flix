// PixelCanvas — 32×32 のドット絵キャンバス（純粋）。キャンバスは「座標 → 色」の Map で、
// キーが無いセルは透明。全操作が新しい Canvas を返す値ベースの DSL なので、
// パーツを部品ごとに組んで overlay で重ねる合成スタイルで絵を作る。
//
// 出口は 2 つ:
//   - toPlaced … ギャラリー（SoftRaster）用に 1 ピクセル = 1×1 の RawDraw.box へ変換
//   - SheetBake が Map を直接 setRGB で PNG へ blit（こちらは等倍・正確）

mod PixelCanvas {
    import java.lang.Math

    pub type alias Canvas = Map[(Int32, Int32), Color]

    /// キャンバスの一辺（32px 固定）。
    pub def size(): Int32 = 32

    pub def empty(): Canvas = Map.empty()

    /// 1 ドット置く。0..31 の範囲外は書き込まない（クランプせず捨てる —
    /// はみ出した作画は単に消えるので、シルエットが歪まない）。
    pub def dot(x: Int32, y: Int32, c: Color, cv: Canvas): Canvas =
        if (x >= 0 and x < size() and y >= 0 and y < size())
            Map.insert((x, y), c, cv)
        else
            cv

    /// 左上 (x,y) から w×h の塗りつぶし矩形。
    pub def rectFill(x: Int32, y: Int32, w: Int32, h: Int32, c: Color, cv: Canvas): Canvas =
        List.range(0, h) |> List.foldLeft((acc, dy) -> hline(x, y + dy, w, c, acc), cv)

    /// 水平線（長さ w）。
    pub def hline(x: Int32, y: Int32, w: Int32, c: Color, cv: Canvas): Canvas =
        List.range(0, w) |> List.foldLeft((acc, dx) -> dot(x + dx, y, c, acc), cv)

    /// 垂直線（長さ h）。
    pub def vline(x: Int32, y: Int32, h: Int32, c: Color, cv: Canvas): Canvas =
        List.range(0, h) |> List.foldLeft((acc, dy) -> dot(x, y + dy, c, acc), cv)

    /// 任意の 2 点を結ぶ直線（Bresenham）。剣の軌跡や槍の柄のような斜め線に使う。
    pub def line(x0: Int32, y0: Int32, x1: Int32, y1: Int32, c: Color, cv: Canvas): Canvas =
        let dx = Int32.abs(x1 - x0);
        let sx = if (x0 < x1) 1 else -1;
        let dy = -Int32.abs(y1 - y0);
        let sy = if (y0 < y1) 1 else -1;
        lineLoop(x0, y0, x1, y1, dx, dy, sx, sy, dx + dy, c, cv)

    def lineLoop(x: Int32, y: Int32, x1: Int32, y1: Int32, dx: Int32, dy: Int32,
                 sx: Int32, sy: Int32, err: Int32, c: Color, cv: Canvas): Canvas =
        let cv1 = dot(x, y, c, cv);
        if (x == x1 and y == y1)
            cv1
        else {
            let e2 = 2 * err;
            let (x2, errA) = if (e2 >= dy) (x + sx, err + dy) else (x, err);
            let (y2, errB) = if (e2 <= dx) (y + sy, errA + dx) else (y, errA);
            lineLoop(x2, y2, x1, y1, dx, dy, sx, sy, errB, c, cv1)
        }

    /// 中心 (cx,cy)・半径 r の塗りつぶし円板（x²+y² ≤ r²）。
    pub def discFill(cx: Int32, cy: Int32, r: Int32, c: Color, cv: Canvas): Canvas =
        List.range(-r, r + 1) |> List.foldLeft((accY, oy) ->
            List.range(-r, r + 1) |> List.foldLeft((accX, ox) ->
                if (ox * ox + oy * oy <= r * r) dot(cx + ox, cy + oy, c, accX) else accX,
                accY),
            cv)

    /// 左右反転（x → 31-x）。横向きクリップは左向きで作画し、右向きはこれで作る。
    pub def hflip(cv: Canvas): Canvas =
        Map.foldLeftWithKey((acc, k, c) -> {
            let (x, y) = k;
            Map.insert((size() - 1 - x, y), c, acc)
        }, Map.empty(), cv)

    /// 上下反転（y → 31-y）。逆さ吊りの演出や、倒れ絵の使い回しに使う。
    pub def vflip(cv: Canvas): Canvas =
        Map.foldLeftWithKey((acc, k, c) -> {
            let (x, y) = k;
            Map.insert((x, size() - 1 - y), c, acc)
        }, Map.empty(), cv)

    /// 中心 (cx,cy)・半径 r の円弧。角度は度（整数）で 0 度 = 右・反時計回り
    /// （画面の y は下向きなので 90 度は中心の真上）。武器の斬撃軌跡に使う。
    /// 円周ピクセルは Bresenham（中点円）で決めてから角度でフィルタするので、
    /// 同じ引数なら常に同じドットが置かれる（浮動小数のサンプリング間隔に依存しない）。
    pub def arc(cx: Int32, cy: Int32, r: Int32, a0deg: Int32, a1deg: Int32, c: Color, cv: Canvas): Canvas =
        circlePoints(r)
            |> List.filter(p -> { let (ox, oy) = p; angleWithin(ox, oy, a0deg, a1deg) })
            |> List.foldLeft((acc, p) -> { let (ox, oy) = p; dot(cx + ox, cy + oy, c, acc) }, cv)

    /// 半径 r の円周の全オフセット（中点円アルゴリズム・8 分円の鏡映）。
    /// 軸上などで重複が出るが、dot は同じセルへの上書きなので害はない。
    def circlePoints(r: Int32): List[(Int32, Int32)] =
        if (r <= 0)
            (0, 0) :: Nil
        else
            circleLoop(r, 0, 1 - r, Nil)

    def circleLoop(x: Int32, y: Int32, err: Int32, acc: List[(Int32, Int32)]): List[(Int32, Int32)] =
        if (y > x)
            acc
        else {
            let pts = (x, y) :: (y, x) :: (-x, y) :: (-y, x) ::
                      (x, -y) :: (y, -x) :: (-x, -y) :: (-y, -x) :: Nil;
            let (x1, err1) =
                if (err >= 0) (x - 1, err + 2 * (y - x) + 5) else (x, err + 2 * y + 3);
            circleLoop(x1, y + 1, err1, List.append(pts, acc))
        }

    /// オフセット (ox,oy) の角度が [a0..a1]（反時計回りの掃引・度）に入るか。
    /// y は画面座標（下向き）なので符号を返してから atan2 に渡す。
    def angleWithin(ox: Int32, oy: Int32, a0deg: Int32, a1deg: Int32): Bool =
        // Math.atan2 は同じ入力に同じ出力を返す純粋な計算なので、効果なしへキャストする。
        let rad = unchecked_cast(Math.atan2(Int32.toFloat64(-oy), Int32.toFloat64(ox)) as _ \ {});
        let deg = normDeg(rad * 180.0 / 3.141592653589793);
        let a0 = normDeg(Int32.toFloat64(a0deg));
        let a1 = normDeg(Int32.toFloat64(a1deg));
        if (a0 <= a1)
            a0 <= deg and deg <= a1
        else
            deg >= a0 or deg <= a1   // 0 度またぎ（例: 330..30 度）

    /// 度を 0 以上 360 未満へ正規化する。
    def normDeg(d: Float64): Float64 =
        let m = d - Float64.floor(d / 360.0) * 360.0;
        if (m >= 360.0) m - 360.0 else m

    /// 平行移動。範囲外に出たドットは破棄する。
    pub def shift(dx: Int32, dy: Int32, cv: Canvas): Canvas =
        Map.foldLeftWithKey((acc, k, c) -> {
            let (x, y) = k;
            dot(x + dx, y + dy, c, acc)
        }, Map.empty(), cv)

    /// top を bottom の上に重ねる（両方にあるセルは top が勝つ）。
    pub def overlay(top: Canvas, bottom: Canvas): Canvas =
        Map.union(top, bottom)

    /// ギャラリー用の出口: 1 ピクセルを 1×1 の RawDraw.box にして design 座標
    /// (originX+x, originY+y) へ置く。整数座標なので SoftRaster の scale=4 でも
    /// にじまずクリスプに拡大される。
    pub def toPlaced(originX: Int32, originY: Int32, cv: Canvas): List[Render.PlacedItem] =
        Map.foldLeftWithKey((acc, k, c) -> {
            let (x, y) = k;
            let pos = { x = Int32.toFloat64(originX + x), y = Int32.toFloat64(originY + y) };
            { at = pos, item = RawDraw.box({ x = 1.0, y = 1.0 }, c, 10) } :: acc
        }, Nil, cv)
}
