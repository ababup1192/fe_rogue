// GpuHandle — バックエンドが割り当てる描画リソースのハンドル。
//
// タイル VBO やテクスチャの実体（OpenGL の VAO/テクスチャ id など）を 1 枚の型で包む。
// フロントやゲームは中身を読まずに値として持ち運ぶだけで、中身の意味はバックエンド
// （render_gl など）だけが `*Int` で取り出して知る。バックエンドを差し替えても、
// ハンドルの中身の表現だけが変わり、運ぶ側のコードは変わらない。

mod GpuHandle {

    /// タイルマップの GPU インスタンスバッファのハンドル（`initTileBuffer` が返す）。
    pub enum TileVao { case TileVao(Int32) }

    /// テクスチャの GPU ハンドル。
    pub enum TextureId { case TextureId(Int32) }

    /// Int32 の実体をハンドルに包む（バックエンドが割り当て時に呼ぶ）。
    pub def wrapTileVao(v: Int32): TileVao = TileVao.TileVao(v)

    /// ハンドルから Int32 の実体を取り出す（バックエンドが描画時に呼ぶ）。
    pub def tileVaoInt(h: TileVao): Int32 = let TileVao.TileVao(v) = h; v

    /// Int32 の実体をハンドルに包む。
    pub def wrapTextureId(v: Int32): TextureId = TextureId.TextureId(v)

    /// ハンドルから Int32 の実体を取り出す。
    pub def textureIdInt(h: TextureId): Int32 = let TextureId.TextureId(v) = h; v

}
