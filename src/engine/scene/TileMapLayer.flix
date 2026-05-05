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
        gridSize = Vec2.Vec2i,        // マップのグリッド寸法（__cWid, __cHei）
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
                            collisionCells = List[Vec2.Vec2],
                            gridSize = Vec2.Vec2i }): TileMapLayer =
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
            gridSize       = config#gridSize,
            tileVaoId      = 0,
            tileCount      = 0
        })

    // ────────────────────────────────────────────────────────
    // Godot TileMapLayer 準拠のクエリ API
    // ────────────────────────────────────────────────────────

    /// Godot: tile_set.tile_size のショートカット（タイル正方形）
    pub def tileSize(tileMap: TileMapLayer): Float64 =
        let TileMapLayer.TileMapLayer(r) = tileMap;
        TileSet.tileSize(r#tileSet)

    /// Godot: get_used_rect()
    /// position は (0,0) 固定（LDTK は座標オフセット無し）、size は gridSize
    pub def getUsedRect(tileMap: TileMapLayer):
            { position = Vec2.Vec2i, size = Vec2.Vec2i } =
        let TileMapLayer.TileMapLayer(r) = tileMap;
        { position = Vec2.zeroI(), size = r#gridSize }

    /// Godot: map_to_local(coords)
    /// グリッド座標 → セル中心のローカルピクセル座標
    /// world 座標が必要な場合は呼び出し側で
    ///   Vec2.add(Scene.globalPositionAt(path, scene), local)
    /// と合成する（Godot で言う to_global(local)）
    pub def mapToLocal(coords: Vec2.Vec2i, tileMap: TileMapLayer): Vec2.Vec2 =
        let s = tileSize(tileMap);
        let v = Vec2.fromI(coords);
        { x = v#x * s + s / 2.0,
          y = v#y * s + s / 2.0 }

    /// Godot: local_to_map(local_position)
    /// ローカルピクセル座標 → グリッド座標。範囲外でも値を返す（負値あり得る）。
    /// floor 切り捨てを使い、負値でも正しい結果になる
    /// （truncate だと -0.5 → 0、floor なら -1 が正解）。
    pub def localToMap(localPos: Vec2.Vec2, tileMap: TileMapLayer): Vec2.Vec2i =
        let s = tileSize(tileMap);
        Vec2.toIFloor(Vec2.div(localPos, s))

    /// Godot: get_cell_source_id(coords)
    /// 空セル（範囲外含む）: -1
    /// 壁セル: 0（本プロジェクトは intGrid 二値構造、source は 1 種類のみ）
    pub def getCellSourceId(coords: Vec2.Vec2i, tileMap: TileMapLayer): Int32 =
        let TileMapLayer.TileMapLayer(r) = tileMap;
        if (not isInBounds(coords, tileMap)) -1
        else
            let target = Vec2.fromI(coords);
            if (List.exists(c -> c#x == target#x and c#y == target#y, r#collisionCells))
                0
            else
                -1

    // ── Godot 拡張（本プロジェクト固有の便宜 API）──

    /// 範囲チェック: getUsedRect 内に収まるか
    pub def isInBounds(coords: Vec2.Vec2i, tileMap: TileMapLayer): Bool =
        let TileMapLayer.TileMapLayer(r) = tileMap;
        coords#x >= 0 and coords#x < r#gridSize#x and
        coords#y >= 0 and coords#y < r#gridSize#y

    /// 衝突セルか（getCellSourceId(coords, layer) != -1 の薄いラッパ）
    pub def isWall(coords: Vec2.Vec2i, tileMap: TileMapLayer): Bool =
        getCellSourceId(coords, tileMap) != -1

    /// 範囲内 かつ 壁でない ⇒ 床
    pub def isFloor(coords: Vec2.Vec2i, tileMap: TileMapLayer): Bool =
        isInBounds(coords, tileMap) and not isWall(coords, tileMap)

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
