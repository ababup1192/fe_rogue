// CutsceneBake — イベントシーンを画面なしで GIF ＋ コマ別 PNG に焼く（golden の外）。
// 実行: flix run --entrypoint CutsceneBake.all → debug/cutscene/<id>.gif と
//       debug/cutscene/frames/<id>/*.png（駒送りで細かく見る用）。
// 場面は Cutscene.framesOf が演じた World のコマ列そのもの — 実機と同じ規則を通った絵になる。
// 編集ループ: assets/*.cutscene.json を保存 → make cutscene → GIF を目視、を回す。
// 脚本の誤り（飛ばしたカット・打ち切り）は止めずに焼き切り、最後にまとめて報せる。
mod CutsceneBake {
    import java.io.File
    import java.lang.System

    /// assets/ のイベントシーンを debug/cutscene/ に焼く。
    /// 環境変数 CUTSCENE_FILE にパスが入っていればその 1 本だけ
    /// （make cutscene FILE=assets/x.cutscene.json — 触った脚本ぶんの待ちで済む）。
    pub def all(): Unit \ IO =
        discard (new File("debug/cutscene")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(Bake.ttf(), Bake.ttf());
        let w0 = Bake.loadWorld();
        let cfg = Bake.cfgOf("debug/cutscene", atlas, w0#theme#sky);
        let ctx = App.viewCtxOf(atlas, Bake.design());
        chosenPaths() |> List.forEach(path -> {
            let (doc, warnings) = readScript(path);
            let played = Cutscene.framesOf(doc, w0);
            discard Bakery.bakeGif(cfg, played#frames, 2,
                w -> Render.draw(View.frame(ctx, w)), doc#id);
            println("baked: ${cfg#outDir}/${doc#id}.gif (${List.length(played#frames)} frames)");
            List.append(warnings, played#notes)
                |> List.forEach(note -> println("  ${path}: ${note}"))
        })

    /// 焼く脚本の一覧。CUTSCENE_FILE が指すパスが一覧に有ればその 1 本、無ければ全部。
    def chosenPaths(): List[String] \ IO =
        let chosen = System.getenv("CUTSCENE_FILE");
        if (Object.isNull(chosen) or chosen == "") CutsceneDoc.paths()
        else if (List.memberOf(chosen, CutsceneDoc.paths())) chosen :: Nil
        else {
            println("CUTSCENE_FILE=${chosen} は CutsceneDoc.paths() に無いので全部焼く");
            CutsceneDoc.paths()
        }

    /// 脚本を読み、JSON ごと読めないときはその報せを添えて既定へ倒す
    /// （読めないカット 1 つぶんの報せは Cut.Broken を演じる側が出す）。
    /// pub なのは常駐の焼き係（CutscenePreview）が同じ読み方をするため。
    pub def readScript(path: String): (CutsceneDoc.Doc, List[String]) \ IO =
        let readResult = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead
            with Fs.FileRead.runWithIO;
        let text = readResult |> Result.toOption |> Option.getWithDefault("");
        match CutsceneDoc.fromJson(text) {
            case None      => (CutsceneDoc.defaults(),
                               "JSON が読めないので既定(空のシーン)へ倒した" :: Nil)
            case Some(doc) => (doc, Nil)
        }

    // ── 座標定規（脚本の start / at のマスを数える下敷き。golden の外） ──

    /// 間取りを座標定規つき（上端に x・左端に y の数字を薄く重ねる）で
    /// debug/cutscene/grid/grid.png に焼く。実行: make cutscene-grid。
    pub def grid(): Unit \ IO =
        discard (new File("debug/cutscene/grid")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(Bake.ttf(), Bake.ttf());
        // 表紙の文字が間取りに重ならないよう、決定を押して遊びの状態にしてから焼く。
        let w0 = World.confirm(Bake.loadWorld());
        let cfg = Bake.cfgOf("debug/cutscene/grid", atlas, w0#theme#sky);
        let ctx = App.viewCtxOf(atlas, Bake.design());
        let items = List.append(View.frame(ctx, w0), ruler(atlas, w0));
        let (drawables, polygons) = Render.draw(items);
        Bakery.renderPng(cfg, drawables, polygons, "grid");
        println("baked: ${cfg#outDir}/grid.png")

    /// 定規の数字。盤の位置は View と同じ式で引くので、絵とずれない。
    /// 画面の外に出た数字は描かない。
    def ruler(atlas: FontAtlas, w: World.World): List[Render.PlacedItem] =
        let t = World.tileSize();
        let origin = View.boardOrigin(w);
        let ink = w#theme#paper;
        let xs = List.range(0, MapDoc.cols(w#map)) |> List.filterMap(c -> {
            let cx = origin#x + Int32.toFloat64(c) * t + t / 2.0;
            if (cx < 0.0 or cx >= World.width()) None
            else Some(mark(atlas, ink, "${c}", { x = cx - 3.0, y = 1.0 }))
        });
        let ys = List.range(0, MapDoc.rowCount(w#map)) |> List.filterMap(r -> {
            let cy = origin#y + Int32.toFloat64(r) * t + t / 2.0 - 3.0;
            if (cy < 0.0 or cy >= World.height()) None
            else Some(mark(atlas, ink, "${r}", { x = 1.0, y = cy }))
        });
        List.append(xs, ys)

    /// 数字 1 つ。すべての上（z=500）に、薄く（fade）重ねる — 盤の絵を隠さない。
    def mark(atlas: FontAtlas, ink: Color, label: String, at: Vec2.Vec2): Render.PlacedItem =
        { at = at, item = Render.textTinted(label, atlas, 6.0, ink, 500) |> Render.fade(0.6f32) }
}
