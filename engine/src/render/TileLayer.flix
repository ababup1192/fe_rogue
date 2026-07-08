/// タイルマップレイヤー — 格子状に並べたタイルの層を 1 枚まとめて描く。
///
/// 大量のタイルを 1 回の描画でまとめて出せるので、床や壁のマップを軽く表示できる。
/// 利用例: ダンジョンの床・壁レイヤーを 1 枚として置く。
///
/// GPU インスタンシング（glDrawArraysInstanced）で全タイルを 1 draw call で描画する。
///
/// tileVaoId / tileCount は tilemap loader が initTileBuffer() で設定する。
/// 初期値 0 = 未初期化（GPU リソース未アップロード）。
pub enum TileLayer {
    case TileLayer({
        position = Vec2.Vec2,        // Node2D: 位置
        rotation = Float64,           // Node2D: 回転（ラジアン）
        scale = Vec2.Vec2,           // Node2D: スケール
        skew = Float64,               // Node2D: スキュー
        visible = Bool,               // CanvasItem: 表示フラグ
        zIndex = Int32,               // CanvasItem: 描画順
        modulate = Color,             // CanvasItem: 色変調
        tileSet = Tileset,            // タイルセット
        tiles = List[TileData],       // タイル一覧
        collisionCells = List[Vec2.Vec2], // 衝突グリッドセル
        gridSize = {x = Int32, y = Int32},        // マップのグリッド寸法（__cWid, __cHei）
        tileVaoId = Int32,            // GPU VAO ID（0 = 未初期化）
        tileCount = Int32,            // インスタンス数
        ySortEnabled = Bool           // CanvasItem: 子を global_y で並べる
    })
}

/// 1 タイルの描画情報（tilemap loader が tilemap tile データから生成する）
pub type alias TileData = {
    px    = Vec2.Vec2,
    srcX  = Float64,
    srcY  = Float64,
    flipH = Bool,
    flipV = Bool,
    alpha = Float32
}

mod TileLayer {

    /// TileLayer を TileMapRenderCmd に変換する（GameEngine.render 内で使用）。
    /// `position` は既にカメラ ViewTransform を適用したスクリーン座標、
    /// `tileScale` は ViewTransform.scale（zoom）。シェーダ側でタイル本体に乗算する
    pub def toRenderCmd(layerScreenPos: Vec2.Vec2, tileScale: Vec2.Vec2,
                         tileMap: TileLayer): GameEngine.TileMapRenderCmd =
        let TileLayer.TileLayer(r) = tileMap;
        let atlas = r#tileSet#atlasSource;
        { textureName = atlas#textureName,
          tileSize    = atlas#tileSize,
          position    = layerScreenPos,
          tileScale   = tileScale,
          color       = r#modulate,
          zIndex      = r#zIndex,
          tileVaoId   = r#tileVaoId,
          tileCount   = r#tileCount }

    /// デフォルト値で TileLayer を構築するビルドヘルパー
    pub def make(config: { tileSet = Tileset,
                            tiles = List[TileData],
                            collisionCells = List[Vec2.Vec2],
                            gridSize = {x = Int32, y = Int32} }): TileLayer =
        TileLayer.TileLayer({
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
            tileCount      = 0,
            ySortEnabled   = false
        })

    // ────────────────────────────────────────────────────────
    // タイル座標のクエリ API
    // ────────────────────────────────────────────────────────

    /// タイル 1 マスの一辺（ピクセル）のショートカット（タイル正方形）
    pub def tileSize(tileMap: TileLayer): Float64 =
        let TileLayer.TileLayer(r) = tileMap;
        Tileset.tileSize(r#tileSet)

    /// 使用中のマス範囲を矩形で返す。
    /// position は (0,0) 固定（LDTK は座標オフセット無し）、size は gridSize
    pub def getUsedRect(tileMap: TileLayer):
            { position = {x = Int32, y = Int32}, size = {x = Int32, y = Int32} } =
        let TileLayer.TileLayer(r) = tileMap;
        { position = Vec2i.zero(), size = r#gridSize }

    /// グリッド座標 → セル中心のローカルピクセル座標に変換する。
    /// world 座標が必要な場合は呼び出し側でレイヤーの原点を足し合わせる。
    pub def mapToLocal(coords: {x = Int32, y = Int32}, tileMap: TileLayer): Vec2.Vec2 =
        let s = tileSize(tileMap);
        let v = Vec2i.toVec2(coords);
        { x = v#x * s + s / 2.0,
          y = v#y * s + s / 2.0 }

    /// ローカルピクセル座標 → グリッド座標に変換する。範囲外でも値を返す（負値あり得る）。
    /// floor 切り捨てを使い、負値でも正しい結果になる
    /// （truncate だと -0.5 → 0、floor なら -1 が正解）。
    pub def localToMap(localPos: Vec2.Vec2, tileMap: TileLayer): {x = Int32, y = Int32} =
        let s = tileSize(tileMap);
        Vec2i.fromVec2Floor(Vec2.div(localPos, s))

    /// 指定マスのソース ID を返す。
    /// 空セル（範囲外含む）: -1
    /// 壁セル: 0（本プロジェクトは intGrid 二値構造、source は 1 種類のみ）
    pub def getCellSourceId(coords: {x = Int32, y = Int32}, tileMap: TileLayer): Int32 =
        let TileLayer.TileLayer(r) = tileMap;
        if (not isInBounds(coords, tileMap)) -1
        else
            let target = Vec2i.toVec2(coords);
            if (List.exists(c -> c#x == target#x and c#y == target#y, r#collisionCells))
                0
            else
                -1

    // ── 本プロジェクト固有の便宜 API ──

    /// 範囲チェック: getUsedRect 内に収まるか
    pub def isInBounds(coords: {x = Int32, y = Int32}, tileMap: TileLayer): Bool =
        let TileLayer.TileLayer(r) = tileMap;
        coords#x >= 0 and coords#x < r#gridSize#x and
        coords#y >= 0 and coords#y < r#gridSize#y

    /// 衝突セルか（getCellSourceId(coords, layer) != -1 の薄いラッパ）
    pub def isWall(coords: {x = Int32, y = Int32}, tileMap: TileLayer): Bool =
        getCellSourceId(coords, tileMap) != -1

    /// 範囲内 かつ 壁でない ⇒ 床
    pub def isFloor(coords: {x = Int32, y = Int32}, tileMap: TileLayer): Bool =
        isInBounds(coords, tileMap) and not isWall(coords, tileMap)

    /// GPU リソース ID を設定する（tilemap loader が initTileBuffer の結果を書き込む）
    pub def withGpuResources(tileVaoId: Int32, tileCount: Int32,
                              tileMap: TileLayer): TileLayer =
        let TileLayer.TileLayer(r) = tileMap;
        TileLayer.TileLayer({ tileVaoId = tileVaoId, tileCount = tileCount | r })
}

// ── CanvasItem 実装 ──

instance CanvasItem[TileLayer] {
    pub def isVisible(node: TileLayer): Bool =
        let TileLayer.TileLayer(r) = node; r#visible
    pub def setVisible(visible: Bool, node: TileLayer): TileLayer =
        let TileLayer.TileLayer(r) = node;
        TileLayer.TileLayer({ visible = visible | r })
    pub def getModulate(node: TileLayer): Color =
        let TileLayer.TileLayer(r) = node; r#modulate
    pub def setModulate(color: Color, node: TileLayer): TileLayer =
        let TileLayer.TileLayer(r) = node;
        TileLayer.TileLayer({ modulate = color | r })
    pub def getZIndex(node: TileLayer): Int32 =
        let TileLayer.TileLayer(r) = node; r#zIndex
    pub def setZIndex(zIndex: Int32, node: TileLayer): TileLayer =
        let TileLayer.TileLayer(r) = node;
        TileLayer.TileLayer({ zIndex = zIndex | r })
    redef isYSortEnabled(node: TileLayer): Bool =
        let TileLayer.TileLayer(r) = node; r#ySortEnabled
    redef setYSortEnabled(v: Bool, node: TileLayer): TileLayer =
        let TileLayer.TileLayer(r) = node;
        TileLayer.TileLayer({ ySortEnabled = v | r })
}

// ── Node2D 実装 ──

instance Node2D[TileLayer] {
    pub def getPosition(node: TileLayer): Vec2.Vec2 =
        let TileLayer.TileLayer(r) = node; r#position
    pub def setPosition(position: Vec2.Vec2, node: TileLayer): TileLayer =
        let TileLayer.TileLayer(r) = node;
        TileLayer.TileLayer({ position = position | r })
    pub def getRotation(node: TileLayer): Float64 =
        let TileLayer.TileLayer(r) = node; r#rotation
    pub def setRotation(rotation: Float64, node: TileLayer): TileLayer =
        let TileLayer.TileLayer(r) = node;
        TileLayer.TileLayer({ rotation = rotation | r })
    pub def getScale(node: TileLayer): Vec2.Vec2 =
        let TileLayer.TileLayer(r) = node; r#scale
    pub def setScale(scale: Vec2.Vec2, node: TileLayer): TileLayer =
        let TileLayer.TileLayer(r) = node;
        TileLayer.TileLayer({ scale = scale | r })
    pub def getSkew(node: TileLayer): Float64 =
        let TileLayer.TileLayer(r) = node; r#skew
    pub def setSkew(skew: Float64, node: TileLayer): TileLayer =
        let TileLayer.TileLayer(r) = node;
        TileLayer.TileLayer({ skew = skew | r })
}
