/// Marker2D — 位置だけを保持する、それ自身は描画されないノード。
/// 「ここが基準点」という座標に名前を付けて置けるので、生成位置や狙う先を一箇所で参照できる。
/// 利用例: 敵のスポーン地点、弾の発射位置、カメラの注視点。
///
///   Marker2D
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position, rotation, scale, skew
pub enum Marker2D {
    case Marker2D({
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color,
        ySortEnabled = Bool       // CanvasItem: 子を global_y で並べる
    })
}

mod Marker2D {
    /// デフォルト値で Marker2D を生成する。
    /// visible の既定は true。Marker2D 自身は描画されないが、可視性は子へ伝播する
    /// （`drawContextWalk` の AND）ため、false にすると子ノードごと描画されなくなる。
    pub def make(position: Vec2.Vec2): Marker2D =
        Marker2D.Marker2D({
            position = position,
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            ySortEnabled = false
        })

    /// path 位置の Marker2D に f を適用。state タグは保持される。
    /// path に Marker2D が居なければ no-op。（Sprite2D.mapAt と同形の typed accessor）
    pub def mapAt(path: NodePath, f: Marker2D -> Marker2D,
                   scene: Scene[s]): Scene[s] =
        Scene.mapEngineNode(path, node -> match node {
            case EngineNode.Marker2DWithState(marker, tag) =>
                EngineNode.Marker2DWithState(f(marker), tag)
            case other => other
        }, scene)

    /// path 位置の Marker2D に対し、内部ノードと state を同時に更新する f を適用。
    /// path に Marker2D が居なければ no-op。（内部だけなら mapAt を使う）
    pub def mapAtWithState(path: NodePath, f: (Marker2D, s) -> (Marker2D, s),
                            scene: Scene[s]): Scene[s] =
        Scene.mapEngineNode(path, node -> match node {
            case EngineNode.Marker2DWithState(marker, tag) =>
                let (newMarker, newTag) = f(marker, tag);
                EngineNode.Marker2DWithState(newMarker, newTag)
            case other => other
        }, scene)
}

// -- CanvasItem 実装 --

instance CanvasItem[Marker2D] {
    pub def isVisible(marker: Marker2D): Bool =
        let Marker2D.Marker2D(r) = marker;
        r#visible
    pub def setVisible(visible: Bool, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ visible = visible | r })
    pub def getModulate(marker: Marker2D): Color =
        let Marker2D.Marker2D(r) = marker;
        r#modulate
    pub def setModulate(color: Color, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ modulate = color | r })
    pub def getZIndex(marker: Marker2D): Int32 =
        let Marker2D.Marker2D(r) = marker;
        r#zIndex
    pub def setZIndex(zIndex: Int32, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ zIndex = zIndex | r })
    redef isYSortEnabled(marker: Marker2D): Bool =
        let Marker2D.Marker2D(r) = marker;
        r#ySortEnabled
    redef setYSortEnabled(v: Bool, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ ySortEnabled = v | r })
}

// -- Node2D 実装 --

instance Node2D[Marker2D] {
    pub def getPosition(marker: Marker2D): Vec2.Vec2 =
        let Marker2D.Marker2D(r) = marker;
        r#position
    pub def setPosition(position: Vec2.Vec2, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ position = position | r })
    pub def getRotation(marker: Marker2D): Float64 =
        let Marker2D.Marker2D(r) = marker;
        r#rotation
    pub def setRotation(rotation: Float64, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ rotation = rotation | r })
    pub def getScale(marker: Marker2D): Vec2.Vec2 =
        let Marker2D.Marker2D(r) = marker;
        r#scale
    pub def setScale(scale: Vec2.Vec2, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ scale = scale | r })
    pub def getSkew(marker: Marker2D): Float64 =
        let Marker2D.Marker2D(r) = marker;
        r#skew
    pub def setSkew(skew: Float64, marker: Marker2D): Marker2D =
        let Marker2D.Marker2D(r) = marker;
        Marker2D.Marker2D({ skew = skew | r })
}
