/// タイルマップレイヤー（Godot TileMapLayer 準拠）
///
/// GPU インスタンシング（glDrawArraysInstanced）で全タイルを 1 draw call で描画する。
/// 衝突セル（collisionCells）は PhysicsStep が仮想 StaticBody として展開する。
/// Scene に直接 TileMapLayerWithState として登録し、子ノードは一切持たない。
///
/// tileVaoId / tileCount は LDTKLoader.loadLevel() が initTileBuffer() で設定する。
/// 初期値 0 = 未初期化（GPU リソース未アップロード）。
pub enum TileMapLayer {
    case TileMapLayer({
        position = Vec2.Vec2,        // Node2D: 位置
        rotation = Float64,           // Node2D: 回転（ラジアン）
        scale = Vec2.Vec2,           // Node2D: スケール
        skew = Float64,               // Node2D: スキュー
        visible = Bool,               // CanvasItem: 表示フラグ
        zIndex = Int32,               // CanvasItem: 描画順
        modulate = Color,             // CanvasItem: 色変調
        tileSet = TileSet,            // タイルセット
        tiles = List[TileData],       // タイル一覧
        collisionCells = List[Vec2.Vec2], // 衝突グリッドセル
        tileVaoId = Int32,            // GPU VAO ID（0 = 未初期化）
        tileCount = Int32             // インスタンス数
    })
}

/// 1 タイルの描画情報（LDTKLoader が autoLayerTiles から生成する）
pub type alias TileData = {
    px    = Vec2.Vec2,
    srcX  = Float64,
    srcY  = Float64,
    flipH = Bool,
    flipV = Bool,
    alpha = Float32
}

mod TileMapLayer {

    /// TileMapLayer を TileMapRenderCmd に変換する（GameEngine.render 内で使用）。
    /// `position` は既にカメラ ViewTransform を適用したスクリーン座標、
    /// `tileScale` は ViewTransform.scale（zoom）。シェーダ側でタイル本体に乗算する
    pub def toRenderCmd(layerScreenPos: Vec2.Vec2, tileScale: Vec2.Vec2,
                         tileMap: TileMapLayer): GameEngine.TileMapRenderCmd =
        let TileMapLayer.TileMapLayer(r) = tileMap;
        let atlas = r#tileSet#atlasSource;
        { textureName = atlas#textureName,
          tileSize    = atlas#tileSize,
          position    = layerScreenPos,
          tileScale   = tileScale,
          color       = r#modulate,
          zIndex      = r#zIndex,
          tileVaoId   = r#tileVaoId,
          tileCount   = r#tileCount }

    /// 衝突セルを仮想 StaticBody2D 形状として展開する（PhysicsStep が使用）
    /// collisionCells はグリッド座標（col, row）で格納されている。
    pub def expandWallShapes(globalPos: Vec2.Vec2,
                              tileMap: TileMapLayer): List[(Vec2.Vec2, CollisionShape2D)] =
        let TileMapLayer.TileMapLayer(r) = tileMap;
        let s = r#tileSet#atlasSource#tileSize;
        List.map(cell -> {
            let center: Vec2.Vec2 = {
                x = globalPos#x + cell#x * s + s / 2.0,
                y = globalPos#y + cell#y * s + s / 2.0
            };
            (center, CollisionShape2D.RectShape2D({ width = s, height = s }))
        }, r#collisionCells)

    /// デフォルト値で TileMapLayer を構築するビルドヘルパー
    pub def make(config: { tileSet = TileSet,
                            tiles = List[TileData],
                            collisionCells = List[Vec2.Vec2] }): TileMapLayer =
        TileMapLayer.TileMapLayer({
            position       = Vec2.zero(),
            rotation       = 0.0,
            scale          = {x = 1.0, y = 1.0},
            skew           = 0.0,
            visible        = true,
            zIndex         = 0,
            modulate       = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            tileSet        = config#tileSet,
            tiles          = config#tiles,
            collisionCells = config#collisionCells,
            tileVaoId      = 0,
            tileCount      = 0
        })

    /// GPU リソース ID を設定する（LDTKLoader が initTileBuffer の結果を書き込む）
    pub def withGpuResources(tileVaoId: Int32, tileCount: Int32,
                              tileMap: TileMapLayer): TileMapLayer =
        let TileMapLayer.TileMapLayer(r) = tileMap;
        TileMapLayer.TileMapLayer({ tileVaoId = tileVaoId, tileCount = tileCount | r })
}

// ── CanvasItem 実装 ──

instance CanvasItem[TileMapLayer] {
    pub def isVisible(node: TileMapLayer): Bool =
        let TileMapLayer.TileMapLayer(r) = node; r#visible
    pub def setVisible(visible: Bool, node: TileMapLayer): TileMapLayer =
        let TileMapLayer.TileMapLayer(r) = node;
        TileMapLayer.TileMapLayer({ visible = visible | r })
    pub def getModulate(node: TileMapLayer): Color =
        let TileMapLayer.TileMapLayer(r) = node; r#modulate
    pub def setModulate(color: Color, node: TileMapLayer): TileMapLayer =
        let TileMapLayer.TileMapLayer(r) = node;
        TileMapLayer.TileMapLayer({ modulate = color | r })
    pub def getZIndex(node: TileMapLayer): Int32 =
        let TileMapLayer.TileMapLayer(r) = node; r#zIndex
    pub def setZIndex(zIndex: Int32, node: TileMapLayer): TileMapLayer =
        let TileMapLayer.TileMapLayer(r) = node;
        TileMapLayer.TileMapLayer({ zIndex = zIndex | r })
}

// ── Node2D 実装 ──

instance Node2D[TileMapLayer] {
    pub def getPosition(node: TileMapLayer): Vec2.Vec2 =
        let TileMapLayer.TileMapLayer(r) = node; r#position
    pub def setPosition(position: Vec2.Vec2, node: TileMapLayer): TileMapLayer =
        let TileMapLayer.TileMapLayer(r) = node;
        TileMapLayer.TileMapLayer({ position = position | r })
    pub def getRotation(node: TileMapLayer): Float64 =
        let TileMapLayer.TileMapLayer(r) = node; r#rotation
    pub def setRotation(rotation: Float64, node: TileMapLayer): TileMapLayer =
        let TileMapLayer.TileMapLayer(r) = node;
        TileMapLayer.TileMapLayer({ rotation = rotation | r })
    pub def getScale(node: TileMapLayer): Vec2.Vec2 =
        let TileMapLayer.TileMapLayer(r) = node; r#scale
    pub def setScale(scale: Vec2.Vec2, node: TileMapLayer): TileMapLayer =
        let TileMapLayer.TileMapLayer(r) = node;
        TileMapLayer.TileMapLayer({ scale = scale | r })
    pub def getSkew(node: TileMapLayer): Float64 =
        let TileMapLayer.TileMapLayer(r) = node; r#skew
    pub def setSkew(skew: Float64, node: TileMapLayer): TileMapLayer =
        let TileMapLayer.TileMapLayer(r) = node;
        TileMapLayer.TileMapLayer({ skew = skew | r })
}
