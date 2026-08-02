/// `.map.json` 由来のタイルデータを GPU インスタンス (`TileInstance`) に変換するための
/// 汎用ヘルパ。フォーマット非依存 — `TileData` のリストと texture 情報があれば動く。
///
/// 段階 4 の LDTK 削除に伴って engine の `LDTKLoader` から
/// `LDTKLevelRaw` / `LDTKLayerRaw` / `buildTileInstances` を fe_rogue 側に切り出して
/// `TileLevelRaw` / `TileLayerRaw` / `buildTileInstances` にリネームした。
mod TileRendering {

    /// 装飾レイヤー（Floor 等）の生データ。collision / door は Wall 専用なので含まない。
    /// tile の `src` は MapLoader 側で margin/spacing 込みで計算済みのため
    /// シェーダーへはそのまま渡せる。
    pub type alias TileLayerRaw = {
        tiles    = List[TileData],
        tileSet  = Tileset,
        gridSize = {x = Int32, y = Int32},
        tileSize = Float64
    }

    /// GPU アップロード前の生データ。複数モジュールを `DungeonComposer` で 1 枚にマージする際に使う。
    /// `tileSize` は描画 / 座標換算で繰り返し参照するので展開済みで持つ
    /// (`tileSet#atlasSource#tileSize` と同値)。
    pub type alias TileLevelRaw = {
        tiles          = List[TileData],
        collisionCells = List[Vec2.Vec2],
        doors          = List[{x = Int32, y = Int32}],
        tileSet        = Tileset,
        gridSize       = {x = Int32, y = Int32},
        tileSize       = Float64
    }

    /// TileData のリストを GPU インスタンス (TileInstance) のリストに変換する。
    /// MapLoader / DungeonComposer / MapSetup の各レンダリング経路で共有する。
    /// 実体はエンジンの TileLayer.buildInstances（half-texel inset 込み）。
    pub def buildTileInstances(tiles: List[TileData],
                                tileSet: Tileset,
                                tileSize: Float64): List[GameEngine.TileInstance] =
        TileLayer.buildInstances(tiles, tileSet, tileSize)
}
