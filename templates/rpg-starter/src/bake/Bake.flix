// Bake — ゲーム画面を画面なしで PNG に焼く（golden 比較用と、アトリエ候補のプレビュー用）。
// 実行: flix run --entrypoint Bake.all → gallery/title.png・walk.png・talk.png・door.png・clear.png
//       flix run --entrypoint Bake.atelier → debug/atelier/*.png（golden の外）
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
        { design = design(), scale = 2, background = bg,
          texturePath = Map.empty(), fontTtf = ttf(), fontAtlas = atlas,
          outDir = outDir, frameW = 960, frameH = 600, gifDelayMs = 66, gifFps = 15 }

    def loadWorld(): World.World \ IO =
        run { World.initial(Controls.loadDocs()) } with Fs.FileRead.runWithIO

    // ── 決定的な場面（golden） ──

    pub def all(): Unit \ IO =
        discard allShots()

    /// Bake.all の中身。焼けた PNG のパス列を返す — 走行中のゲームへの POST /bake
    /// （Main の App.onBakeRequest）もこれを呼ぶ。プレイ状態には触れず Docs から組み立てる。
    pub def allShots(): List[String] \ IO =
        discard (new File("gallery")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let w0 = loadWorld();
        let cfg = cfgOf("gallery", atlas, w0#theme#sky);
        let ctx = App.viewCtxOf(atlas, design());
        // 表紙: 夕暮れの里に霧、その上に題と一行。
        let title = shoot(cfg, ctx, w0, "title");
        // 歩き: start から 3 歩（規則で歩く。3 歩 = 歩きのコマが出る奇数）。
        let playing = World.confirm(w0);
        let walking = playing |> World.stepOnce(Dir4.Right) |> World.stepOnce(Dir4.Right)
            |> World.stepOnce(Dir4.Down);
        let walk = shoot(cfg, ctx, walking, "walk");
        // 会話: いちばん後ろの住人（間取りの Doc の並びの末尾）の隣に立って話しかけ、
        // 文字送りを全部出す（settle）。
        let talk = shoot(cfg, ctx, talkScene(playing), "talk");
        // 扉前: 閉じた木戸に向いて立つ。
        let door = shoot(cfg, ctx, doorScene(playing), "door");
        // クリア: 薬草がそろい、灯りが全部ともった里。
        let clear = shoot(cfg, ctx, clearScene(playing), "clear");
        title :: walk :: talk :: door :: clear :: Nil

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

    /// 1 場面を PNG に焼き、焼けたファイルパスを返す。
    def shoot(cfg: Bakery.BakeConfig, ctx: App.ViewCtx, w: World.World, name: String): String \ IO =
        let items = View.frame(ctx, w);
        let (drawables, polygons) = Render.draw(items);
        Bakery.renderPng(cfg, drawables, polygons, name);
        let path = "${cfg#outDir}/${name}.png";
        println("baked: ${path}");
        path

    // ── アトリエ（候補スプライト・候補テーマのプレビュー。golden の外） ──

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
        let ctx = App.viewCtxOf(atlas, design());
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
                    let w = loadWorld();
                    discard shoot({ background = cand#sky | cfg }, ctx,
                        World.withTheme(cand, w), stripJson(f))
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
