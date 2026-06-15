/// 円弧/リングノード（Godot CanvasItem.draw_arc 準拠の簡易版）
/// see: https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-method-draw-arc
///
/// 中心（ノード位置）から半径 `radius`（外周）・太さ `width` のリングを、`startAngle` から
/// `endAngle`（ラジアン、Godot draw_arc と同義で時計回りに増加・画面 +y は下向き）まで単色で塗る。
/// レンダラは塗り潰し凸ポリゴン（GL_TRIANGLE_FAN）しか持たないため、リングは中空円＝アヌラスとして
/// `segments` 個の凸クアッド（台形）に分割し、各セグメントを 1 つの PolygonRenderCmd として emit する。
/// クールダウン/タイマー表示は `endAngle` を毎フレーム更新して円弧を伸縮させる（駆動はゲーム側）。
///
///   Arc2D
///     +-- CanvasItem: visible, zIndex, modulate, alpha
///     +-- Node2D: position, rotation, scale, skew
pub enum Arc2D {
    case Arc2D({
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color,
        alpha = Float32,
        radius = Float64,      // 外周半径（px）
        width = Float64,       // リングの太さ（px）。内半径 = radius - width（0 未満は中心まで塗る扇形）
        startAngle = Float64,  // 円弧開始角（ラジアン）
        endAngle = Float64,    // 円弧終了角（ラジアン）。endAngle <= startAngle なら非描画
        segments = Int32       // 円弧の分割数（多いほど滑らか）
    })
}

mod Arc2D {

    /// 全周（2π）の既定分割数。小さなインジケータには十分滑らか。
    def defaultSegments(): Int32 = 32

    /// 全周 = 2π（ラジアン）。全周リングの endAngle 既定や、比率→角度の換算に使う。
    pub def tau(): Float64 = 6.283185307179586

    /// 半径・太さ・開始/終了角を指定して円弧を生成する（alpha=1.0 不透明、segments 既定）。
    pub def make(radius: Float64, width: Float64,
                 startAngle: Float64, endAngle: Float64, color: Color): Arc2D =
        Arc2D.Arc2D({
            position = {x = 0.0, y = 0.0},
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = color,
            alpha = 1.0f32,
            radius = radius,
            width = width,
            startAngle = startAngle,
            endAngle = endAngle,
            segments = defaultSegments()
        })

    /// 全周リング（startAngle=0, endAngle=2π）を生成するショートカット。背景の輪などに使う。
    pub def ring(radius: Float64, width: Float64, color: Color): Arc2D =
        make(radius, width, 0.0, tau(), color)

    pub def getRadius(arc: Arc2D): Float64 =
        let Arc2D.Arc2D(r) = arc; r#radius

    pub def setRadius(radius: Float64, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({radius = radius | r})

    pub def getWidth(arc: Arc2D): Float64 =
        let Arc2D.Arc2D(r) = arc; r#width

    pub def setWidth(width: Float64, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({width = width | r})

    pub def getStartAngle(arc: Arc2D): Float64 =
        let Arc2D.Arc2D(r) = arc; r#startAngle

    pub def setStartAngle(startAngle: Float64, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({startAngle = startAngle | r})

    pub def getEndAngle(arc: Arc2D): Float64 =
        let Arc2D.Arc2D(r) = arc; r#endAngle

    /// 円弧の終了角を更新する。クールダウンは `setEndAngle(start + 2π*ratio)` を毎フレーム呼ぶ。
    pub def setEndAngle(endAngle: Float64, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({endAngle = endAngle | r})

    pub def getSegments(arc: Arc2D): Int32 =
        let Arc2D.Arc2D(r) = arc; r#segments

    /// 分割数を設定する。1 未満は 1 にクランプ（state と描画を一致させる）。
    pub def setSegments(segments: Int32, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({segments = Int32.max(1, segments) | r})

    pub def getAlpha(arc: Arc2D): Float32 =
        let Arc2D.Arc2D(r) = arc; r#alpha

    pub def setAlpha(alpha: Float32, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({alpha = alpha | r})

    /// スクリーン px の塗り潰しコマンド列に変換する。`screenPos` はノードの描画原点
    /// （カメラ/CanvasLayer 適用後）、`scaleVec` はワールドの zoom 倍率（CanvasLayer 下は (1,1)）。
    /// 各クアッドの頂点 = screenPos + (cosθ, sinθ) * 半径 * scaleVec * ノード scale。回転/skew は未適用。
    /// 太さ 0 以下、または endAngle <= startAngle のときは空（非描画）。
    pub def toRenderCmds(screenPos: Vec2.Vec2, scaleVec: Vec2.Vec2,
                         arc: Arc2D): List[GameEngine.PolygonRenderCmd] =
        let Arc2D.Arc2D(r) = arc;
        let sweep = r#endAngle - r#startAngle;
        if (sweep <= 0.0 or r#width <= 0.0) Nil
        else {
            let sx = scaleVec#x * r#scale#x;
            let sy = scaleVec#y * r#scale#y;
            let outerR = r#radius;
            let innerR = Float64.max(0.0, r#radius - r#width);
            let n = Int32.max(1, r#segments);
            let step = sweep / Int32.toFloat64(n);
            let mkPt = (angle, radius) ->
                ({x = screenPos#x + RenderUtil.cosF(angle) * radius * sx,
                  y = screenPos#y + RenderUtil.sinF(angle) * radius * sy}: Vec2.Vec2);
            List.range(0, n) |> List.map(i -> {
                let a0 = r#startAngle + step * Int32.toFloat64(i);
                let a1 = r#startAngle + step * Int32.toFloat64(i + 1);
                let verts =
                    mkPt(a0, outerR) :: mkPt(a1, outerR) ::
                    mkPt(a1, innerR) :: mkPt(a0, innerR) :: Nil;
                ({vertices = verts, color = r#modulate, alpha = r#alpha,
                  zIndex = r#zIndex}: GameEngine.PolygonRenderCmd)
            })
        }
}

// -- CanvasItem 実装 --

instance CanvasItem[Arc2D] {
    pub def isVisible(arc: Arc2D): Bool =
        let Arc2D.Arc2D(r) = arc; r#visible
    pub def setVisible(visible: Bool, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({visible = visible | r})
    pub def getModulate(arc: Arc2D): Color =
        let Arc2D.Arc2D(r) = arc; r#modulate
    pub def setModulate(color: Color, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({modulate = color | r})
    pub def getZIndex(arc: Arc2D): Int32 =
        let Arc2D.Arc2D(r) = arc; r#zIndex
    pub def setZIndex(zIndex: Int32, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({zIndex = zIndex | r})
}

// -- Node2D 実装 --

instance Node2D[Arc2D] {
    pub def getPosition(arc: Arc2D): Vec2.Vec2 =
        let Arc2D.Arc2D(r) = arc; r#position
    pub def setPosition(position: Vec2.Vec2, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({position = position | r})
    pub def getRotation(arc: Arc2D): Float64 =
        let Arc2D.Arc2D(r) = arc; r#rotation
    pub def setRotation(rotation: Float64, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({rotation = rotation | r})
    pub def getScale(arc: Arc2D): Vec2.Vec2 =
        let Arc2D.Arc2D(r) = arc; r#scale
    pub def setScale(scale: Vec2.Vec2, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({scale = scale | r})
    pub def getSkew(arc: Arc2D): Float64 =
        let Arc2D.Arc2D(r) = arc; r#skew
    pub def setSkew(skew: Float64, arc: Arc2D): Arc2D =
        let Arc2D.Arc2D(r) = arc;
        Arc2D.Arc2D({skew = skew | r})
}
