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
    def readScript(path: String): (CutsceneDoc.Doc, List[String]) \ IO =
        let readResult = run { Fs.ReadFile.read(path) } with Fs.ReadFile.runWithFileRead
            with Fs.FileRead.runWithIO;
        let text = readResult |> Result.toOption |> Option.getWithDefault("");
        match CutsceneDoc.fromJson(text) {
            case None      => (CutsceneDoc.defaults(),
                               "JSON が読めないので既定(空のシーン)へ倒した" :: Nil)
            case Some(doc) => (doc, Nil)
        }
}
