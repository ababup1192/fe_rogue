// TileScene.toItems（CPU 投影）の置き場所を固定する。GPU 経路（TileLayer）は UV だけ
// 反転してマスの位置を動かさないので、CPU 投影も同じでなければ、実機の絵とヘッドレスの
// 描き出し・F8 の凍結画面が反転タイルのぶんだけ食い違う。
mod TestTileScene {

    def atlas(): Tileset =
        Tileset.make({ textureName = "tiles", texWidth = 64.0, texHeight = 64.0,
                       tileSize = 16.0, marginX = 0.0, marginY = 0.0,
                       spacingX = 0.0, spacingY = 0.0 })

    def specOf(flipH: Bool): TileLayerSpec =
        { key = "test", tileSet = atlas(), origin = { x = 100.0, y = 50.0 }, zIndex = 3,
          tiles = () -> ({ px = { x = 32.0, y = 16.0 }, srcX = 0.0, srcY = 0.0,
                           flipH = flipH, flipV = false, alpha = 1.0,
                           tint = TileLayer.noTint() }: TileData) :: Nil }

    def atOf(flipH: Bool): Option[(Float64, Float64)] =
        TileScene.toItems(specOf(flipH))
            |> List.head
            |> Option.map(p -> (p#at#x, p#at#y))

    /// マスの左上 = origin + px。反転しても同じ（覆う範囲は at から右下へ 1 マス）。
    @Test
    def testFlipKeepsTheTilePosition(): Unit \ Assert =
        Assert.assertEq(expected = (Some((132.0, 66.0)), Some((132.0, 66.0))),
            (atOf(false), atOf(true)))
}
