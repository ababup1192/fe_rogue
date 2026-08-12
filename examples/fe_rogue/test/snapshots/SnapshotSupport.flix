// SnapshotSupport — UI 描画スナップショットの土台。
//
//  - withMockGame  : GL 無しの GameEngine.Game handler（renderUi に必要な getFontAtlas /
//                    getTextureInfo だけ本物のメトリクス、他は無害スタブ）
//  - buildTexture* : project.json のテクスチャ名 → 実 PNG 寸法 / パスの表
//  - formatScene   : List[Drawable]+polygons を決定的なテキストへ（float は小数2桁）
//  - snapshot      : golden と比較し、PNG を build/snapshots へ生成する（更新モード対応）
//
// カタログ→HTML サイトの生成は SnapshotCatalog（目録）+ SnapshotSite（汎用生成器）が担う。
//
// golden は test/snapshots/<name>.golden.txt（コミット対象）。PNG は build/snapshots/（.gitignore）。
mod SnapshotSupport {
    import java.lang.{System => JSystem}
    import java.io.File
    import javax.imageio.ImageIO

    /// スナップショット 1 枚を生成するのに要る共有コンテキスト（毎回作り直さず使い回す）。
    pub type alias Ctx = {
        atlas       = FontAtlas,
        atlasDim    = Float64,
        ttfPath     = String,
        texInfo     = Map[String, GameEngine.TextureInfo],
        texPaths    = Map[String, String],
        background  = Color,
        scale       = Int32,
        design      = Vec2.Vec2
    }

    // ════════════════════════════════════════════════════════
    // mock GameEngine.Game
    // ════════════════════════════════════════════════════════

    /// GL 無しの GameEngine.Game。renderUi が触るのは getFontAtlas / getTextureInfo のみだが、
    /// handler は全 operation を実装する必要がある（dodge の runHeadless mock に倣う）。
    pub def withMockGame(atlas: FontAtlas, texInfo: Map[String, GameEngine.TextureInfo],
                         f: Unit -> a \ ef + GameEngine.Game): a \ ef =
        run f() with handler GameEngine.Game {
            def renderCommands(_, _, _, _, k)  = k(())
            def initTileBuffer(_, k)        = k((GpuHandle.wrapTileVao(0i32), 0i32))
            def updateTileBuffer(_, _, k)   = k((GpuHandle.wrapTileVao(0i32), 0i32))
            def shouldClose(k)              = k(false)
            def getDeltaTime(k)             = k(Duration.seconds(0.1))
            def isKeyPressed(_, k)          = k(false)
            def getMousePosition(k)         = k({x = 0.0, y = 0.0})
            def isMouseButtonPressed(_, k)  = k(false)
            def consumeScrollDelta(k)       = k(0.0)
            def getFontAtlas(_, k)          = k(atlas)
            def ensureGlyphs(_, _cps, k)    = k(())
            def getViewportRect(k)          = k({position = Vec2.zero(), size = {x = 240.0, y = 128.0}})
            def getTextureInfo(name, k)     = k(Map.get(name, texInfo))
            def ensureTexture(_, _, _, _, _, k) = k(())
            def setCursor(_, k)             = k(())
            def setCursorVisible(_, k)      = k(())
            def setFullscreen(_, k)         = k(())
            def isFullscreen(k)             = k(false)
            def saveAnnotation(_, k)        = k(None)
            def setDebugBadge(_, k)         = k(())
        }

    // ════════════════════════════════════════════════════════
    // テクスチャ表（project.json 由来）
    // ════════════════════════════════════════════════════════

    /// テクスチャ論理名 → プロジェクトルート相対パス（project.json の "textures" と一致）。
    def manifest(): List[(String, String)] =
        ("inca_tileset",          "assets/sprites/Inca_front_by_Kronbits-extended.png") ::
        ("character_sheet",       "assets/sprites/character_sheet_grid_16.png") ::
        ("arrow",                 "assets/sprites/arrow.png") ::
        ("flag",                  "assets/sprites/flag.png") ::
        ("tilemap_floor",         "assets/sprites/tilemap.png") ::
        ("tileset_dungeon_green", "assets/sprites/tileset_dungeon_green.png") ::
        ("roguelike_weapons",     "assets/sprites/roguelikeChar_transparent.png") ::
        ("item_potions",          "assets/sprites/Item_Sheet_Potions.png") ::
        ("item_skills",           "assets/sprites/Item_Sheet_Skills.png") ::
        ("item_weapons",          "assets/sprites/Item_Sheet_Weapons.png") ::
        ("item_icons",            "assets/sprites/Tex_Item_Icons.png") ::
        ("fe_archer",             "assets/sprites/fe_archer.png") ::
        ("stairs",                "assets/sprites/stairs.png") ::
        ("rogues",                "assets/sprites/rogues.png") :: Nil

    /// font_ui のプレースホルダパス。HeadlessFont はもうこのパスに画像を書かない
    /// （SoftRaster が直接 drawString するためアトラス画像が不要 — HeadlessFont.flix 冒頭コメント参照）。
    /// ここでは「font_ui というテクスチャ名がある」ことを buildTexturePaths/buildTextureInfo に
    /// 伝えるためだけのキーとして残す。実ファイルが無くても loadTextures は存在チェックで無害にスキップする。
    pub def atlasPngPath(): String = "build/snapshots/_font_ui.png"

    /// テクスチャ名 → 実ファイルパス。font_ui は上記プレースホルダへ向ける（画像は実在しない）。
    pub def buildTexturePaths(): Map[String, String] =
        manifest()
            |> List.foldLeft((acc, pair) -> let (name, rel) = pair; Map.insert(name, AssetPath.resolve(rel), acc), Map.empty())
            |> Map.insert("font_ui", atlasPngPath())

    /// テクスチャ名 → TextureInfo（region UV 計算に使う元画像寸法）。PNG を読んで実寸を得る。
    /// font_ui はファイルを読まずアトラス一辺で確定（画像が無いテクスチャ名のため特別扱い）。
    /// それ以外で読めないテクスチャは表に入れない（getTextureInfo が None を返す）。
    pub def buildTextureInfo(paths: Map[String, String], atlasDim: Float64): Map[String, GameEngine.TextureInfo] \ IO =
        Map.foldLeftWithKey((acc, name, path) ->
            if (name == "font_ui")
                Map.insert(name, ({id = GpuHandle.wrapTextureId(0i32), width = atlasDim, height = atlasDim}: GameEngine.TextureInfo), acc)
            else match readDims(path) {
                case None            => acc
                case Some((wf, hf)) => Map.insert(name, ({id = GpuHandle.wrapTextureId(0i32), width = wf, height = hf}: GameEngine.TextureInfo), acc)
            }, (Map.empty(): Map[String, GameEngine.TextureInfo]), paths)

    /// PNG の寸法を読む。存在しない・読めないときは None。
    def readDims(path: String): Option[(Float64, Float64)] \ IO =
        let file = new File(path);
        if (file.exists()) {
            let img = ImageIO.read(file);
            if (Object.isNull(img)) None
            else Some((Int32.toFloat64(img.getWidth()), Int32.toFloat64(img.getHeight())))
        } else None

    // ════════════════════════════════════════════════════════
    // GIF の永続化（test/snapshots/gifs/ → build/snapshots/）
    // ════════════════════════════════════════════════════════
    //
    // GIF は PNG と違い毎回生成し直すには重いので、生成物を test/snapshots/gifs/（コミット対象）に
    // 置く。SnapshotSite は build/snapshots/ 直下のファイル存在で表示可否を決めるので、サイト生成の
    // 直前に gifs/ から build/snapshots/ へコピーする（FE_ROGUE_SNAPSHOT_GIF=1 の新規生成後も、
    // 素の flix test で既存 GIF を表示するときも、このコピーだけを通る）。

    /// GIF の永続置き場（コミット対象）。
    pub def gifSourceDir(): String = "test/snapshots/gifs"

    /// `names` の GIF を test/snapshots/gifs/ から build/snapshots/ へコピーする。
    /// 出典が無い（未生成）名前は無視する（SnapshotSite が generateHint 案内を出す）。
    pub def syncGifs(names: List[String]): Unit \ IO + Fs.FileWrite =
        List.forEach(copyGifIfPresent, names)

    /// 1 本の GIF を上書きコピーする。存在チェックと出力先ディレクトリ作成は java.io.File
    /// （readDims / SnapshotSite.fileExists と同じ流儀）、コピー本体は Fs.CopyFile。
    def copyGifIfPresent(name: String): Unit \ IO + Fs.FileWrite =
        let srcPath = "${gifSourceDir()}/${name}.gif";
        let src = new File(srcPath);
        if (src.exists()) {
            let dst = new File("build/snapshots/${name}.gif");
            let parent = dst.getParentFile();
            if (not Object.isNull(parent)) discard parent.mkdirs() else ();
            run {
                discard Fs.CopyFile.copyWith({src = srcPath}, "build/snapshots/${name}.gif",
                    Set#{Fs.CopyOption.CopyOption.ReplaceExisting})
            } with Fs.CopyFile.runWithFileWrite
        } else ()

    // ════════════════════════════════════════════════════════
    // フィルムストリップ情報の読み取り（ストリップ PNG が生成済みであれば）
    // ════════════════════════════════════════════════════════

    /// `stripPath` にストリップ PNG があれば、その実寸から SnapshotSite.Filmstrip を組む
    /// （frameCount = 画像幅 ÷ frameW）。無ければ None（カードは従来の GIF 表示に落ちる）。
    /// `stripFile` は outDir 相対のファイル名（HTML の background-image が指すパス）。
    pub def readFilmstrip(stripPath: String, stripFile: String,
                          frameW: Int32, frameH: Int32, fps: Int32): Option[SnapshotSite.Filmstrip] \ IO =
        match readDims(stripPath) {
            case None            => None
            case Some((wf, _hf)) =>
                let w = Float64.tryToInt32(wf) |> Option.getWithDefault(0i32);
                if (w <= 0i32 or frameW <= 0i32) None
                else Some({strip = stripFile, frameCount = w / frameW,
                           frameW = frameW, frameH = frameH, fps = fps})
        }

    // ════════════════════════════════════════════════════════
    // 1 枚のスナップショット処理
    // ════════════════════════════════════════════════════════

    /// UI ツリー `ui` を描画し、golden 比較 + PNG 出力を行う。
    /// 一致すれば None、不一致なら差分メッセージ Some を返す（更新モードでは golden を書き直して None）。
    pub def snapshot(ctx: Ctx, name: String,
                     rendered: {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]}):
            Option[String] \ (IO + Fs.FileRead + Fs.FileWrite) =
        let text = formatScene(ctx#atlasDim, rendered);
        // PNG は毎回生成する（目視確認用・build 配下）。
        SoftRaster.render({
            drawables = rendered#drawables, polygons = rendered#polygons,
            design = ctx#design, scale = ctx#scale, background = ctx#background,
            texturePath = ctx#texPaths, fontTtf = ctx#ttfPath, fontAtlas = ctx#atlas,
            outPath = pngPath(name)
        });
        // golden と突き合わせる。
        match readGolden(name) {
            case Some(expected) =>
                if (normalize(expected) == normalize(text))
                    None
                else if (updateMode()) {
                    writeGolden(name, text);
                    None
                } else
                    Some(diffMessage(name, normalize(expected), normalize(text)))
            case None =>
                // golden 不在/読取不可: 生成して（更新モードでなければ）fail させる。
                writeGolden(name, text);
                if (updateMode()) None
                else Some("snapshot '${name}': 新規 golden を生成しました。内容を確認して "
                          + "test/snapshots/${name}.golden.txt をコミットするか、"
                          + "FE_ROGUE_SNAPSHOT_UPDATE=1 で再実行してください。")
        }

    def pngPath(name: String): String = "build/snapshots/${name}.png"
    def goldenPath(name: String): String = "test/snapshots/${name}.golden.txt"

    /// 環境変数 FE_ROGUE_SNAPSHOT_UPDATE が空でなければ更新モード（golden を上書きして pass）。
    def updateMode(): Bool \ IO =
        let v = JSystem.getenv("FE_ROGUE_SNAPSHOT_UPDATE");
        not Object.isNull(v) and not String.isEmpty(v)

    def readGolden(name: String): Option[String] \ Fs.FileRead =
        let result = run { Fs.ReadFile.read(goldenPath(name)) } with Fs.ReadFile.runWithFileRead;
        Result.toOption(result)

    def writeGolden(name: String, content: String): Unit \ Fs.FileWrite =
        run { discard Fs.WriteFile.write({str = content}, goldenPath(name)) } with Fs.WriteFile.runWithFileWrite

    /// 末尾改行差を吸収する。
    def normalize(s: String): String = String.trimRight(s)

    /// 最初に食い違う行を指摘するメッセージ。
    def diffMessage(name: String, expected: String, actual: String): String =
        let es = String.lines(expected);
        let as_ = String.lines(actual);
        let firstDiff = findFirstDiff(0, es, as_);
        match firstDiff {
            case None => "snapshot '${name}': 行数のみ相違 (expected ${List.length(es)} / actual ${List.length(as_)})"
            case Some(i) =>
                let e = List.nth(i, es) |> Option.getWithDefault("<なし>");
                let a = List.nth(i, as_) |> Option.getWithDefault("<なし>");
                "snapshot '${name}' が golden と相違。最初の相違は ${i + 1} 行目:\n"
                    + "  expected: ${e}\n  actual  : ${a}"
        }

    def findFirstDiff(i: Int32, es: List[String], as_: List[String]): Option[Int32] =
        match (es, as_) {
            case (e :: ert, a :: art) => if (e != a) Some(i) else findFirstDiff(i + 1, ert, art)
            case (Nil, Nil)           => None
            case _                    => Some(i)
        }

    // ════════════════════════════════════════════════════════
    // 決定的フォーマット
    // ════════════════════════════════════════════════════════

    /// テキスト実行時に隣り合う同 z・同色のグリフ列をまとめる集約子。
    type alias TextRun = {
        z = Int32, colorHex = String,
        count = Int32, minX = Float64, minY = Float64, maxX = Float64, maxY = Float64
    }

    /// {drawables, polygons} を決定的な複数行テキストへ射影する。
    /// - box    : 1 行（pos/size/色/枠/z）
    /// - sprite : 1 行（tex/pos/scale/uv/色/z）
    /// - text   : 連続する font_ グリフ列を 1 行に集約（個数 + 外接矩形 + 色 + z）
    /// - poly   : 1 行（頂点数 + 外接矩形 + 色 + z）
    /// 描画順（z, 追加順）にソートしてから出力する。
    pub def formatScene(atlasDim: Float64,
                        rendered: {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]}):
            String =
        let tagged = List.append(
            List.map(d -> (Result.Ok(d): Result[GameEngine.PolygonRenderCmd, GameEngine.Drawable]), rendered#drawables),
            List.map(p -> (Result.Err(p): Result[GameEngine.PolygonRenderCmd, GameEngine.Drawable]), rendered#polygons));
        let sorted = tagged
            |> List.zipWithIndex
            |> List.sortBy(ix -> let (idx, item) = ix; (zOf(item), idx))
            |> List.map(ix -> let (_, item) = ix; item);
        let folded = List.foldLeft((acc, item) -> stepFormat(atlasDim, acc, item),
            ({lines = (Nil: List[String]), pending = (None: Option[TextRun])}), sorted);
        let finalLines = flushRun(folded#pending, folded#lines);
        String.unlines(List.reverse(finalLines))

    def zOf(item: Result[GameEngine.PolygonRenderCmd, GameEngine.Drawable]): Int32 =
        match item {
            case Result.Ok(d)  => d#zIndex
            case Result.Err(p) => p#zIndex
        }

    /// 集約状態を 1 要素進める。glyph なら run に足し、それ以外は run を flush してから 1 行足す。
    def stepFormat(atlasDim: Float64,
                   acc: {lines = List[String], pending = Option[TextRun]},
                   item: Result[GameEngine.PolygonRenderCmd, GameEngine.Drawable]):
            {lines = List[String], pending = Option[TextRun]} =
        match item {
            case Result.Err(poly) =>
                {lines = polyLine(poly) :: flushRun(acc#pending, acc#lines), pending = None}
            case Result.Ok(d) =>
                if (isFont(d))
                    stepFont(atlasDim, acc, d)
                else if (String.isEmpty(d#texture))
                    {lines = boxLine(d) :: flushRun(acc#pending, acc#lines), pending = None}
                else
                    {lines = spriteLine(d) :: flushRun(acc#pending, acc#lines), pending = None}
        }

    def isFont(d: GameEngine.Drawable): Bool = String.startsWith({prefix = "font_"}, d#texture)

    /// glyph 1 個を集約に取り込む。直前 run と同じ z・色なら伸ばし、違えば直前 run を flush して
    /// 新しい run を始める（異なるラベルが混ざらないよう色・z で切る）。
    def stepFont(atlasDim: Float64,
                 acc: {lines = List[String], pending = Option[TextRun]},
                 d: GameEngine.Drawable): {lines = List[String], pending = Option[TextRun]} =
        let cHex = colorHex(d#color);
        match acc#pending {
            case Some(cur) =>
                if (cur#z == d#zIndex and cur#colorHex == cHex)
                    {lines = acc#lines, pending = Some(growRun(atlasDim, cur, d))}
                else
                    {lines = flushRun(acc#pending, acc#lines), pending = Some(freshRun(atlasDim, d))}
            case None =>
                {lines = acc#lines, pending = Some(freshRun(atlasDim, d))}
        }

    /// 既存 run にグリフの外接矩形を足す。
    def growRun(atlasDim: Float64, cur: TextRun, d: GameEngine.Drawable): TextRun =
        let gx1 = d#position#x + d#scale#x * atlasDim;
        let gy1 = d#position#y + d#scale#y * atlasDim;
        { count = cur#count + 1,
          minX = Float64.min(cur#minX, d#position#x), minY = Float64.min(cur#minY, d#position#y),
          maxX = Float64.max(cur#maxX, gx1), maxY = Float64.max(cur#maxY, gy1) | cur }

    /// 新しい run をグリフ 1 個から作る。
    def freshRun(atlasDim: Float64, d: GameEngine.Drawable): TextRun =
        { z = d#zIndex, colorHex = colorHex(d#color), count = 1,
          minX = d#position#x, minY = d#position#y,
          maxX = d#position#x + d#scale#x * atlasDim, maxY = d#position#y + d#scale#y * atlasDim }

    /// run を 1 行に確定して lines（逆順）に積む。空 run は素通し。
    def flushRun(cur: Option[TextRun], lines: List[String]): List[String] =
        match cur {
            case None    => lines
            case Some(r) =>
                let line = "text   z=${r#z} n=${r#count} bbox=(${fmt2(r#minX)},${fmt2(r#minY)})-"
                    + "(${fmt2(r#maxX)},${fmt2(r#maxY)}) rgb=${r#colorHex}";
                line :: lines
        }

    def boxLine(d: GameEngine.Drawable): String =
        let (corner, bw, bcol, ba) = match d#style {
            case Some(st) => (st#cornerRadius, st#borderWidth, colorHex(st#borderColor), st#borderAlpha)
            case None     => (0.0, 0.0, "-", 0.0f32)
        };
        "box    z=${d#zIndex} pos=(${fmt2(d#position#x)},${fmt2(d#position#y)}) "
            + "size=(${fmt2(d#scale#x)},${fmt2(d#scale#y)}) rgb=${colorHex(d#color)} "
            + "a=${fmt2(Float32.toFloat64(d#alpha))} corner=${fmt2(corner)} "
            + "border=${fmt2(bw)}/${bcol}/${fmt2(Float32.toFloat64(ba))}"

    def spriteLine(d: GameEngine.Drawable): String =
        "sprite z=${d#zIndex} tex=${d#texture} pos=(${fmt2(d#position#x)},${fmt2(d#position#y)}) "
            + "scale=(${fmt2(d#scale#x)},${fmt2(d#scale#y)}) "
            + "uvOff=(${fmt2(d#uvOffset#x)},${fmt2(d#uvOffset#y)}) "
            + "uvScale=(${fmt2(d#uvScale#x)},${fmt2(d#uvScale#y)}) rgb=${colorHex(d#color)} "
            + "a=${fmt2(Float32.toFloat64(d#alpha))} centered=${d#centered}"

    def polyLine(p: GameEngine.PolygonRenderCmd): String =
        let xs = List.map(v -> v#x, p#vertices);
        let ys = List.map(v -> v#y, p#vertices);
        let minX = List.foldLeft(Float64.min, 1.0e9, xs);
        let minY = List.foldLeft(Float64.min, 1.0e9, ys);
        let maxX = List.foldLeft(Float64.max, -1.0e9, xs);
        let maxY = List.foldLeft(Float64.max, -1.0e9, ys);
        "poly   z=${p#zIndex} n=${List.length(p#vertices)} "
            + "bbox=(${fmt2(minX)},${fmt2(minY)})-(${fmt2(maxX)},${fmt2(maxY)}) "
            + "rgb=${colorHex(p#color)} a=${fmt2(Float32.toFloat64(p#alpha))}"

    // ── 数値・色フォーマット ──

    /// Float64 を符号付き小数2桁固定に。FP ノイズを golden から締め出す。
    def fmt2(x: Float64): String =
        let neg = x < 0.0;
        let a = Float64.abs(x);
        let scaled = roundToInt(a * 100.0);
        let ip = scaled / 100i32;
        let fp = scaled - ip * 100i32;
        let body = "${ip}.${pad2(fp)}";
        if (neg and scaled != 0i32) "-${body}" else body

    def pad2(v: Int32): String = if (v < 10i32) "0${v}" else "${v}"

    def roundToInt(x: Float64): Int32 =
        Float64.tryToInt32(x + 0.5) |> Option.getWithDefault(0i32)

    /// Color を #rrggbb に。
    def colorHex(c: Color): String =
        "#${hex2(byteOf(c#r))}${hex2(byteOf(c#g))}${hex2(byteOf(c#b))}"

    def byteOf(x: Float32): Int32 =
        Int32.max(0i32, Int32.min(255i32, roundToInt(Float32.toFloat64(x) * 255.0)))

    def hex2(v: Int32): String = "${hexDigit(v / 16i32)}${hexDigit(Int32.remainder(v, 16i32))}"

    def hexDigit(n: Int32): Char =
        List.nth(n, String.toList("0123456789abcdef")) |> Option.getWithDefault('0')
}
