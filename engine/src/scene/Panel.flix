/// パネルノード（Godot Panel + StyleBoxFlat の最小組み合わせ）
/// see: https://docs.godotengine.org/en/stable/classes/class_panel.html
/// see: https://docs.godotengine.org/en/stable/classes/class_styleboxflat.html
///
/// 矩形領域に背景色と枠線を描く UI ノード。Godot では Panel + StyleBoxFlat
/// による Theme override で同等の見た目を作るが、テーマ機構は重いので
/// Flix では「背景色 + 枠線色 + 枠線太さ」だけを直接フィールドに持つ素朴版。
///
/// `toDrawables` は最大 5 枚の ColorRect 由来 Drawable を返す:
///   1. 背景（borderWidth ぶん内側に小さく描く形ではなく、size 全体を背景塗りつぶし）
///   2-5. 上/下/左/右 の枠線（borderWidth > 0 のときのみ）
///
/// 子ノードのレイアウトは持たない（必要なら親 Control + Layout.Anchor で配置する）。
///
///   Panel
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
///     +-- size, backgroundColor, backgroundAlpha, borderColor, borderAlpha, borderWidth
pub enum Panel {
    case Panel({
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color,
        size = Vec2.Vec2,
        backgroundColor = Color,
        backgroundAlpha = Float32,
        borderColor = Color,
        borderAlpha = Float32,
        borderWidth = Int32,
        // 角丸半径 (px)。0 で従来の直角 (5 矩形描画)。>0 で角丸スタイル描画 (1 Drawable)。
        cornerRadius = Float64
    })
}

mod Panel {
    /// 背景色のみ、枠線なしの最小コンストラクタ。
    pub def make(size: Vec2.Vec2, backgroundColor: Color): Panel =
        Panel.Panel({
            position = Vec2.zero(),
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            size = size,
            backgroundColor = backgroundColor,
            backgroundAlpha = 1.0f32,
            borderColor = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            borderAlpha = 1.0f32,
            borderWidth = 0,
            cornerRadius = 0.0
        })

    pub def getSize(panel: Panel): Vec2.Vec2 =
        let Panel.Panel(r) = panel;
        r#size

    pub def setSize(size: Vec2.Vec2, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({size = size | r})

    pub def setBackgroundColor(color: Color, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({backgroundColor = color | r})

    pub def getBackgroundColor(panel: Panel): Color =
        let Panel.Panel(r) = panel;
        r#backgroundColor

    pub def setBackgroundAlpha(alpha: Float32, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({backgroundAlpha = alpha | r})

    pub def getBackgroundAlpha(panel: Panel): Float32 =
        let Panel.Panel(r) = panel;
        r#backgroundAlpha

    pub def setBorderColor(color: Color, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({borderColor = color | r})

    pub def getBorderColor(panel: Panel): Color =
        let Panel.Panel(r) = panel;
        r#borderColor

    pub def setBorderAlpha(alpha: Float32, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({borderAlpha = alpha | r})

    pub def getBorderAlpha(panel: Panel): Float32 =
        let Panel.Panel(r) = panel;
        r#borderAlpha

    /// 枠線の太さ（px）。0 なら枠線描画なし。
    pub def setBorderWidth(width: Int32, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({borderWidth = Int32.max(0, width) | r})

    /// 角丸半径 (px) を設定する。0 で直角。
    pub def setCornerRadius(radius: Float64, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({cornerRadius = Float64.max(0.0, radius) | r})

    /// 角丸半径 (px) を取得する。
    pub def getCornerRadius(panel: Panel): Float64 =
        let Panel.Panel(r) = panel;
        r#cornerRadius

    pub def getBorderWidth(panel: Panel): Int32 =
        let Panel.Panel(r) = panel;
        r#borderWidth

    /// 単色矩形 1 枚分の Drawable を組み立てる。texture="" でテクスチャ無し。
    /// `pos` は左上、`size` は描画矩形。
    def makeRectDrawable(pos: Vec2.Vec2, size: Vec2.Vec2, color: Color,
                         alpha: Float32, zIndex: Int32): GameEngine.Drawable =
        {
            texture = "",
            position = pos,
            scale = size,
            rotation = 0.0,
            color = color,
            alpha = alpha,
            centered = false,
            uvOffset = {x = 0.0, y = 0.0},
            uvScale = {x = 1.0, y = 1.0},
            zIndex = zIndex,
            style = None
        }

    /// 背景 + 枠線 4 辺を Drawable リストとして返す。
    /// cornerRadius > 0 のときは「塗り＋枠＋角丸＋AA」を 1 フラグメントで描く styled Drawable 1 枚を返す
    /// （半透明でも枠/塗りが排他描画され二重合成しない）。cornerRadius = 0 のときは従来の最大 5 矩形。
    pub def toDrawables(panel: Panel, globalPos: Vec2.Vec2): List[GameEngine.Drawable] =
        let Panel.Panel(r) = panel;
        let w = r#size#x;
        let h = r#size#y;
        // 背景 Drawable は全分岐で共有（角丸時は style を載せ替えるだけ＝重複リテラルを持たない）。
        let bg = makeRectDrawable(globalPos, r#size, r#backgroundColor, r#backgroundAlpha, r#zIndex);
        if (r#cornerRadius > 0.0)
            // 角丸時: 1 枚で塗り＋枠＋角丸＋AA を排他描画（半透明でも二重合成しない）。
            ({style = Some({cornerRadius = r#cornerRadius,
                            borderWidth = Int32.toFloat64(r#borderWidth),
                            borderColor = r#borderColor,
                            borderAlpha = r#borderAlpha}) | bg}: GameEngine.Drawable) :: Nil
        else if (r#borderWidth <= 0)
            bg :: Nil
        else {
            let bw = Int32.toFloat64(r#borderWidth);
            let bc = r#borderColor;
            let ba = r#borderAlpha;
            let zi = r#zIndex;
            // 上辺 / 下辺 / 左辺 / 右辺（背景の上に同 z で重ねる）。
            let top = makeRectDrawable(globalPos, {x = w, y = bw}, bc, ba, zi);
            let bot = makeRectDrawable(
                {x = globalPos#x, y = globalPos#y + h - bw},
                {x = w, y = bw}, bc, ba, zi);
            let lft = makeRectDrawable(globalPos, {x = bw, y = h}, bc, ba, zi);
            let rgt = makeRectDrawable(
                {x = globalPos#x + w - bw, y = globalPos#y},
                {x = bw, y = h}, bc, ba, zi);
            bg :: top :: bot :: lft :: rgt :: Nil
        }

    /// path 位置に Panel が居れば取り出す（Godot の `GetNode<Panel>(path)` 相当）。
    /// 別ノードや欠落なら `None`。
    pub def getAt(path: NodePath, scene: Scene[s]): Option[Panel] =
        match Scene.getEngineNode(path, scene) {
            case Some(EngineNode.PanelWithState(panel, _)) => Some(panel)
            case _                                          => None
        }

    /// path 位置の Panel に f を適用。state タグは保持される。
    /// path に Panel が居なければ no-op。
    pub def mapAt(path: NodePath, f: Panel -> Panel,
                   scene: Scene[s]): Scene[s] =
        Scene.mapEngineNode(path, node -> match node {
            case EngineNode.PanelWithState(panel, tag) =>
                EngineNode.PanelWithState(f(panel), tag)
            case other => other
        }, scene)
}

// ── CanvasItem 実装 ──

instance CanvasItem[Panel] {
    pub def isVisible(panel: Panel): Bool =
        let Panel.Panel(r) = panel;
        r#visible
    pub def setVisible(visible: Bool, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({visible = visible | r})
    pub def getModulate(panel: Panel): Color =
        let Panel.Panel(r) = panel;
        r#modulate
    pub def setModulate(color: Color, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({modulate = color | r})
    pub def getZIndex(panel: Panel): Int32 =
        let Panel.Panel(r) = panel;
        r#zIndex
    pub def setZIndex(zIndex: Int32, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({zIndex = zIndex | r})
}

// ── Node2D 実装 ──

instance Node2D[Panel] {
    pub def getPosition(panel: Panel): Vec2.Vec2 =
        let Panel.Panel(r) = panel;
        r#position
    pub def setPosition(position: Vec2.Vec2, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({position = position | r})
    pub def getRotation(panel: Panel): Float64 =
        let Panel.Panel(r) = panel;
        r#rotation
    pub def setRotation(rotation: Float64, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({rotation = rotation | r})
    pub def getScale(panel: Panel): Vec2.Vec2 =
        let Panel.Panel(r) = panel;
        r#scale
    pub def setScale(scale: Vec2.Vec2, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({scale = scale | r})
    pub def getSkew(panel: Panel): Float64 =
        let Panel.Panel(r) = panel;
        r#skew
    pub def setSkew(skew: Float64, panel: Panel): Panel =
        let Panel.Panel(r) = panel;
        Panel.Panel({skew = skew | r})
}
