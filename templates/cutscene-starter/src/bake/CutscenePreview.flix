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
mod CutscenePreview {
    import java.io.File
    import java.lang.System

    /// 起動: make cutscene-server（headless）。ポートは環境変数 CUTSCENE_PORT（既定 8793）。
    /// 頼み方: curl -X POST 'http://127.0.0.1:8793/cutscene?file=assets/intro.cutscene.json'
    /// file 無しなら全シーン。応答は {"baked":[{"gif":…,"frames":…,"notes":[…]}]}。
    pub def main(): Unit \ IO =
        discard (new File("debug/cutscene")).mkdirs();
        let atlas = HeadlessFont.buildUiAtlas(Bake.ttf(), Bake.ttf());
        let w0 = Bake.loadWorld();
        let cfg = Bake.cfgOf("debug/cutscene", atlas, w0#theme#sky);
        let ctx = App.viewCtxOf(atlas, Bake.design());
        BakeService.serve(portFromEnv(), BakeService.idleSecondsFromEnv(), req ->
            handle(req, path -> bakeOne(cfg, ctx, w0, path)))

    /// 環境変数 CUTSCENE_PORT から待ち受けるポートを読む（BakeService.portFromEnv の流儀。
    /// あちらは BAKE_PORT を見るので、他の常駐と同時に立てても口がぶつからない）。
    def portFromEnv(): Int32 \ IO =
        let value = System.getenv("CUTSCENE_PORT");
        if (Object.isNull(value)) 8793
        else Int32.fromString(value) |> Option.getWithDefault(8793)

    /// 頼まれごとの仕分け。焼く仕事そのものは bakeOne（脚本パス → 1 件ぶんの JSON）が持つ。
    def handle(req: BakeService.Request, bakeOne: String -> String \ IO): BakeService.Reply \ IO =
        match (req#method, req#path) {
            case ("GET", "/health") =>
                BakeService.jsonReply(200, "{\"ok\":true,\"scenes\":${scenesJson()}}")
            case (_, "/cutscene")   => cutscene(req, bakeOne)
            case _                  =>
                BakeService.textReply(404, "text/plain; charset=utf-8", "not found\n")
        }

    def scenesJson(): String =
        CutsceneDoc.paths() |> List.map(p -> "\"${p}\"") |> List.join(",") |> (s -> "[${s}]")

    /// file= が有ればその 1 本、無ければ全シーン。知らないパスは焼かずに理由を返す
    /// （常駐は死なせない — 分かる誤りは 500 に落とす前にこちらで報せる）。
    def cutscene(req: BakeService.Request, bakeOne: String -> String \ IO): BakeService.Reply \ IO =
        match Map.get("file", req#params) {
            case Some(f) =>
                if (List.memberOf(f, CutsceneDoc.paths()))
                    BakeService.jsonReply(200, "{\"baked\":[${bakeOne(f)}]}")
                else BakeService.textReply(404, "text/plain; charset=utf-8",
                    "知らない脚本: ${f}（CutsceneDoc.paths() に無い）\n")
            case None    =>
                let objs = CutsceneDoc.paths() |> List.map(bakeOne) |> List.join(",");
                BakeService.jsonReply(200, "{\"baked\":[${objs}]}")
        }

    /// 脚本 1 本を焼いて、その報告（JSON オブジェクト 1 個ぶんの文字列）を返す。
    /// 脚本は**その都度読み直す**ので、常駐中の保存がそのまま次の焼きに反映される。
    /// notes には読めない JSON・飛ばしたカットの報せが載る（無音の fail-open にしない）。
    def bakeOne(cfg: Bakery.BakeConfig, ctx: App.ViewCtx, w0: World.World,
                path: String): String \ IO =
        let (doc, warnings) = CutsceneBake.readScript(path);
        let played = Cutscene.framesOf(doc, w0);
        discard Bakery.bakeGif(cfg, played#frames, 2,
            w -> Render.draw(View.frame(ctx, w)), doc#id);
        let notes = List.append(warnings, played#notes)
            |> List.map(n -> "\"${escape(n)}\"") |> List.join(",");
        "{\"gif\":\"${cfg#outDir}/${doc#id}.gif\",\"frames\":${List.length(played#frames)},\"notes\":[${notes}]}"

    /// JSON の文字列に入れて壊れる 2 文字だけ写す（報せは日本語の平文なのでこれで足りる）。
    def escape(s: String): String =
        s |> String.replace(src = "\\", dst = "\\\\")
          |> String.replace(src = "\"", dst = "\\\"")
}
