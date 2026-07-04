/// タイルセットのアトラス元 — 1 枚のタイル画像と、そこからマスを切り出す設定。
/// texWidth / texHeight は tilemap loader 側で getTextureInfo() を呼んで自動補完する想定。
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

/// タイルセット — マップが使うタイル画像一式。
pub type alias TileSet = { atlasSource = TileSetAtlasSource }

mod TileSet {
    pub def make(source: TileSetAtlasSource): TileSet = { atlasSource = source }

    /// タイル 1 マスの一辺（ピクセル）。本プロジェクトはタイル正方形なので Float64 単一値
    pub def tileSize(tileSet: TileSet): Float64 =
        tileSet#atlasSource#tileSize
}

mod TileSetAtlasSource {
    /// margin/spacing のデフォルトを 0 として生成する。
    /// texWidth / texHeight / tileSize は tilemap loader が後から補完するため 0 で初期化する。
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
