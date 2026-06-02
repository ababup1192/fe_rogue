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
        tileSet  = TileSet,
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
        tileSet        = TileSet,
        gridSize       = {x = Int32, y = Int32},
        tileSize       = Float64
    }

    /// TileData のリストを GPU インスタンス (TileInstance) のリストに変換する。
    /// UV は texture サイズと flipH/flipV から計算する。
    /// MapLoader / DungeonComposer / MapScene の各レンダリング経路で共有する。
    pub def buildTileInstances(tiles: List[TileData],
                                tileSet: TileSet,
                                tileSize: Float64): List[GameEngine.TileInstance] =
        let texWidth  = tileSet#atlasSource#texWidth;
        let texHeight = tileSet#atlasSource#texHeight;
        // UV は各 texel の中心 (src + 0.5 .. src + tileSize - 0.5) を結ぶように
        // half-texel inset する。アトラスがタイル間 padding なしで密パックされているため、
        // 境界そのまま (src .. src + tileSize) を UV にすると、シェーダ内補間の浮動小数
        // 誤差で隣接タイルの最初の 1 texel を拾い、タイル境界に細い線として現れる。
        let inset = 0.5;
        List.map(tile -> {
            let uvoX = if (tile#flipH) (tile#srcX + tileSize - inset) / texWidth
                       else            (tile#srcX + inset) / texWidth;
            let uvoY = if (tile#flipV) (tile#srcY + tileSize - inset) / texHeight
                       else            (tile#srcY + inset) / texHeight;
            let uvsX = if (tile#flipH) -((tileSize - 2.0 * inset) / texWidth)
                       else            (tileSize - 2.0 * inset) / texWidth;
            let uvsY = if (tile#flipV) -((tileSize - 2.0 * inset) / texHeight)
                       else            (tileSize - 2.0 * inset) / texHeight;
            ({
                px    = tile#px,
                uvOff = ({x = uvoX, y = uvoY}: Vec2.Vec2),
                uvSc  = ({x = uvsX, y = uvsY}: Vec2.Vec2),
                alpha = tile#alpha
            }: GameEngine.TileInstance)
        }, tiles)
}
