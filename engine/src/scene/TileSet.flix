/// タイルセットアトラスソース（Godot TileSetAtlasSource 準拠）
/// texWidth / texHeight は LDTKLoader が getTextureInfo() で自動補完する。
/// tileSize は .ldtkl の __gridSize から自動補完する。
pub type alias TileSetAtlasSource = {
    textureName = String,
    texWidth    = Float64,
    texHeight   = Float64,
    tileSize    = Float64,
    marginX     = Float64,
    marginY     = Float64,
    spacingX    = Float64,
    spacingY    = Float64
}

/// タイルセット（Godot TileSet 準拠）
pub type alias TileSet = { atlasSource = TileSetAtlasSource }

mod TileSet {
    pub def make(source: TileSetAtlasSource): TileSet = { atlasSource = source }

    /// Godot: tile_set.tile_size。本プロジェクトはタイル正方形なので Float64 単一値
    pub def tileSize(tileSet: TileSet): Float64 =
        tileSet#atlasSource#tileSize
}

mod TileSetAtlasSource {
    /// margin/spacing のデフォルトを 0 として生成する。
    /// texWidth / texHeight / tileSize は LDTKLoader が後から補完するため 0 で初期化する。
    pub def make(config: { textureName = String,
                           marginX = Float64, marginY = Float64,
                           spacingX = Float64, spacingY = Float64 }): TileSetAtlasSource = {
        textureName = config#textureName,
        texWidth    = 0.0,
        texHeight   = 0.0,
        tileSize    = 0.0,
        marginX     = config#marginX,
        marginY     = config#marginY,
        spacingX    = config#spacingX,
        spacingY    = config#spacingY
    }
}
