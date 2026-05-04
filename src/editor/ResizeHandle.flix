// ResizeHandle — 選択枠の 8 個のハンドル（4 隅 + 4 辺）の判定と座標計算
//
// 選択中ノードの bbox（screen 座標）に対して 8 個の小さな矩形を「ハンドル」として配置し、
// マウス押下位置 → どのハンドルがヒットしたか / リサイズの結果新しい bbox はどうなるか
// を純粋関数として計算する。
//
// 実際の Scene 更新（scale 変更 + position 補正）は DragInput 側で行う。
// 描画は Overlay 側で `overlayRects` の結果を ColorRect として並べる

mod ResizeHandle {

    /// 8 方向のハンドル名。順序は all() の戻り値で固定
    pub enum Handle with Eq, ToString {
        case TopLeft
        case Top
        case TopRight
        case Right
        case BottomRight
        case Bottom
        case BottomLeft
        case Left
    }

    /// 8 ハンドルを 1 リストで返す（Overlay 描画 / hit 判定の走査で使う）
    pub def all(): List[Handle] =
        Handle.TopLeft :: Handle.Top :: Handle.TopRight ::
        Handle.Right :: Handle.BottomRight :: Handle.Bottom ::
        Handle.BottomLeft :: Handle.Left :: Nil

    /// ハンドル 1 個の見た目サイズ（正方形の 1 辺、ピクセル）
    pub def handleSize(): Float64 = 8.0

    /// ハンドルの hit 判定で「中心からどれだけ外れても掴めるか」（ピクセル）。
    /// 描画サイズより少し大きめにしておくと細い handle でも掴みやすい
    pub def hitRadius(): Float64 = 6.0

    /// bbox の左上 + サイズ から、指定ハンドルの中心 screen 座標を返す
    pub def centerOf(handle: Handle, box: {topLeft = Vec2.Vec2, size = Vec2.Vec2}):
            Vec2.Vec2 =
        let x0 = box#topLeft#x;
        let y0 = box#topLeft#y;
        let xMid = x0 + box#size#x / 2.0;
        let yMid = y0 + box#size#y / 2.0;
        let x1 = x0 + box#size#x;
        let y1 = y0 + box#size#y;
        match handle {
            case Handle.TopLeft     => {x = x0,   y = y0}
            case Handle.Top         => {x = xMid, y = y0}
            case Handle.TopRight    => {x = x1,   y = y0}
            case Handle.Right       => {x = x1,   y = yMid}
            case Handle.BottomRight => {x = x1,   y = y1}
            case Handle.Bottom      => {x = xMid, y = y1}
            case Handle.BottomLeft  => {x = x0,   y = y1}
            case Handle.Left        => {x = x0,   y = yMid}
        }

    /// ハンドル中心から ±handleSize/2 の正方形 Rect2 を返す（描画用）
    pub def overlayRect(handle: Handle,
                        box: {topLeft = Vec2.Vec2, size = Vec2.Vec2}): Rect2.Rect2 =
        let center = centerOf(handle, box);
        let half = handleSize() / 2.0;
        {position = {x = center#x - half, y = center#y - half},
         size = {x = handleSize(), y = handleSize()}}

    /// 8 個のハンドルすべてについて (Handle, Rect2) を返す（Overlay 描画用）
    pub def overlayRects(box: {topLeft = Vec2.Vec2, size = Vec2.Vec2}):
            List[(Handle, Rect2.Rect2)] =
        all() |> List.map(handle -> (handle, overlayRect(handle, box)))

    /// マウス位置にヒットするハンドルを 1 個返す。複数候補があれば優先順は all() の順
    /// （TopLeft → Top → ... → Left）。hit 判定は handleSize/2 + hitRadius の余裕をもつ
    pub def hitTest(mousePos: Vec2.Vec2,
                    box: {topLeft = Vec2.Vec2, size = Vec2.Vec2}): Option[Handle] =
        all() |> List.findLeft(handle -> {
            let center = centerOf(handle, box);
            let dx = Float64.abs(mousePos#x - center#x);
            let dy = Float64.abs(mousePos#y - center#y);
            let radius = handleSize() / 2.0 + hitRadius();
            dx <= radius and dy <= radius
        })

    /// ハンドルがリサイズで動かす方向。
    /// movesLeft=true なら左辺が動く（= 右辺がアンカー）。
    /// movesTop=true なら上辺が動く（= 下辺がアンカー）。
    /// 偽のときはその辺は固定で、対辺が動く
    pub type alias DragAxes = {movesLeft = Bool, movesRight = Bool,
                               movesTop = Bool, movesBottom = Bool}

    /// 各ハンドルが「どの辺を動かすか」を返す
    pub def dragAxes(handle: Handle): DragAxes =
        match handle {
            case Handle.TopLeft     => {movesLeft = true,  movesRight = false,
                                        movesTop = true,   movesBottom = false}
            case Handle.Top         => {movesLeft = false, movesRight = false,
                                        movesTop = true,   movesBottom = false}
            case Handle.TopRight    => {movesLeft = false, movesRight = true,
                                        movesTop = true,   movesBottom = false}
            case Handle.Right       => {movesLeft = false, movesRight = true,
                                        movesTop = false,  movesBottom = false}
            case Handle.BottomRight => {movesLeft = false, movesRight = true,
                                        movesTop = false,  movesBottom = true}
            case Handle.Bottom      => {movesLeft = false, movesRight = false,
                                        movesTop = false,  movesBottom = true}
            case Handle.BottomLeft  => {movesLeft = true,  movesRight = false,
                                        movesTop = false,  movesBottom = true}
            case Handle.Left        => {movesLeft = true,  movesRight = false,
                                        movesTop = false,  movesBottom = false}
        }

    /// ドラッグ後の bbox（topLeft + size）を計算する。
    /// originalBox: ドラッグ開始時の bbox。mouseDelta: ドラッグ開始からのマウス移動量。
    /// 動かさない辺はそのまま、動かす辺は mouseDelta だけ移動する。
    /// サイズが minSize 未満になる場合はクランプする（負スケール防止）
    pub def applyDrag(handle: Handle,
                      originalBox: {topLeft = Vec2.Vec2, size = Vec2.Vec2},
                      mouseDelta: Vec2.Vec2,
                      minSize: Vec2.Vec2):
            {topLeft = Vec2.Vec2, size = Vec2.Vec2} =
        let axes = dragAxes(handle);
        let leftDelta   = if (axes#movesLeft)   mouseDelta#x else 0.0;
        let rightDelta  = if (axes#movesRight)  mouseDelta#x else 0.0;
        let topDelta    = if (axes#movesTop)    mouseDelta#y else 0.0;
        let bottomDelta = if (axes#movesBottom) mouseDelta#y else 0.0;
        let newLeft   = originalBox#topLeft#x + leftDelta;
        let newRight  = originalBox#topLeft#x + originalBox#size#x + rightDelta;
        let newTop    = originalBox#topLeft#y + topDelta;
        let newBottom = originalBox#topLeft#y + originalBox#size#y + bottomDelta;
        // 各軸ごとに最小サイズ確保（左右どちらが動いていたかでクランプ位置が変わる）
        let (clampedLeft, clampedRight) =
            clampAxis({lo = newLeft, hi = newRight, minSpan = minSize#x,
                       loMoves = axes#movesLeft, hiMoves = axes#movesRight,
                       origLo = originalBox#topLeft#x,
                       origHi = originalBox#topLeft#x + originalBox#size#x});
        let (clampedTop, clampedBottom) =
            clampAxis({lo = newTop, hi = newBottom, minSpan = minSize#y,
                       loMoves = axes#movesTop, hiMoves = axes#movesBottom,
                       origLo = originalBox#topLeft#y,
                       origHi = originalBox#topLeft#y + originalBox#size#y});
        {topLeft = {x = clampedLeft, y = clampedTop},
         size = {x = clampedRight - clampedLeft, y = clampedBottom - clampedTop}}

    /// 1 軸分のクランプ。最小幅 minSpan を割り込む場合、動いていない側を維持して
    /// 動いている側を minSpan 確保する位置に押し戻す
    def clampAxis(args: {lo = Float64, hi = Float64, minSpan = Float64,
                         loMoves = Bool, hiMoves = Bool,
                         origLo = Float64, origHi = Float64}): (Float64, Float64) =
        let span = args#hi - args#lo;
        if (span >= args#minSpan) (args#lo, args#hi)
        else if (args#loMoves and args#hiMoves)
            // 両端可動はないが念のため: 中点を保って広げる
            let mid = (args#lo + args#hi) / 2.0;
            (mid - args#minSpan / 2.0, mid + args#minSpan / 2.0)
        else if (args#loMoves)
            // 動いているのは lo 側 → hi 側 (= origHi) を固定し lo を minSpan 手前に
            (args#origHi - args#minSpan, args#origHi)
        else
            // 動いているのは hi 側 → lo 側 (= origLo) を固定し hi を minSpan 先に
            (args#origLo, args#origLo + args#minSpan)
}
