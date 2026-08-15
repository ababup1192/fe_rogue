// SceneRender — ゲーム画面を画面なしで PNG に生成する（スナップショット比較用と、アトリエ候補のプレビュー用）。
// 実行: make render-all → gallery/main.png
//       make render SHOT=main → debug/main.png（1 枚だけ）
//       make atelier-preview → debug/atelier/*.png（スナップショットの外）
mod SceneRender {
    import java.io.File
    import java.lang.System

    def design(): Vec2.Vec2 = { x = World.width(), y = World.height() }

    def ttf(): String = "assets/Xolonium-Regular.ttf"

    def cfgOf(outDir: String, atlas: FontAtlas, bg: Color): HeadlessRender.RenderConfig =
        // 面の縁はならさない — 8×8 のドット絵を整数倍で置く画面なので、ならすと
        // sprite.json の legend に無い中間色が縁に湧く。字は読めないと困るので既定のまま残す。
        { design = design(), scale = 2, background = bg,
          fontTtf = ttf(), fontAtlas = atlas,
          outDir = outDir, frameW = __WW__, frameH = __WH__,
          shapeAntialias = false | HeadlessRender.defaults() }

    def loadWorld(): World.World \ IO =
        run {
            World.initial(SampleDoc.load(SampleDoc.path()),
                KeysDoc.load(KeysDoc.path()),
                ThemeDoc.load(ThemeDoc.path()),
                PxSpriteDoc.load(World.spritePath()),
                Controls.loadShader())
        } with Fs.FileRead.runWithIO

    /// 生成するときの時刻（秒）。実時間でなく固定値を使う — 空の流れも塵の位置もこの t
    /// だけで決まるので、何度生成しても同じ PNG が出る（スナップショットのバイト比較が成り立つ）。
    def renderTime(): Float64 = 3.0

    // ── 決定的な場面（スナップショット） ──

    pub def all(): Unit \ IO =
        discard allShots()

    /// 描き出せる場面の名前。make render の使い方も SHOT の当たり判定も、この並びが source of truth。
    /// 場面を足したら、ここと sceneOf と Makefile の SHOTS を一緒に足す。
    pub def shotNames(): List[String] =
        "main" :: Nil

    /// 名前 → その場面の World。shotNames と対で保つ。名前で引く形にしてあるので、
    /// SHOT で 1 枚だけ生成するときに残りの場面は組まない。
    def sceneOf(name: String, w0: World.World): Option[World.World] =
        match name {
            case "main" => Some(w0)
            case _      => None
        }

    /// SceneRender.all の中身。生成した PNG のパス列を返す — 走行中のゲームへの POST /render
    /// （Main の App.onRenderRequest）もこれを呼ぶ。プレイ状態には触れず Docs から組み立てる。
    pub def allShots(): List[String] \ IO =
        shotsInto("gallery", _ -> true)

    /// SHOT で指した場面だけを debug/ へ生成する（スナップショットを汚さない）。
    /// 実行: make render SHOT=main
    pub def one(): Unit \ IO =
        let wanted = envOr("SHOT", "") |> String.splitOn(substr = " ")
            |> List.map(String.trim) |> List.filter(n -> not String.isEmpty(n));
        let known = List.toSet(shotNames());
        let unknown = wanted |> List.filter(n -> not Set.memberOf(n, known));
        if (List.isEmpty(wanted) or not List.isEmpty(unknown)) {
            println("[render] 描けない名前です: ${List.join(" ", unknown)}");
            println("[render] SHOT=<場面> に使えるのは: ${List.join(" ", shotNames())}");
            System.exit(1)
        } else {
            let picked = List.toSet(wanted);
            discard shotsInto("debug", n -> Set.memberOf(n, picked))
        }

    /// keep が真を返す場面だけを outDir へ生成し、そのファイルパス列を返す。
    def shotsInto(outDir: String, keep: String -> Bool): List[String] \ IO =
        discard (new File(outDir)).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let w0 = loadWorld();
        let cfg = cfgOf(outDir, atlas, w0#theme#bg);
        let ctx = App.viewCtxOf(atlas, design());
        shotNames() |> List.filter(keep) |> List.filterMap(name ->
            sceneOf(name, w0) |> Option.map(w -> shoot(cfg, ctx, w, name)))

    def envOr(key: String, fallback: String): String \ IO =
        let value = System.getenv(key);
        if (Object.isNull(value)) fallback else value

    /// 1 場面を PNG に生成し、生成したファイルパスを返す。
    /// 宣言シェーダーの面は draw に渡さず（渡すと代表色のベタ塗りになる）、
    /// surfaces として別に取り出して画素ごとに評価させる。
    def shoot(cfg: HeadlessRender.RenderConfig, ctx: App.ViewCtx, w: World.World, name: String): String \ IO =
        let items = View.frame(ctx, { t = renderTime() | w });
        let surfaces = Render.shaderSurfaces(items);
        let (drawables, polygons) = Render.draw(Render.withoutShaders(items));
        HeadlessRender.renderPngWith(cfg, drawables, polygons, surfaces, name);
        let path = "${cfg#outDir}/${name}.png";
        println("rendered: ${path}");
        path

    // ── アトリエ（候補スプライト・候補テーマのプレビュー。スナップショットの外） ──

    /// atelier/*.sprite.json（候補）と assets/*.sprite.json（現行 → <名前>.current）を
    /// 実機と同じ描画経路（PxSprite.draw + ThemeDoc.resolver）でコンタクトシートに生成する。
    /// atelier/*.theme.json（候補）は代表場面（初期の盤）で生成する。
    /// 前回生成した残り（古い候補の PNG）は先に消す。読めない・種類の違う JSON は黙って飛ばす（fail-open）。
    pub def atelier(): Unit \ IO =
        discard (new File("debug/atelier")).mkdirs();
        // 前回生成した残りを消す（候補を消したのに絵が残ると紛らわしい）。
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
        // テーマ: 候補を初期の盤で生成する（現行は SceneRender.all の main が兼ねる）。
        jsonsIn("atelier", ".theme.json") |> List.forEach(f -> {
            let text = run { Fs.ReadFile.read("atelier/${f}") } with Fs.ReadFile.runWithFileRead
                with Fs.FileRead.runWithIO;
            match (text |> Result.toOption |> Option.flatMap(ThemeDoc.fromJson)) {
                case None => ()
                case Some(cand) => {
                    let w = loadWorld();
                    let sprites = run { PxSpriteDoc.load(World.spritePath()) }
                        with Fs.FileRead.runWithIO;
                    discard shoot({ background = cand#bg | cfg }, ctx,
                        World.withTheme(cand, sprites, w), stripJson(f))
                }
            }
        })

    /// 1 Doc の全スプライト×全コマを 1 枚に並べる。
    def spriteSheet(cfg: HeadlessRender.RenderConfig, doc: PxSpriteDoc.Doc, theme: ThemeDoc.Doc,
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
        HeadlessRender.renderPng(cfg, drawables, polygons, out);
        println("rendered: ${cfg#outDir}/${out}.png")

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
