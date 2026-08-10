// Bake — ゲーム画面を画面なしで PNG に焼く（golden 比較用と、アトリエ候補のプレビュー用）。
// 実行: flix run --entrypoint Bake.all → gallery/title.png・choice.png・ending.png
//       flix run --entrypoint Bake.atelier → debug/atelier/*.png（golden の外）
// 場面は「進めて作る」: 台本が伸びても拍数を数え直さずに済むよう、
// 「選択肢待ちになるまで進める」「結末の最後の拍まで進める」で位置を決める。
mod Bake {
    import java.io.File

    def design(): Vec2.Vec2 = { x = World.width(), y = World.height() }

    def ttf(): String = "assets/PixelMplus10-Regular.ttf"

    def cfgOf(outDir: String, atlas: FontAtlas, bg: Color): Bakery.BakeConfig =
        { design = design(), scale = 2, background = bg,
          texturePath = Map.empty(), fontTtf = ttf(), fontAtlas = atlas,
          outDir = outDir, frameW = 960, frameH = 600, gifDelayMs = 66, gifFps = 15 }

    def loadWorld(): World.World \ IO =
        run {
            World.initial(Controls.loadDocs(), NovelKit.spawnAssets())
        } with Fs.FileRead.runWithIO

    // ── 決定的な場面（golden） ──

    pub def all(): Unit \ IO =
        discard allShots()

    /// Bake.all の中身。焼けた PNG のパス列を返す — 走行中のゲームへの POST /bake
    /// （Main の App.onBakeRequest）もこれを呼ぶ。プレイ状態には触れず Docs から組み立てる。
    /// 場面ごとに時計 t を固定してから焼く（雨も炎も埃も t から導くので、
    /// 据えれば毎回同じ絵になる = golden がバイトで比べられる）。
    pub def allShots(): List[String] \ IO =
        discard (new File("gallery")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let w0 = loadWorld();
        let cfg = cfgOf("gallery", atlas, w0#theme#bg);
        let ctx = App.viewCtxOf(atlas, design());
        // 表紙: 灯りが全部ついた書斎とタイトル。
        let title = shoot(cfg, ctx, { t = 2.3 | w0 }, "title");
        // 最初の分岐: 問いを読み終え、選択肢のチップが出た状態。
        let asking = walkToAsk(40, World.advance(w0));
        let choice = shoot(cfg, ctx, { t = 5.1 | asking }, "choice");
        // 結末: 疑いを重ねて灯りが消えた書斎で、最後の一文を読んでいる状態。
        // （分岐 2 つは選んで次の分岐まで歩き、最後の告発だけは結末の最後の拍で止める）
        let ended = asking |> pickAndWalk(0) |> pickAndWalk(0) |> World.pick(1) |> walkToLast(40);
        let ending = shoot(cfg, ctx, { t = 8.4 | ended }, "ending");
        title :: choice :: ending :: Nil

    /// 1 場面を PNG に焼き、焼けたファイルパスを返す。hud の合流は実機と同じ
    /// App.composeScene を通す（カメラ無しなので center = None・等倍）。
    def shoot(cfg: Bakery.BakeConfig, ctx: App.ViewCtx, w: World.World, name: String): String \ IO =
        let items = App.composeScene(None, 1.0, cfg#design,
            { world = View.frame(ctx, w), hud = View.hud(ctx, w) });
        let (drawables, polygons) = Render.draw(items);
        Bakery.renderPng(cfg, drawables, polygons, name);
        let path = "${cfg#outDir}/${name}.png";
        println("baked: ${path}");
        path

    /// 文字送りを使い切って 1 拍読み終えた状態にする（UI への投影も済む）。
    def settle(w: World.World): World.World = World.step(60.0, w)

    /// 選択肢待ちになるまで拍を進める（fuel で必ず止まる）。
    def walkToAsk(fuel: Int32, w: World.World): World.World =
        let settled = settle(w);
        if (fuel <= 0 or NovelKit.isAsking(settled#kit)) settled
        else walkToAsk(fuel - 1, World.advance(settled))

    /// 選択肢 i を選んで、次の選択肢待ちまで進める（途中に分岐が無ければ最後まで歩く）。
    def pickAndWalk(i: Int32, w: World.World): World.World =
        walkToAsk(40, World.pick(i, w))

    /// これ以上進めると表紙へ戻る、その手前（結末の最後の拍）で止める。
    def walkToLast(fuel: Int32, w: World.World): World.World =
        let settled = settle(w);
        let next = World.advance(settled);
        if (fuel <= 0 or next#phase == World.Phase.Title) settled
        else walkToLast(fuel - 1, next)

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
        let cfg = cfgOf("debug/atelier", atlas, theme#bg);
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
                    discard shoot({ background = cand#bg | cfg }, ctx,
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
