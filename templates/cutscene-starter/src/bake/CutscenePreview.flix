// CutscenePreview — イベントシーンの常駐する焼き係。重い仕度（フォントアトラス・
// World の読み込み）を起動時の 1 回だけ済ませて持ち続け、「この脚本を焼いて」と
// 頼まれるたびに**脚本だけ**読み直して GIF を焼く。
//
// なぜ常駐か: make cutscene の待ちのほとんどは毎回のコンパイルと JVM の立ち上げで、
// 演じて焼く時間そのものは秒の単位。立ち上げっぱなしにすれば、その待ちが最初の
// 1 回だけになり、脚本の編集ループが「保存 → curl → 目視」で秒単位に回る。
//
// 焼くのは単発の make cutscene（CutsceneBake）と同じ経路
// （Cutscene.framesOf → Bakery.bakeGif）なので、出る絵も同じ。
// Studio 向けの口が 2 つ足してある:
//   POST /cutscene?…&draft=1        … 下書き（等倍 + 粗い間引き）を debug/cutscene/draft/ へ
//   POST /cutscene/frame?…&cut=N    … カット N の最初の拍を PNG 1 枚だけ焼く
mod CutscenePreview {
    import java.io.File
    import java.lang.System

    /// 起動: make cutscene-server（headless）。ポートは環境変数 CUTSCENE_PORT（既定 8793）。
    /// 頼み方: curl -X POST 'http://127.0.0.1:8793/cutscene?file=assets/intro.cutscene.json'
    /// file 無しなら全シーン。応答は
    /// {"baked":[{"gif":…,"frames":…,"pngFrames":…,"stride":…,"draft":…,"notes":[…]}]}。
    pub def main(): Unit \ IO =
        discard (new File("debug/cutscene")).mkdirs();
        discard (new File("debug/cutscene/draft")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(Bake.ttf(), Bake.ttf());
        let w0 = Bake.loadWorld();
        let cfg = Bake.cfgOf("debug/cutscene", atlas, w0#theme#sky);
        let ctx = App.viewCtxOf(atlas, Bake.design());
        BakeService.serve(portFromEnv(), BakeService.idleSecondsFromEnv(), req ->
            handle(req,
                (draft, path) -> bakeOne(cfg, ctx, w0, draft, path),
                (path, cut) -> frameOne(cfg, ctx, w0, path, cut)))

    /// 環境変数 CUTSCENE_PORT から待ち受けるポートを読む（BakeService.portFromEnv の流儀。
    /// あちらは BAKE_PORT を見るので、他の常駐と同時に立てても口がぶつからない）。
    def portFromEnv(): Int32 \ IO =
        let value = System.getenv("CUTSCENE_PORT");
        if (Object.isNull(value)) 8793
        else Int32.fromString(value) |> Option.getWithDefault(8793)

    /// 頼まれごとの仕分け。焼く仕事そのものは bakeOne（脚本パス → 1 件ぶんの JSON）と
    /// frameOne（脚本パス + カット番号 → PNG 1 枚ぶんの JSON）が持つ。
    def handle(req: BakeService.Request, bakeOne: (Bool, String) -> String \ IO,
               frameOne: (String, Int32) -> String \ IO): BakeService.Reply \ IO =
        match (req#method, req#path) {
            case ("GET", "/health") =>
                BakeService.jsonReply(200, "{\"ok\":true,\"scenes\":${scenesJson()}}")
            case (_, "/cutscene/frame") => frame(req, frameOne)
            case (_, "/cutscene")       => cutscene(req, bakeOne)
            case _                      =>
                BakeService.textReply(404, "text/plain; charset=utf-8", "not found\n")
        }

    def scenesJson(): String =
        CutsceneDoc.paths() |> List.map(p -> "\"${p}\"") |> List.join(",") |> (s -> "[${s}]")

    /// file= が有ればその 1 本、無ければ全シーン。draft=1 なら下書き（速い）。
    /// 知らないパスは焼かずに理由を返す
    /// （常駐は死なせない — 分かる誤りは 500 に落とす前にこちらで報せる）。
    def cutscene(req: BakeService.Request, bakeOne: (Bool, String) -> String \ IO): BakeService.Reply \ IO =
        let draft = isDraft(req);
        match Map.get("file", req#params) {
            case Some(f) =>
                if (List.memberOf(f, CutsceneDoc.paths()))
                    BakeService.jsonReply(200, "{\"baked\":[${bakeOne(draft, f)}]}")
                else BakeService.textReply(404, "text/plain; charset=utf-8",
                    "知らない脚本: ${f}（CutsceneDoc.paths() に無い）\n")
            case None    =>
                let objs = CutsceneDoc.paths() |> List.map(p -> bakeOne(draft, p)) |> List.join(",");
                BakeService.jsonReply(200, "{\"baked\":[${objs}]}")
        }

    /// draft=1（0 以外の何か）で下書きモード。無指定は仕上げ。
    def isDraft(req: BakeService.Request): Bool =
        match Map.get("draft", req#params) {
            case Some("0") => false
            case Some(_)   => true
            case None      => false
        }

    /// カット 1 つの最初の拍を PNG 1 枚だけ焼く口（Studio が「カット行を選ぶと
    /// その時点の絵が出る」に使う）。cut= はカットの通し番号（1 始まり。脚本と同じ数え方）。
    def frame(req: BakeService.Request, frameOne: (String, Int32) -> String \ IO): BakeService.Reply \ IO =
        match Map.get("file", req#params) {
            case Some(f) =>
                if (List.memberOf(f, CutsceneDoc.paths()))
                    BakeService.jsonReply(200, frameOne(f, cutOf(req)))
                else BakeService.textReply(404, "text/plain; charset=utf-8",
                    "知らない脚本: ${f}（CutsceneDoc.paths() に無い）\n")
            case None    =>
                BakeService.textReply(400, "text/plain; charset=utf-8",
                    "file= で脚本を指定して（例 /cutscene/frame?file=assets/intro.cutscene.json&cut=3）\n")
        }

    /// cut= の読み。数字でない・無いは 1 番（脚本の最初のカット）。
    def cutOf(req: BakeService.Request): Int32 =
        Map.get("cut", req#params) |> Option.flatMap(Int32.fromString)
            |> Option.getWithDefault(1)

    /// 脚本 1 本を焼いて、その報告（JSON オブジェクト 1 個ぶんの文字列）を返す。
    /// 脚本は**その都度読み直す**ので、常駐中の保存がそのまま次の焼きに反映される。
    /// draft は等倍（scale 1）+ 粗い間引き（stride 4）で debug/cutscene/draft/ へ —
    /// 仕上げの GIF を上書きせずに、通しの動きだけ数秒で確かめる口。
    /// notes には読めない JSON・飛ばしたカットの報せが載る（無音の fail-open にしない）。
    def bakeOne(cfg: Bakery.BakeConfig, ctx: App.ViewCtx, w0: World.World,
                draft: Bool, path: String): String \ IO =
        let (doc, warnings) = CutsceneBake.readScript(path);
        let played = Cutscene.framesOf(doc, w0);
        let baked = if (draft) { scale = 1, outDir = "debug/cutscene/draft" | cfg } else cfg;
        let stride = if (draft) 4 else 2;
        let strip = Bakery.bakeGif(baked, played#frames, stride,
            w -> Render.draw(View.frame(ctx, w)), doc#id);
        let notes = List.append(warnings, played#notes)
            |> List.map(n -> "\"${escape(n)}\"") |> List.join(",");
        "{\"gif\":\"${baked#outDir}/${doc#id}.gif\",\"frames\":${List.length(played#frames)},"
            + "\"pngFrames\":${strip#frameCount},\"stride\":${stride},\"draft\":${draft},"
            + "\"notes\":[${notes}]}"

    /// カット cut の最初の拍まで演じ、その 1 コマだけを PNG に焼く。
    /// 演じるのは通しの焼きと同じ道具（Cutscene.perform / idle を SceneSeq.tick で回す）
    /// なので、出る絵も同じ。cut が範囲の外なら届いた所（最後の状態）を焼いて notes で報せる。
    def frameOne(cfg: Bakery.BakeConfig, ctx: App.ViewCtx, w0: World.World,
                 path: String, cut: Int32): String \ IO =
        let (doc, warnings) = CutsceneBake.readScript(path);
        let (w, reached) = worldAtCut(doc, w0, cut);
        let name = "${doc#id}-cut${cut}";
        let (drawables, polygons) = Render.draw(View.frame(ctx, w));
        Bakery.renderPng(cfg, drawables, polygons, name);
        let extra = if (reached) Nil
                    else "カット${cut} に届かない(脚本の外か、途中で打ち切った)ので最後の状態を焼いた" :: Nil;
        let notes = List.append(warnings, extra)
            |> List.map(n -> "\"${escape(n)}\"") |> List.join(",");
        "{\"png\":\"${cfg#outDir}/${name}.png\",\"cut\":${cut},\"notes\":[${notes}]}"

    /// カット cut の最初の拍の World と「そこに届いたか」。純粋・ヘッドレスなので
    /// 数百 tick は一瞬。上限は通しの焼きと同じ maxFrames（暴走の安全弁）。
    def worldAtCut(doc: CutsceneDoc.Doc, w0: World.World, cut: Int32): (World.World, Bool) =
        seek(cut, Cutscene.maxFrames(), SceneSeq.start(doc#cuts), Cutscene.stage(doc, w0))

    def seek(cut: Int32, budget: Int32,
             s: SceneSeq.State[CutsceneDoc.Guarded, Cutscene.Progress],
             w: World.World): (World.World, Bool) =
        if (SceneSeq.done(s) or budget <= 0) (w, false)
        else {
            let (s2, w2) = SceneSeq.tick(Cutscene.perform, Cutscene.idle, Cutscene.dt(), s, w);
            if (s#at >= cut) (w2, true) else seek(cut, budget - 1, s2, w2)
        }

    /// JSON の文字列に入れて壊れる 2 文字だけ写す（報せは日本語の平文なのでこれで足りる）。
    def escape(s: String): String =
        s |> String.replace(src = "\\", dst = "\\\\")
          |> String.replace(src = "\"", dst = "\\\"")
}
