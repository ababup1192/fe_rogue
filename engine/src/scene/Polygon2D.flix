/// Polygon2D — 局所座標の凸多角形 `points` を単色（modulate + alpha）で塗り潰すノード。
/// 三角形や円などの簡単な図形を画像なしで出せるので、マーカーや図形エフェクトに手軽。
/// 利用例: 円形マーカー、簡易的な図形の演出。
/// 注意: テクスチャ・穴あき・UV は未対応（凸多角形を三角形ファンで塗る最小実装）。円は `circle` で 12 角形として生成する。
///
///   Polygon2D
///     +-- CanvasItem: visible, zIndex, modulate, alpha
///     +-- Node2D: position, rotation, scale, skew
pub enum Polygon2D {
    case Polygon2D({
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color,
        alpha = Float32,
        points = List[Vec2.Vec2]   // 局所座標の頂点列（凸・順序付き）
    })
}

mod Polygon2D {

    /// 任意の頂点列から Polygon2D を生成する（alpha=1.0 不透明）。
    pub def make(points: List[Vec2.Vec2], color: Color): Polygon2D =
        Polygon2D.Polygon2D({
            position = {x = 0.0, y = 0.0},
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = color,
            alpha = 1.0f32,
            points = points
        })

    /// 半径 `radius`（px）の円を 12 角形として生成する。小さなマーカーには十分滑らか。
    pub def circle(radius: Float64, color: Color): Polygon2D =
        make(unitCircle12() |> List.map(p -> ({x = p#x * radius, y = p#y * radius}: Vec2.Vec2)),
             color)

    /// 単位円上の 12 点（30°刻み）。engine に三角関数 FFI を持ち込まないための定数テーブル。
    pub def unitCircle12(): List[Vec2.Vec2] =
        let h = 0.8660254037844387;  // cos 30° = sin 60°
        let half = 0.5;
        ({x = 1.0,        y = 0.0}: Vec2.Vec2) ::
        ({x = h,          y = half}: Vec2.Vec2) ::
        ({x = half,       y = h}: Vec2.Vec2) ::
        ({x = 0.0,        y = 1.0}: Vec2.Vec2) ::
        ({x = 0.0 - half, y = h}: Vec2.Vec2) ::
        ({x = 0.0 - h,    y = half}: Vec2.Vec2) ::
        ({x = 0.0 - 1.0,  y = 0.0}: Vec2.Vec2) ::
        ({x = 0.0 - h,    y = 0.0 - half}: Vec2.Vec2) ::
        ({x = 0.0 - half, y = 0.0 - h}: Vec2.Vec2) ::
        ({x = 0.0,        y = 0.0 - 1.0}: Vec2.Vec2) ::
        ({x = half,       y = 0.0 - h}: Vec2.Vec2) ::
        ({x = h,          y = 0.0 - half}: Vec2.Vec2) :: Nil

    pub def getPoints(poly: Polygon2D): List[Vec2.Vec2] =
        let Polygon2D.Polygon2D(r) = poly;
        r#points

    pub def setPoints(points: List[Vec2.Vec2], poly: Polygon2D): Polygon2D =
        let Polygon2D.Polygon2D(r) = poly;
        Polygon2D.Polygon2D({points = points | r})

    pub def setAlpha(alpha: Float32, poly: Polygon2D): Polygon2D =
        let Polygon2D.Polygon2D(r) = poly;
        Polygon2D.Polygon2D({alpha = alpha | r})

    /// スクリーン px の塗り潰しコマンドに変換する。`screenPos` はノードの描画原点
    /// （カメラ/CanvasLayer 適用後）、`scaleVec` はワールドの zoom 倍率（CanvasLayer 下は (1,1)）。
    /// 頂点 = screenPos + 局所点 * scaleVec * ノード scale。回転/skew は未適用。
    pub def toRenderCmd(screenPos: Vec2.Vec2, scaleVec: Vec2.Vec2,
                         poly: Polygon2D): GameEngine.PolygonRenderCmd =
        let Polygon2D.Polygon2D(r) = poly;
        let sx = scaleVec#x * r#scale#x;
        let sy = scaleVec#y * r#scale#y;
        let verts = r#points |> List.map(p ->
            ({x = screenPos#x + p#x * sx, y = screenPos#y + p#y * sy}: Vec2.Vec2));
        {vertices = verts, color = r#modulate, alpha = r#alpha, zIndex = r#zIndex}
}

// -- CanvasItem 実装 --

instance CanvasItem[Polygon2D] {
    pub def isVisible(poly: Polygon2D): Bool =
        let Polygon2D.Polygon2D(r) = poly; r#visible
    pub def setVisible(visible: Bool, poly: Polygon2D): Polygon2D =
        let Polygon2D.Polygon2D(r) = poly;
        Polygon2D.Polygon2D({visible = visible | r})
    pub def getModulate(poly: Polygon2D): Color =
        let Polygon2D.Polygon2D(r) = poly; r#modulate
    pub def setModulate(color: Color, poly: Polygon2D): Polygon2D =
        let Polygon2D.Polygon2D(r) = poly;
        Polygon2D.Polygon2D({modulate = color | r})
    pub def getZIndex(poly: Polygon2D): Int32 =
        let Polygon2D.Polygon2D(r) = poly; r#zIndex
    pub def setZIndex(zIndex: Int32, poly: Polygon2D): Polygon2D =
        let Polygon2D.Polygon2D(r) = poly;
        Polygon2D.Polygon2D({zIndex = zIndex | r})
}

// -- Node2D 実装 --

instance Node2D[Polygon2D] {
    pub def getPosition(poly: Polygon2D): Vec2.Vec2 =
        let Polygon2D.Polygon2D(r) = poly; r#position
    pub def setPosition(position: Vec2.Vec2, poly: Polygon2D): Polygon2D =
        let Polygon2D.Polygon2D(r) = poly;
        Polygon2D.Polygon2D({position = position | r})
    pub def getRotation(poly: Polygon2D): Float64 =
        let Polygon2D.Polygon2D(r) = poly; r#rotation
    pub def setRotation(rotation: Float64, poly: Polygon2D): Polygon2D =
        let Polygon2D.Polygon2D(r) = poly;
        Polygon2D.Polygon2D({rotation = rotation | r})
    pub def getScale(poly: Polygon2D): Vec2.Vec2 =
        let Polygon2D.Polygon2D(r) = poly; r#scale
    pub def setScale(scale: Vec2.Vec2, poly: Polygon2D): Polygon2D =
        let Polygon2D.Polygon2D(r) = poly;
        Polygon2D.Polygon2D({scale = scale | r})
    pub def getSkew(poly: Polygon2D): Float64 =
        let Polygon2D.Polygon2D(r) = poly; r#skew
    pub def setSkew(skew: Float64, poly: Polygon2D): Polygon2D =
        let Polygon2D.Polygon2D(r) = poly;
        Polygon2D.Polygon2D({skew = skew | r})
}
