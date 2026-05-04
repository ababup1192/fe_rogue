/// キャンバスレイヤーノード（Godot CanvasLayer 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_canvaslayer.html
///
/// 子ノードを独立した描画レイヤーに配置するノード。
/// HUD・メニュー・背景など、メインシーンの座標系から独立した描画に使う。
///
/// Godot 準拠の挙動:
///   - 親の座標チェーンを断ち切り、offset をスクリーン座標の基点とする
///   - layer 値でレイヤー間の描画順を制御する（大きいほど前面）
///   - visible=false で子ノードを一括非表示にする
///   - CanvasLayer 自体は描画されない
///
///   CanvasLayer
///     +-- CanvasItem: visible, zIndex, modulate
///     +-- Node2D: position(=offset), rotation, scale, skew
pub enum CanvasLayer {
    case CanvasLayer({
        drawLayer = Int32,
        followViewport = Bool,
        position = Vec2.Vec2,
        rotation = Float64,
        scale = Vec2.Vec2,
        skew = Float64,
        visible = Bool,
        zIndex = Int32,
        modulate = Color
    })
}

mod CanvasLayer {

    /// レイヤー間の z-index ストライド
    /// 各レイヤーの子ノードの z-index に layer * layerStride を加算する
    pub def layerStride(): Int32 = 10000

    /// デフォルト値で CanvasLayer を生成する
    /// Godot 準拠で layer のデフォルトは 1
    pub def make(dl: Int32): CanvasLayer =
        CanvasLayer.CanvasLayer({
            drawLayer = dl,
            followViewport = false,
            position = Vec2.zero(),
            rotation = 0.0,
            scale = {x = 1.0, y = 1.0},
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
        })

    /// レイヤー番号を取得する
    pub def getDrawLayer(canvasLayer: CanvasLayer): Int32 =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        r#drawLayer

    /// レイヤー番号を設定する
    pub def setDrawLayer(dl: Int32, canvasLayer: CanvasLayer): CanvasLayer =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        CanvasLayer.CanvasLayer({ drawLayer = dl | r })

    /// レイヤーのオフセットを取得する（Node2D.getPosition と同義）
    pub def getOffset(canvasLayer: CanvasLayer): Vec2.Vec2 =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        r#position

    /// レイヤーのオフセットを設定する（Node2D.setPosition と同義）
    pub def setOffset(offset: Vec2.Vec2, canvasLayer: CanvasLayer): CanvasLayer =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        CanvasLayer.CanvasLayer({ position = offset | r })

    /// ビューポート追従フラグを取得する
    pub def isFollowViewport(canvasLayer: CanvasLayer): Bool =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        r#followViewport

    /// ビューポート追従フラグを設定する
    pub def setFollowViewport(followViewport: Bool, canvasLayer: CanvasLayer): CanvasLayer =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        CanvasLayer.CanvasLayer({ followViewport = followViewport | r })
}

// -- CanvasItem 実装 --

instance CanvasItem[CanvasLayer] {
    pub def isVisible(canvasLayer: CanvasLayer): Bool =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        r#visible
    pub def setVisible(visible: Bool, canvasLayer: CanvasLayer): CanvasLayer =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        CanvasLayer.CanvasLayer({ visible = visible | r })
    pub def getModulate(canvasLayer: CanvasLayer): Color =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        r#modulate
    pub def setModulate(color: Color, canvasLayer: CanvasLayer): CanvasLayer =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        CanvasLayer.CanvasLayer({ modulate = color | r })
    pub def getZIndex(canvasLayer: CanvasLayer): Int32 =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        r#zIndex
    pub def setZIndex(zIndex: Int32, canvasLayer: CanvasLayer): CanvasLayer =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        CanvasLayer.CanvasLayer({ zIndex = zIndex | r })
}

// -- Node2D 実装 --

instance Node2D[CanvasLayer] {
    pub def getPosition(canvasLayer: CanvasLayer): Vec2.Vec2 =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        r#position
    pub def setPosition(position: Vec2.Vec2, canvasLayer: CanvasLayer): CanvasLayer =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        CanvasLayer.CanvasLayer({ position = position | r })
    pub def getRotation(canvasLayer: CanvasLayer): Float64 =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        r#rotation
    pub def setRotation(rotation: Float64, canvasLayer: CanvasLayer): CanvasLayer =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        CanvasLayer.CanvasLayer({ rotation = rotation | r })
    pub def getScale(canvasLayer: CanvasLayer): Vec2.Vec2 =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        r#scale
    pub def setScale(scale: Vec2.Vec2, canvasLayer: CanvasLayer): CanvasLayer =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        CanvasLayer.CanvasLayer({ scale = scale | r })
    pub def getSkew(canvasLayer: CanvasLayer): Float64 =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        r#skew
    pub def setSkew(skew: Float64, canvasLayer: CanvasLayer): CanvasLayer =
        let CanvasLayer.CanvasLayer(r) = canvasLayer;
        CanvasLayer.CanvasLayer({ skew = skew | r })
}
