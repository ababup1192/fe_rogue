// Bake — ゲーム画面を画面なしで PNG に焼く（スナップショット比較用と、アトリエ候補のプレビュー用）。
// 実行: flix run --entrypoint Bake.all → gallery/title.png・walk.png・talk.png・door.png・clear.png
//       flix run --entrypoint Bake.atelier → debug/atelier/*.png（スナップショットの外）
// 場面の作り方は 2 通りを使い分ける:
//   - 主人公の動き（歩く・話す・扉の前に立つ）は World の規則（stepOnce / confirm）で作る
//     — 実機と同じ経路を通った絵になる。
//   - 立ち位置そのものは Doc の配置（住人・扉のマス）から導いて直接置く
//     — 間取りを編集しても bake の脚本を書き直さずに済む。
mod Bake {
    import java.io.File

    def design(): Vec2.Vec2 = { x = World.width(), y = World.height() }

    def ttf(): String = "assets/PixelMplus10-Regular.ttf"

    def cfgOf(outDir: String, atlas: FontAtlas, bg: Color): Bakery.BakeConfig =
        { design = design(), scale = 3, background = bg,
          texturePath = Map.empty(), fontTtf = ttf(), fontAtlas = atlas,
          outDir = outDir, frameW = 960, frameH = 720, gifDelayMs = 66, gifFps = 15 }

    def loadWorld(): World.World \ IO =
        run { World.initial(Controls.loadDocs()) } with Fs.FileRead.runWithIO

    // ── 決定的な場面（スナップショット） ──

    pub def all(): Unit \ IO =
        discard allShots()

    /// Bake.all の中身。焼けた PNG のパス列を返す — 走行中のゲームへの POST /bake
    /// （Main の App.onBakeRequest）もこれを呼ぶ。プレイ状態には触れず Docs から組み立てる。
    pub def allShots(): List[String] \ IO =
        discard (new File("gallery")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let w0 = loadWorld();
        // 地面のタイルと建物は 1 枚のアトラスから貼る。SoftRaster はファイルからしか
        // 絵を読めないので、アトラスを debug/ に落として texturePath で渡す
        // （gallery/ にスナップショット以外の生成物を置かない）。
        let images = PxSpriteAtlas.asImages(
            { texture = TownMap.textureName(), baked = w0#townAtlas } :: Nil);
        let texPaths = Bakery.imagePngs("debug", images);
        let cfg = { texturePath = texPaths | cfgOf("gallery", atlas, w0#theme#sky) };
        // 表紙: 里の一角に幕、その上に題と一行。
        let title = shoot(cfg, atlas, images, w0, "title");
        // 歩き: start から 3 歩（規則で歩く。3 歩 = 歩きのコマが出る奇数）。
        let playing = World.confirm(w0);
        let walking = playing |> World.stepOnce(Dir4.Right) |> World.stepOnce(Dir4.Right)
            |> World.stepOnce(Dir4.Down);
        let walk = shoot(cfg, atlas, images, walking, "walk");
        // 会話: いちばん後ろの住人（間取りの Doc の並びの末尾）の隣に立って話しかけ、
        // 文字送りを全部出す（settle）。
        let talk = shoot(cfg, atlas, images, talkScene(playing), "talk");
        // 扉前: 閉じた木戸に向いて立つ。
        let door = shoot(cfg, atlas, images, doorScene(playing), "door");
        // 戦い: 魔物と向き合い、1 回殴り合った直後（下のウィンドウに打ち合いの結果が出ている）。
        let fight = shoot(cfg, atlas, images, battleScene(playing), "battle");
        // クリア: 薬草がそろい、灯りが全部ともった里。
        let clear = shoot(cfg, atlas, images, clearScene(playing), "clear");
        title :: walk :: talk :: door :: fight :: clear :: Nil

    /// 魔物と出会い、「たたかう」を 1 回選んだ直後。歩数も打ち合いも規則どおりに進める
    /// （World を手で組まない = 規則が変わればこの絵も一緒に変わる）。
    def battleScene(playing: World.World): World.World =
        let met = walkUntilFoe(playing#battleDoc#encounterSteps, playing);
        // 出会いの 1 行を読み終え（決定）、「たたかう」を選ぶ（決定）。
        World.confirm(World.confirm(met)) |> withClock(2.1)

    /// 魔物に出会うまで規則どおり歩く（左右に往復するので間取りが小さくても歩数が稼げる）。
    /// 上限を切って必ず止まる（Doc で encounterSteps を 0 にしても回り続けない）。
    def walkUntilFoe(budget: Int32, w: World.World): World.World =
        if (budget <= 0 or w#phase == World.Phase.Battle) w
        else {
            let dir = if (Int32.modulo(budget, 2) == 0) Dir4.Right else Dir4.Left;
            walkUntilFoe(budget - 1, World.stepOnce(dir, w))
        }

    /// 時計を決まった秒に据える（またたきや息づかいを毎回同じ位相で焼くため）。
    def withClock(t: Float64, w: World.World): World.World = { t = t | w }

    /// 住人の隣（歩けるマス）に立ち、規則どおり話しかけて文字送りを終えた状態。
    /// 話し相手は villagers の末尾 — 約束の相手（先頭に置く習わし）でない住人が選ばれ、
    /// ふつうの 1 行のふきだしが写る。住人がいなければそのまま（fail-open）。
    def talkScene(playing: World.World): World.World =
        match List.last(playing#map#villagers) {
            case None           => playing
            case Some(villager) => match standNextTo(villager#cell, playing) {
                case None    => playing
                case Some(w) => settle(World.confirm(w))
            }
        }

    /// 閉じた木戸の前に立ち、木戸のほうを向いた状態。
    def doorScene(playing: World.World): World.World =
        standNextTo(playing#map#door#cell, playing) |> Option.getWithDefault(playing)

    /// 薬草がそろってクリアになった状態（扉は開き、灯りは全部ともる）。
    /// 収支は World の導出（goalOf / lampsLit）に合わせて置く。
    def clearScene(playing: World.World): World.World =
        { phase = World.Phase.Clear, doorOpen = true,
          herbs = Nil, picked = World.goalOf(playing) | playing }

    /// target の四方の歩けるマスに主人公を置き、target のほうを向かせる。
    /// （立ち位置は Doc の配置から導く — 間取りを編集しても脚本が壊れない。）
    /// 下側を先に試す — ふきだしは相手の頭の上に出るので、主人公が隠れない。
    def standNextTo(target: Grid.Cell, w: World.World): Option[World.World] =
        (Dir4.Down :: Dir4.Left :: Dir4.Right :: Dir4.Up :: Nil)
            |> List.filter(d -> World.walkable(Grid.neighborOf(target, d), w))
            |> List.head
            |> Option.map(d -> { hero = Grid.neighborOf(target, d), facing = Dir4.opposite(d) | w })

    /// 文字送りを使い切って 1 行を読み終えた状態にする。
    def settle(w: World.World): World.World = World.step(None, 60.0, w)

    /// 実機と同じ camera 中心を出す（追従 → bounds へ収める → 1px 吸着の順。
    /// App の resolvedCamera と同じ式 — bake だけ別の式にすると実機と絵がずれる）。
    def cameraOf(w: World.World, design0: Vec2.Vec2): Vec2.Vec2 =
        let clamped = CameraRig.clampCenter(
            bounds = World.boardRect(w), seen = design0, World.cameraCenter(w));
        { x = Float64.round(clamped#x), y = Float64.round(clamped#y) }

    /// 1 場面を PNG に焼き、焼けたファイルパスを返す。world 側の絵に camera を掛けて
    /// hud を重ねる合成は、実機と同じ App.composeScene を通す。
    /// 地面（タイル層）は実機ではエンジンの別チャンネルなので、bake では
    /// TileScene.toItems の CPU 投影を world の先頭に足して同じ絵にする。
    def shoot(cfg: Bakery.BakeConfig, atlas: FontAtlas,
              images: List[{ name = String, side = Int32, pixelAt = (Int32, Int32) -> Int32 }],
              w: World.World, name: String): String \ IO =
        shootAt(cfg, atlas, images, w, cameraOf(w, cfg#design), name)

    /// camera 中心を自分で決める版（建物のクローズアップ等）。
    def shootAt(cfg: Bakery.BakeConfig, atlas: FontAtlas,
                images: List[{ name = String, side = Int32, pixelAt = (Int32, Int32) -> Int32 }],
                w: World.World, center: Vec2.Vec2, name: String): String \ IO =
        let design0 = cfg#design;
        let ctx = { atlas = atlas, fontOf = _ -> atlas,
                    visible = App.visibleOf(Some(center), 1.0, design0) };
        // hud には常に design 全体が見えている扱い（実機の sceneItems と同じ）。
        let hudCtx = { atlas = atlas, fontOf = _ -> atlas,
                       visible = App.visibleOf(None, 1.0, design0) };
        let ground = match w#phase {
            case World.Phase.Battle => Nil
            case _ => TileScene.toItems(TownMap.spec(w#townMap, w#townAtlas))
        };
        let items = App.composeScene(Some(center), 1.0, design0,
            { world = List.append(ground, View.frame(ctx, w)), hud = View.hud(hudCtx, w) });
        // シェーダー面（水面）は画素評価のチャンネルへ分け、draw 側からは外して二重に塗らない。
        let surfaces = Render.shaderSurfaces(items);
        let (drawables, polygons) =
            Render.drawWith(Bakery.imageTextureInfo(images), Render.withoutShaders(items));
        Bakery.renderPngWith(cfg, drawables, polygons, surfaces, name);
        let path = "${cfg#outDir}/${name}.png";
        println("baked: ${path}");
        path

    // ── 街の下書き（DQ6級の街並み検証。スナップショットの外・debug/ 行き） ──
    // 盤の正典は Doc（assets/town.map.json）、層の宣言は TownMap — ここは焼くだけ。
    // この 2 枚は盤全体（640×480）を 1 枚で見たいので、design を盤の寸法に上げた
    // 別 config で焼く（camera は掛けない — 全景のほうが批評しやすい）。

    def townCfgOf(outDir: String, atlas: FontAtlas, bg: Color): Bakery.BakeConfig =
        { design = { x = 640.0, y = 480.0 }, scale = 2, frameW = 1280, frameH = 960
          | cfgOf(outDir, atlas, bg) }

    /// 街の全景（地面のタイル家族 + 建物 + 人）を debug/town_floor.png に焼く。
    /// 里を歩いている状態（Play）で組む — 実機の walk 画面と同じ絵の全体が 1 枚で見える。
    pub def town(): Unit \ IO =
        discard (new File("debug")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let w = World.confirm(loadWorld());
        let images = PxSpriteAtlas.asImages(
            { texture = TownMap.textureName(), baked = w#townAtlas } :: Nil);
        let texPaths = Bakery.imagePngs("debug", images);
        let cfg = { texturePath = texPaths | townCfgOf("debug", atlas, w#theme#sky) };
        let ctx = App.viewCtxOf(atlas, cfg#design);
        let ground = TileScene.toItems(TownMap.spec(w#townMap, w#townAtlas));
        let items = List.append(ground, View.frame(ctx, { t = 2.1, npcClock = 2.1 | w }));
        let surfaces = Render.shaderSurfaces(items);
        let (drawables, polygons) =
            Render.drawWith(Bakery.imageTextureInfo(images), Render.withoutShaders(items));
        Bakery.renderPngWith(cfg, drawables, polygons, surfaces, "town_floor");
        println("baked: debug/town_floor.png")

    /// 建物 1 棟のクローズアップ（320×240 等倍・建物が画面中央）を 3 枚焼く:
    ///   house_closeup … 主人公なし（建物そのものの水準を見る）
    ///   house_behind  … 主人公が建物の裏（北側）— 屋根と壁に隠れることの証明
    ///   house_front   … 主人公が建物の手前（南側）— 全身が建物の前に出ることの証明
    pub def house(): Unit \ IO =
        discard (new File("debug")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let playing = World.confirm(loadWorld()) |> withClock(2.1);
        let images = PxSpriteAtlas.asImages(
            { texture = TownMap.textureName(), baked = playing#townAtlas } :: Nil);
        let texPaths = Bakery.imagePngs("debug", images);
        let cfg = { texturePath = texPaths | cfgOf("debug", atlas, playing#theme#sky) };
        // カメラは 1 棟目の民家の見た目の中心（位置を変えても追随する）。
        let nw = buildingCell("house", { x = 10, y = 11 });
        let t = World.tileSize();
        let center = { x = (Int32.toFloat64(nw#x) + 2.0) * t,
                       y = (Int32.toFloat64(nw#y) + 1.0) * t - 6.0 };
        let far = { hero = { x = 30, y = 20 } | playing };
        discard shootAt(cfg, atlas, images, far, center, "house_closeup");
        let behind = { hero = { x = nw#x + 1, y = nw#y - 1 }, facing = Dir4.Down | playing };
        discard shootAt(cfg, atlas, images, behind, center, "house_behind");
        let front = { hero = { x = nw#x + 1, y = nw#y + 3 }, facing = Dir4.Down | playing };
        discard shootAt(cfg, atlas, images, front, center, "house_front");
        // 門の開閉（絵が切り替わることの証明）。カメラは門のマスを bounds 内へ収めた位置。
        let doorCell = playing#map#door#cell;
        let gc0 = { x = Int32.toFloat64(doorCell#x) * t + t / 2.0,
                    y = Int32.toFloat64(doorCell#y) * t };
        let gc1 = CameraRig.clampCenter(bounds = World.boardRect(playing),
            seen = cfg#design, gc0);
        let gc = { x = Float64.round(gc1#x), y = Float64.round(gc1#y) };
        let atGate = { hero = { x = doorCell#x, y = doorCell#y + 1 },
                       facing = Dir4.Up | playing };
        discard shootAt(cfg, atlas, images, atGate, gc, "gate_closed");
        discard shootAt(cfg, atlas, images, { doorOpen = true | atGate }, gc, "gate_open");
        // 2棟目(パン屋)と教会の寄り。カメラは各建物の見た目の中心を bounds 内へ収めた位置。
        discard shootAt(cfg, atlas, images, far,
            buildingCamera(playing, cfg#design, "shop", 3, 3), "shop_closeup");
        discard shootAt(cfg, atlas, images, far,
            buildingCamera(playing, cfg#design, "church", 5, 4), "church_closeup")

    /// 動き物の証明: 同じ場面を別の時刻で焼く（水面・煙・旗・巡回が動いていれば絵が変わる）。
    ///   water_a/b  … 橋のたもと（水面の網目が流れる）
    ///   smoke_a/b  … パン屋（窯の煙が立ちのぼる）+ 住人 ko の巡回も写る
    pub def motion(): Unit \ IO =
        discard (new File("debug")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let playing = World.confirm(loadWorld());
        let images = PxSpriteAtlas.asImages(
            { texture = TownMap.textureName(), baked = playing#townAtlas } :: Nil);
        let texPaths = Bakery.imagePngs("debug", images);
        let cfg = { texturePath = texPaths | cfgOf("debug", atlas, playing#theme#sky) };
        let shaderLoaded = run { ShaderJson.load(Controls.waterShaderPath()) } with Fs.FileRead.runWithIO;
        let shaderOk = Result.isOk(shaderLoaded);
        println(if (shaderOk) "waterShader: parsed ok (custom doc)"
                else "waterShader: FELL BACK to waterVeins (vocab?)");
        println("smokeFx: emitters=${Int32.toString(List.length(playing#smokeFx#emitters))} duration=${Float64.toString(playing#smokeFx#duration)} items(t=1.4)=${Int32.toString(List.length(Fx.sample(playing#smokeFx, 7i64, 1.4)))}");
        let bridgeC = { x = 272.0, y = 120.0 };
        let shopC = { x = 344.0, y = 120.0 };
        let at = (t, c, name) -> {
            discard shootAt(cfg, atlas, images,
                { t = t, npcClock = t | playing }, c, name)
        };
        at(1.0, bridgeC, "water_a");
        at(3.0, bridgeC, "water_b");
        at(1.4, shopC, "smoke_a");
        at(3.4, shopC, "smoke_b")

    /// スクロールの継ぎ目検分: camera を半端な座標に置いて焼く（実機のスクロール中と
    /// 同じ条件）。タイルの貼りに継ぎ目対策（half-texel inset）が効いていれば、
    /// タイル境界に細線（下の色や隣のコマの色）は出ない。
    /// 橋のたもと — 芝・石畳・水の縁が全部写る場所で 2 枚焼く:
    ///   seam_half  … center の x/y がどちらも .5（タイルとピクセルの位相が最悪の半分ずれ）
    ///   seam_cross … center が .25/.75 でマスの境界をまたぐ（丸めの向きが軸で食い違う形）
    pub def seam(): Unit \ IO =
        discard (new File("debug")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let playing = World.confirm(loadWorld()) |> withClock(2.1);
        let images = PxSpriteAtlas.asImages(
            { texture = TownMap.textureName(), baked = playing#townAtlas } :: Nil);
        let texPaths = Bakery.imagePngs("debug", images);
        let cfg = { texturePath = texPaths | cfgOf("debug", atlas, playing#theme#sky) };
        discard shootAt(cfg, atlas, images, playing, { x = 272.5, y = 120.5 }, "seam_half");
        discard shootAt(cfg, atlas, images, playing, { x = 264.25, y = 127.75 }, "seam_cross")

    /// 動的 PlacedItem の勘定（DQ6級チェックの性能欄）。タイル層は GPU 側の別チャンネルに
    /// 事前生成されるので数に入れない — 実機で毎フレーム組み直す動的な絵（world + hud）だけを
    /// 実機と同じ合成（App.composeScene = 画面外 culling 込み）で数える。
    pub def count(): Unit \ IO =
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let w0 = loadWorld();
        let playing = World.confirm(w0) |> withClock(2.1);
        let scenes =
               ("title", w0)
            :: ("walk", playing)
            :: ("talk", talkScene(playing))
            :: ("battle", battleScene(playing))
            :: ("clear", clearScene(playing)) :: Nil;
        scenes |> List.forEach(sc -> {
            let (name, w) = sc;
            let design0 = design();
            let center = cameraOf(w, design0);
            let ctx = { atlas = atlas, fontOf = _ -> atlas,
                        visible = App.visibleOf(Some(center), 1.0, design0) };
            let hudCtx = { atlas = atlas, fontOf = _ -> atlas,
                          visible = App.visibleOf(None, 1.0, design0) };
            let items = App.composeScene(Some(center), 1.0, design0,
                { world = View.frame(ctx, w), hud = View.hud(hudCtx, w) });
            println("${name}: ${Int32.toString(List.length(items))} items")
        })

    /// 種類で建物の設置マスを引く（無ければ fallback — bake が落ちるより絵がずれる方がよい）。
    def buildingCell(kind: String, fallback: Grid.Cell): Grid.Cell =
        TownMap.buildings()
            |> List.find(b -> b#kind == kind)
            |> Option.map(b -> b#cell)
            |> Option.getWithDefault(fallback)

    /// 建物の見た目の中心へ寄せた camera 中心（bounds へ収めて丸める）。
    def buildingCamera(w: World.World, design0: Vec2.Vec2, kind: String,
                       fw: Int32, fh: Int32): Vec2.Vec2 =
        let t = World.tileSize();
        let nw = buildingCell(kind, { x = 0, y = 0 });
        let c0 = { x = (Int32.toFloat64(nw#x) + Int32.toFloat64(fw) / 2.0) * t,
                   y = (Int32.toFloat64(nw#y) + Int32.toFloat64(fh) / 2.0) * t - 24.0 };
        let c1 = CameraRig.clampCenter(bounds = World.boardRect(w), seen = design0, c0);
        { x = Float64.round(c1#x), y = Float64.round(c1#y) }

    /// 同じ盤をタイル層の宣言（TileLayerSpec → TileScene.toItems）経由で
    /// debug/town_floor_scene.png に焼く。実機の GPU 経路と同じ Spec から派生するので、
    /// town との見比べが「宣言タイル層は正しく敷けるか」の検証になる。
    /// SoftRaster はファイルからしか絵を読めないため、焼いたアトラスを
    /// debug/town_tiles.png に落として texturePath で渡す。
    pub def townScene(): Unit \ IO =
        discard (new File("debug")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let (sprites, theme, townMap) = run {
            (PxSpriteDoc.load(World.townSpritePath()), ThemeDoc.load(ThemeDoc.path()),
             TownMapDoc.load(TownMapDoc.path()))
        } with Fs.FileRead.runWithIO;
        let (baked, _atlasKey) = World.bakeTownAtlas(sprites, theme);
        let images = PxSpriteAtlas.asImages(
            { texture = TownMap.textureName(), baked = baked } :: Nil);
        let texPaths = Bakery.imagePngs("debug", images);
        let cfg = { texturePath = texPaths | townCfgOf("debug", atlas, theme#sky) };
        let items = TileScene.toItems(TownMap.spec(townMap, baked));
        let (drawables, polygons) = Render.drawWith(Bakery.imageTextureInfo(images), items);
        Bakery.renderPng(cfg, drawables, polygons, "town_floor_scene");
        println("baked: debug/town_floor_scene.png")

    // ── アトリエ（候補スプライト・候補テーマのプレビュー。スナップショットの外） ──

    /// atelier/*.sprite.json（候補）と assets/*.sprite.json（現行 → <名前>.current）を
    /// 実機と同じ描画経路（PxSprite.draw + ThemeDoc.resolver）でコンタクトシートに焼く。
    /// atelier/*.theme.json（候補）は代表場面（表紙）で焼く。
    /// 前回の焼き残し（古い候補の PNG）は先に消す。読めない・種類の違う JSON は黙って飛ばす（fail-open）。
    pub def atelier(): Unit \ IO =
        discard (new File("debug/atelier")).mkdirs();
        // 前回の焼き残しを消す（候補を消したのに絵が残ると紛らわしい）。
        jsonsIn("debug/atelier", ".png") |> List.forEach(f ->
            discard (new File("debug/atelier/${f}")).delete());
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let theme = run { ThemeDoc.load(ThemeDoc.path()) } with Fs.FileRead.runWithIO;
        let cfg = cfgOf("debug/atelier", atlas, theme#sky);
        // スプライト: 候補 + 現行。
        let jobs = List.append(
            jsonsIn("atelier", ".sprite.json") |> List.map(f -> ("atelier/${f}", stripJson(f))),
            jsonsIn("assets", ".sprite.json") |> List.map(f -> ("assets/${f}", "${stripJson(f)}.current")));
        jobs |> List.forEach(job -> {
            let (path, out) = job;
            let doc = run { PxSpriteDoc.load(path) } with Fs.FileRead.runWithIO;
            if (Map.isEmpty(doc#sprites)) ()
            else spriteSheet(cfg, doc, theme, out)
        });
        // テーマ: 候補を代表場面（表紙）で焼く（現行は Bake.all の title が兼ねる）。
        jsonsIn("atelier", ".theme.json") |> List.forEach(f -> {
            let text = run { Fs.ReadFile.read("atelier/${f}") } with Fs.ReadFile.runWithFileRead
                with Fs.FileRead.runWithIO;
            match (text |> Result.toOption |> Option.flatMap(ThemeDoc.fromJson)) {
                case None => ()
                case Some(cand) => {
                    // 候補テーマはアトラスの実色も変える — その候補の色で焼き直して渡す。
                    let wc = World.withTheme(cand, loadWorld());
                    let images = PxSpriteAtlas.asImages(
                        { texture = TownMap.textureName(), baked = wc#townAtlas } :: Nil);
                    let texPaths = Bakery.imagePngs("debug", images);
                    discard shoot({ background = cand#sky, texturePath = texPaths | cfg },
                        atlas, images, wc, stripJson(f))
                }
            }
        })

    /// 1 Doc の全スプライト×全コマを 1 枚に並べる。
    def spriteSheet(cfg: Bakery.BakeConfig, doc: PxSpriteDoc.Doc, theme: ThemeDoc.Doc,
                    out: String): Unit \ IO =
        let s = 4;
        let cellW = 74.0;
        let cellH = 56.0;
        let items = Map.toList(doc#sprites) |> List.zipWithIndex |> List.flatMap(entry -> {
            let (rowIdx, sp) = entry;
            let (name, sprite) = sp;
            let y0 = 10.0 + Int32.toFloat64(rowIdx) * cellH;
            Map.toList(sprite#frames) |> List.zipWithIndex |> List.flatMap(frEntry -> {
                let (frameIdx, fr) = frEntry;
                let (frame, _) = fr;
                let x0 = 10.0 + Int32.toFloat64(frameIdx) * cellW;
                PxSprite.draw(doc, name, frame, { x = x0, y = y0 },
                    false, s, key -> ThemeDoc.resolver(theme, key), 10)
            })
        });
        let (drawables, polygons) = Render.draw(items);
        Bakery.renderPng(cfg, drawables, polygons, out);
        println("baked: ${cfg#outDir}/${out}.png")

    // ── 小物 ──

    def jsonsIn(dir: String, suffix: String): List[String] \ IO =
        let entries = (new File(dir)).list();
        if (Object.isNull(entries)) Nil
        else Array.toList(entries)
            |> List.filter(f -> String.endsWith(suffix = suffix, f))
            |> List.sort

    def stripJson(f: String): String =
        if (String.endsWith(suffix = ".json", f))
            String.dropRight(String.length(".json"), f)
        else f
}
