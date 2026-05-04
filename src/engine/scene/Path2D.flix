/// 2D パスノード（Godot Path2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_path2d.html
///
/// ポイント列で定義されたパスを保持し、sample(t) でパス上の位置と方向を取得する。
/// PathFollow2D の代わりに sample メソッドで同等の機能を提供する。
///
///   Path2D
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
pub enum Path2D {
    case Path2D({
        points = List[Vec2.Vec2],
        closed = Bool,
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color
    })
}

mod Path2D {

    /// デフォルト値で Path2D を生成する
    pub def make(points: List[Vec2.Vec2], closed: Bool): Path2D =
        Path2D.Path2D({
            points = points,
            closed = closed,
            position = Vec2.zero(),
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = false,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
        })

    /// 画面端の矩形パスを生成する（閉じたパス）
    ///
    /// ポイント: (0,0) → (W,0) → (W,H) → (0,H) → (0,0) に戻る
    pub def screenEdgePath(screenW: Int32, screenH: Int32): Path2D =
        let w = Int32.toFloat64(screenW);
        let h = Int32.toFloat64(screenH);
        make(
            {x = 0.0, y = 0.0} :: {x = w, y = 0.0} :: {x = w, y = h} :: {x = 0.0, y = h} :: Nil,
            true
        )

    /// パス上の位置と方向を t (0.0〜1.0) でサンプリングする
    ///
    /// 閉じたパスの場合、最後のポイントから最初のポイントに戻る辺も含む。
    /// 方向は辺の内向き法線（画面端パスの場合は画面中心向き）。
    ///
    /// 戻り値:
    ///   position — パス上の位置
    ///   direction — 内向きの方向（ラジアン）
    pub def sample(t: Float64, path2d: Path2D): {position = Vec2.Vec2, direction = Float64} =
        let Path2D.Path2D(r) = path2d;
        let points = r#points;
        let closed = r#closed;
        samplePoints(t, points, closed)

    /// ポイント列とパラメータ t からサンプリングする内部関数
    def samplePoints(t: Float64, points: List[Vec2.Vec2], closed: Bool): {position = Vec2.Vec2, direction = Float64} =
        let numPoints = List.length(points);
        if (numPoints < 2) {
            match List.head(points) {
                case Some(p) => { position = p, direction = 0.0 }
                case None    => { position = Vec2.zero(), direction = 0.0 }
            }
        } else {
            let numSegments = if (closed) numPoints else numPoints - 1;
            let tClamped = Float64.max(0.0, Float64.min(t, 1.0));
            let tScaled = tClamped * Int32.toFloat64(numSegments);
            let segIdx = Float64.min(Int32.toFloat64(numSegments - 1),
                            Float64.floor(tScaled));
            let segI = match Float64.tryToInt32(segIdx) {
                case Some(i) => Int32.max(0, Int32.min(numSegments - 1, i))
                case None    => 0
            };
            let frac = tScaled - segIdx;
            let p0 = listGet(segI, points);
            let nextIdx = if (closed) Int32.modulo(segI + 1, numPoints) else segI + 1;
            let p1 = listGet(nextIdx, points);
            let position = Vec2.lerp(p0, p1, frac);
            let edge: Vec2.Vec2 = Vec2.sub(p1, p0);
            // 内向き法線: 辺 (dx, dy) に対して左手法線 (-dy, dx) → atan2 で角度
            let direction = Vec2.atan2(edge#x, 0.0 - edge#y);
            { position = position, direction = direction }
        }

    /// リストの i 番目の要素を取得する（bounds check なし）
    def listGet(i: Int32, lst: List[a]): a =
        match List.head(List.drop(i, lst)) {
            case Some(v) => v
            case None => bug!("Path2D.listGet: index out of bounds")
        }
}

// -- CanvasItem 実装 --

instance CanvasItem[Path2D] {
    pub def isVisible(path: Path2D): Bool =
        let Path2D.Path2D(r) = path;
        r#visible
    pub def setVisible(visible: Bool, path: Path2D): Path2D =
        let Path2D.Path2D(r) = path;
        Path2D.Path2D({ visible = visible | r })
    pub def getModulate(path: Path2D): Color =
        let Path2D.Path2D(r) = path;
        r#modulate
    pub def setModulate(color: Color, path: Path2D): Path2D =
        let Path2D.Path2D(r) = path;
        Path2D.Path2D({ modulate = color | r })
    pub def getZIndex(path: Path2D): Int32 =
        let Path2D.Path2D(r) = path;
        r#zIndex
    pub def setZIndex(zIndex: Int32, path: Path2D): Path2D =
        let Path2D.Path2D(r) = path;
        Path2D.Path2D({ zIndex = zIndex | r })
}

// -- Node2D 実装 --

instance Node2D[Path2D] {
    pub def getPosition(path: Path2D): Vec2.Vec2 =
        let Path2D.Path2D(r) = path;
        r#position
    pub def setPosition(position: Vec2.Vec2, path: Path2D): Path2D =
        let Path2D.Path2D(r) = path;
        Path2D.Path2D({ position = position | r })
    pub def getRotation(path: Path2D): Float64 =
        let Path2D.Path2D(r) = path;
        r#rotation
    pub def setRotation(rotation: Float64, path: Path2D): Path2D =
        let Path2D.Path2D(r) = path;
        Path2D.Path2D({ rotation = rotation | r })
    pub def getScale(path: Path2D): Vec2.Vec2 =
        let Path2D.Path2D(r) = path;
        r#scale
    pub def setScale(scale: Vec2.Vec2, path: Path2D): Path2D =
        let Path2D.Path2D(r) = path;
        Path2D.Path2D({ scale = scale | r })
    pub def getSkew(path: Path2D): Float64 =
        let Path2D.Path2D(r) = path;
        r#skew
    pub def setSkew(skew: Float64, path: Path2D): Path2D =
        let Path2D.Path2D(r) = path;
        Path2D.Path2D({ skew = skew | r })
}
