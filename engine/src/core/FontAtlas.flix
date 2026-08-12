// FontAtlas — フォントアトラス型定義
// STBTruetype で生成したフォントビットマップのメタデータを保持する

/// フォントアトラス: テクスチャ名 + グリフメトリクスマップ
pub type alias FontAtlas = {
    textureName = String,
    fontSize = Float64,
    textureSize = Float64,
    ascent = Float64,
    descent = Float64,
    lineGap = Float64,
    glyphs = Map[Int32, TextLayout.GlyphMetrics]
}
