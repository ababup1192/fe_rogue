// Bake — ゲーム画面を画面なしで PNG に焼く(golden 比較用)。
// 実行: make bake → gallery/*.png(title / hill / cave / tower)
// 時刻 t は固定値 — 空・コイン・旗・動く床がこの t だけで決まるので、
// 何度焼いても同じ PNG が出る(golden のバイト比較が成り立つ)。
mod Bake {
    import java.io.File
    import java.lang.System

    def design(): Vec2.Vec2 = View.design()

    def ttf(): String = "assets/Xolonium-Regular.ttf"

    def cfgOf(atlas: FontAtlas, bg: Color): Bakery.BakeConfig =
        { design = design(), scale = 2, background = bg,
          texturePath = Map.empty(), fontTtf = ttf(), fontAtlas = atlas,
          outDir = "gallery", frameW = 1280, frameH = 720, gifDelayMs = 66, gifFps = 15 }

    def loadWorld(): World.World \ IO =
        run {
            World.initial(MotionDoc.load(MotionDoc.path()),
                KeysDoc.load(KeysDoc.path()),
                RulesDoc.load(RulesDoc.path()),
                EnemyDoc.load(EnemyDoc.path()),
                StageDoc.load(StageDoc.path()),
                Theme.load(Theme.path()),
                UiText.load(UiText.path()),
                PxSpriteDoc.load(World.spritePath()))
        } with Fs.FileRead.runWithIO

    /// 実機が GPU へ上げているのと同じアトラス画素をファイルへ落とす
    /// (焼きは PNG からしか絵を読めない)。
    def atlasImages(w: World.World): List[{ name = String, side = Int32,
                                            pixelAt = (Int32, Int32) -> Int32 }] =
        { name = World.atlasName(), side = w#atlas#side,
          pixelAt = (x, y) -> PxSpriteAtlas.pixelAt(w#atlas, x, y) } :: Nil

    def envOr(key: String, fallback: String): String \ IO =
        let value = System.getenv(key);
        if (Object.isNull(value)) fallback else value

    // コイン(spin_0 / spin_1)が表を向く時刻を選ぶ — 横向きのコマだと
    // 見本の絵でコインが棒に見える。floor(t*5) が偶数なら表。
    def bakeTime(): Float64 = 3.2

    def withT(w: World.World): World.World = { t = bakeTime() | w }

    pub def all(): Unit \ IO =
        discard allShots()

    /// 調整中の 1 枚だけを debug/ へ焼く(golden を汚さない)。
    /// 実行: make shot STAGE=1 — 洞窟のように 1 枚が重い面を見ながら直すとき、
    /// 4 枚まとめて焼き直すのを待たずに済む。
    pub def one(): Unit \ IO =
        discard (new File("debug")).mkdirs();
        let ix = envOr("STAGE", "0") |> Int32.fromString |> Option.getWithDefault(0);
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let w0 = loadWorld();
        let images = atlasImages(w0);
        let cfg = { outDir = "debug",
                    texturePath = Bakery.imagePngs("debug", images)
                    | cfgOf(atlas, Theme.resolve(w0#theme, "ink")) };
        let w = withT(World.loadStage(ix, w0));
        discard shoot(cfg, Bakery.imageTextureInfo(images), atlas, w, "shot")

    /// 決定的な 4 場面。走行中の POST /bake(App.onBakeRequest)もこれを呼べる。
    pub def allShots(): List[String] \ IO =
        discard (new File("gallery")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let w0 = loadWorld();
        let images = atlasImages(w0);
        let cfg = { texturePath = Bakery.imagePngs("debug", images)
                    | cfgOf(atlas, Theme.resolve(w0#theme, "ink")) };
        let texInfo = Bakery.imageTextureInfo(images);
        let hill = withT(w0);
        let cave = withT(World.loadStage(1, w0));
        let tower = withT(World.loadStage(2, w0));
        // title は Studio のジャンル札の顔(GET /genesis/title が読む)と、
        // HUD 経路のリグレッション検知を兼ねる — 丘を HUD ごと焼く。
        // 「夕方の丘を走って跳ぶ」が 1 枚で伝わる場面を選んでいる。
        shootWith(cfg, texInfo, atlas, hill, "title",
                View.hud(App.viewCtxOf(atlas, design()), hill))
            :: shoot(cfg, texInfo, atlas, hill, "hill")
            :: shoot(cfg, texInfo, atlas, cave, "cave")
            :: shoot(cfg, texInfo, atlas, tower, "tower")
            :: Nil

    /// カメラを面の中へ収める(実機の App.withCameraBounds と同じ役)。
    /// 面が画面より小さい軸は中央に置く。
    def clampFocus(w: World.World, focus: Vec2.Vec2): Vec2.Vec2 =
        let r = World.worldRect(w);
        let clampAxis = (size, half, v) ->
            if (size <= half * 2.0) size / 2.0
            else CameraRig.clampAxis(half, size - half, v);
        { x = clampAxis(r#size#x, design()#x / 2.0, focus#x),
          y = clampAxis(r#size#y, design()#y / 2.0, focus#y) }

    /// カメラ中心 = World.cameraFocus。visible をその矩形にして View.frame(全動的)を呼び、
    /// ワールド座標の絵を画面座標へ平行移動する。視差レイヤは実機
    /// (CameraRig.parallaxCenter)と同じ式で「見かけのカメラ」を作って重ねる。
    def shoot(cfg: Bakery.BakeConfig, texInfo: String -> Option[GameEngine.TextureInfo],
              atlas: FontAtlas, w: World.World, name: String): String \ IO =
        shootWith(cfg, texInfo, atlas, w, name, Nil)

    /// shoot の HUD 付き版。extras は画面座標のまま最後へ重ねる(実機の withHudView と同じ)。
    def shootWith(cfg: Bakery.BakeConfig, texInfo: String -> Option[GameEngine.TextureInfo],
                  atlas: FontAtlas, w: World.World, name: String,
                  extras: List[Render.PlacedItem]): String \ IO =
        let focus = clampFocus(w, World.cameraFocus(w));
        let topLeft = { x = focus#x - design()#x / 2.0, y = focus#y - design()#y / 2.0 };
        let ctx = { visible = { position = topLeft, size = design() }
                  | App.viewCtxOf(atlas, design()) };
        let layerOf = (factor, lview) -> {
            let lcenter = CameraRig.parallaxCenter(factor, focus, design = design());
            let ltl = Vec2.sub(lcenter, Vec2.mul(design(), 0.5));
            let lctx = { visible = { position = ltl, size = design() }
                       | App.viewCtxOf(atlas, design()) };
            lview(lctx, w) |> Render.movedAll({ x = -ltl#x, y = -ltl#y })
        };
        let layers = layerOf(0.0, (_lctx, lw) -> View.backdrop(lw))
            |> List.append(layerOf(0.04, View.clouds))
            |> List.append(layerOf(0.10, View.mountains))
            |> List.append(layerOf(0.18, View.farHills))
            |> List.append(layerOf(0.30, View.forest));
        let items = layers
            |> List.append(
                View.frame(ctx, w) |> Render.movedAll({ x = -topLeft#x, y = -topLeft#y }))
            |> List.append(extras);
        let (drawables, polygons) = Render.drawWith(texInfo, items);
        Bakery.renderPng(cfg, drawables, polygons, name);
        let path = "${cfg#outDir}/${name}.png";
        println("baked: ${path}");
        path
}
