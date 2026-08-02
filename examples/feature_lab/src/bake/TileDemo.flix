// TileDemo — タイル層の zIndex が動的な絵と同じ z 空間で解釈されることを、CPU 投影
// （TileScene.toItems）の 1 枚絵で確かめる場面。軒のタイル層（z=50）の下をキャラ（z=10）が
// くぐって上半身が隠れ、床のタイル層（z=0）はキャラの奥に敷かれる。比較用に、帯の外に
// 全身が見えるキャラをもう 1 体置く。
// 出力: debug/tile_front_demo.png（golden の外。目視専用）

mod TileDemo {

    def atlasName(): String = "tile_demo_atlas"
    def atlasSide(): Int32 = 32
    def tile(): Float64 = 16.0

    def argb(a: Int32, r: Int32, g: Int32, b: Int32): Int32 =
        Int32.leftShift(a, 24)
            |> Int32.bitwiseOr(Int32.leftShift(r, 16))
            |> Int32.bitwiseOr(Int32.leftShift(g, 8))
            |> Int32.bitwiseOr(b)

    /// アトラスの画素。左 16px = 床（濃淡 2 色の市松）・右 16px = 軒（横縞の瓦 + 目地）。
    /// 実ファイルの絵を持たないのは、この場面が要るのは「層の前後」だけで、
    /// アセット管理の手間を実験場に増やさないため。
    def atlasPixel(x: Int32, y: Int32): Int32 =
        if (x < 16) {
            let cell = Int32.remainder(x / 8 + y / 8, 2);
            if (cell == 0) argb(255, 52, 68, 56) else argb(255, 44, 58, 48)
        } else {
            if (Int32.remainder(y, 4) == 3) argb(255, 96, 44, 32)
            else if (Int32.remainder(y / 4, 2) == 0) argb(255, 178, 84, 58)
            else argb(255, 156, 70, 48)
        }

    def tileset(): Tileset =
        { atlasSource = { textureName = atlasName(),
                          texWidth = 32.0, texHeight = 32.0, tileSize = tile(),
                          marginX = 0.0, marginY = 0.0, spacingX = 0.0, spacingY = 0.0 } }

    def tileAt(col: Int32, row: Int32, srcX: Float64): TileData =
        { px = { x = Int32.toFloat64(col) * tile(), y = Int32.toFloat64(row) * tile() },
          srcX = srcX, srcY = 0.0, flipH = false, flipV = false, alpha = 1.0f32, tint = TileLayer.noTint() }

    def rowsOf(rowFrom: Int32, rowTo: Int32, srcX: Float64): List[TileData] =
        List.range(rowFrom, rowTo) |> List.flatMap(row ->
            List.range(0, 20) |> List.map(col -> tileAt(col, row, srcX)))

    /// 床の層（z=0 = キャラより奥）。design 320x240 を 20x15 マスで埋める。
    def floorLayer(): TileLayerSpec =
        { key = "tile_demo_floor", tileSet = tileset(),
          tiles = _ -> rowsOf(0, 15, 0.0), origin = Vec2.zero(), zIndex = 0 }

    /// 軒の層（z=50 = キャラより手前）。中段に 2 行の帯（y = 96..128）。
    def roofLayer(): TileLayerSpec =
        { key = "tile_demo_roof", tileSet = tileset(),
          tiles = _ -> rowsOf(6, 8, 16.0), origin = Vec2.zero(), zIndex = 50 }

    /// キャラ 1 体（z=10）。頭 + 胴の 2 箱（体の中心を at に置く）。
    def character(at: Vec2.Vec2): List[Render.PlacedItem] =
        Render.boxAt(at, { x = 20.0, y = 44.0 },
                     { r = 0.30f32, g = 0.45f32, b = 0.85f32 }, 10)
        :: Render.boxAt({ x = at#x, y = at#y - 28.0 }, { x = 14.0, y = 14.0 },
                        { r = 0.95f32, g = 0.80f32, b = 0.65f32 }, 10)
        :: Nil

    /// 1 枚絵を debug/ に焼く。左のキャラは頭が軒の帯に入り（隠れる）、
    /// 右のキャラは帯の外で全身が見える — 同じ z=10 でも帯との重なりだけで差が出る。
    pub def bake(): Unit \ IO =
        let atlas = Harness.atlas();
        let texPaths = Bakery.imagePngs("debug",
            { name = atlasName(), side = atlasSide(), pixelAt = (x, y) -> atlasPixel(x, y) } :: Nil);
        let cfg: Bakery.BakeConfig =
            { design = View.design(), scale = 2,
              background = { r = 0.05f32, g = 0.05f32, b = 0.08f32 },
              texturePath = texPaths, fontTtf = "assets/Xolonium-Regular.ttf", fontAtlas = atlas,
              outDir = "debug", frameW = 640, frameH = 480, gifDelayMs = 100, gifFps = 10 };
        let items = List.flatten(
            TileScene.toItems(floorLayer())
            :: character({ x = 110.0, y = 130.0 })
            :: character({ x = 240.0, y = 190.0 })
            :: TileScene.toItems(roofLayer())
            :: Nil);
        let texInfo = Bakery.imageTextureInfo(
            ({ name = atlasName(), side = atlasSide() }) :: Nil);
        let (drawables, polygons) = Render.drawWith(texInfo, items);
        Bakery.renderPng(cfg, drawables, polygons, "tile_front_demo")
}
