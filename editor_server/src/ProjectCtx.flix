// ProjectCtx — 対象ゲームプロジェクトの project.json から、プレビュー描画に必要な
// 設定 (設計解像度・背景色・フォント・テクスチャ) を引く。
// フォントやテクスチャの欠落では止めない — 編集途中のプロジェクトでもできる範囲で
// 描いて返し、欠けた分は warning の文言で編集画面へ伝える。

mod ProjectCtx {
    /// プレビュー描画に使うプロジェクト設定一式。
    /// `designW`/`designH`: 設計解像度 (px)。`clearColor`: 背景色。
    /// `fonts`/`textures`: project.json の manifest (パスは絶対パス化済み)。
    pub type alias Ctx = {
        designW    = Int32,
        designH    = Int32,
        clearColor = Color,
        fonts      = List[{name = String, path = String, fontSize = Float64}],
        textures   = List[{name = String, path = String, hasAlpha = Bool}]
    }

    /// project.json を読んで Ctx にする。読めない・崩れているは Err(理由)。
    pub def load(dir: String): Result[String, Ctx] \ IO =
        let loaded = run { ProjectLoader.loadProject(dir) } with Fs.FileRead.runWithIO;
        loaded
            |> Result.map(loadedProject -> {
                let config = loadedProject#config;
                { designW    = config#designWidth,
                  designH    = config#designHeight,
                  clearColor = config#clearColor,
                  fonts      = config#fontManifest,
                  textures   = config#textureManifest }
            })

    // ════════════════════════════════════════════════════════
    // フォント
    // ════════════════════════════════════════════════════════

    /// フォント解決の結果。
    /// `atlases`: ドキュメントが使うフォント名 → atlas (manifest に無い名前は代表フォントで埋める)。
    /// `primary`: ラスタライザに渡す代表 TTF とその atlas。プロジェクトに TTF が 1 本も
    /// 無いときだけ None (文字をラスタライズする材料が無い)。
    /// `warnings`: 欠落・代替の説明。
    pub type alias FontSetup = {
        atlases  = Map[String, FontAtlas],
        primary  = Option[{path = String, atlas = FontAtlas}],
        warnings = List[String]
    }

    /// ドキュメントが使うフォント名の一覧から atlas 表と代表フォントを組む。
    /// ラスタライザは TTF 1 本しか受けないので、複数フォントの使用は代表 1 本に寄せて warning にする。
    /// atlas は caches のレジストリ経由で引く (同じ TTF の焼き直しは mtime が変わったときだけ)。
    pub def fontSetup(usedFonts: List[String], dir: String, caches: Caches.Caches, ctx: Ctx): FontSetup \ IO =
        let used = List.distinct(usedFonts);
        let (primaryOpt, primaryWarnings) = primaryEntry(used, dir, ctx);
        match primaryOpt {
            case None        =>
                // 代表 TTF 無し: 計測はグリフ 0 の空 atlas で行う (呼び手がエラー応答に落とす)。
                { atlases  = used |> List.map(name -> (name, emptyAtlas())) |> List.toMap,
                  primary  = None,
                  warnings = primaryWarnings }
            case Some(entry) =>
                let primaryAtlas = Caches.fontAtlas(entry#path, caches);
                let multiWarnings =
                    if (List.length(used) > 1)
                        "multiple fonts used (${String.intercalate(", ", used)}) — preview draws every text with '${entry#name}'" :: Nil
                    else Nil;
                let folded = List.foldLeft(
                    (acc, name) -> resolveFont(name, entry#name, entry#path, primaryAtlas, caches, ctx, acc),
                    { byPath = Map#{entry#path => primaryAtlas},
                      byName = (Map.empty(): Map[String, FontAtlas]),
                      warnings = List.append(primaryWarnings, multiWarnings) },
                    used);
                { atlases  = folded#byName,
                  primary  = Some({path = entry#path, atlas = primaryAtlas}),
                  warnings = folded#warnings }
        }

    /// atlas 構築の途中経過。同じ TTF を二度焼かないよう byPath をレジストリにする
    /// (atlas 構築は全グリフ走査で重い)。
    type alias FontAcc = {
        byPath   = Map[String, FontAtlas],
        byName   = Map[String, FontAtlas],
        warnings = List[String]
    }

    /// フォント名 1 個を manifest から解決して acc に足す。manifest に無い名前は代表フォントで代替。
    def resolveFont(name: String, primaryName: String, primaryPath: String, primaryAtlas: FontAtlas,
                    caches: Caches.Caches, ctx: Ctx, acc: FontAcc): FontAcc \ IO =
        match List.findLeft(font -> font#name == name, ctx#fonts) {
            case None       =>
                { byName   = Map.insert(name, primaryAtlas, acc#byName),
                  warnings = List.append(acc#warnings,
                      "font '${name}' is not in project.json fonts — using '${primaryName}' instead" :: Nil)
                  | acc }
            case Some(font) => match Map.get(font#path, acc#byPath) {
                case Some(atlas) => { byName = Map.insert(name, atlas, acc#byName) | acc }
                case None        =>
                    let atlas = if (font#path == primaryPath) primaryAtlas
                                else Caches.fontAtlas(font#path, caches);
                    { byPath = Map.insert(font#path, atlas, acc#byPath),
                      byName = Map.insert(name, atlas, acc#byName)
                      | acc }
            }
        }

    /// ラスタライザに渡す代表フォントの manifest エントリを決める。
    /// 使うフォントの先頭 → manifest 先頭 → dir 内の TTF 探索、の順で拾う
    /// (manifest が空でも、プロジェクトに TTF が転がっていれば描いて返す)。
    def primaryEntry(usedFonts: List[String], dir: String, ctx: Ctx):
            (Option[{name = String, path = String}], List[String]) \ IO =
        let byUsed = usedFonts
            |> List.head
            |> Option.flatMap(name -> List.findLeft(font -> font#name == name, ctx#fonts));
        match (byUsed, List.head(ctx#fonts)) {
            case (Some(font), _)    => (Some({name = font#name, path = font#path}), Nil)
            case (None, Some(font)) => (Some({name = font#name, path = font#path}), Nil)
            case (None, None)       => match findAnyTtf(dir) {
                case Some(path) =>
                    (Some({name = "(project ttf)", path = path}),
                     "project.json has no fonts — using ${path} found in the project" :: Nil)
                case None       =>
                    (None, "project.json has no fonts and no .ttf was found — text cannot be drawn" :: Nil)
            }
        }

    /// dir 配下の TTF を 1 本探す (manifest 空プロジェクトの救済)。無ければ None。
    def findAnyTtf(dir: String): Option[String] \ IO =
        let found = run { Fs.Glob.glob(dir, "**/*.ttf") } with Fs.Glob.runWithIO;
        found |> Result.getWithDefault(Nil) |> List.head

    /// グリフ 0 の空 atlas。fontSize は文字サイズ換算の分母になるため 0 除算を避ける正の値にする。
    def emptyAtlas(): FontAtlas =
        { textureName = "font_ui", fontSize = 8.0, textureSize = 1.0,
          ascent = 0.0, descent = 0.0, lineGap = 0.0, glyphs = Map.empty() }

    // ════════════════════════════════════════════════════════
    // テクスチャ
    // ════════════════════════════════════════════════════════

    /// テクスチャ解決の結果。`infos`: 名前 → 実寸 (GPU が無いので id はダミーの 0 番)。
    pub type alias TextureSetup = {
        infos    = Map[String, GameEngine.TextureInfo],
        warnings = List[String]
    }

    /// ドキュメントが使うテクスチャ名の一覧から実寸表を組む。実寸は caches のレジストリ経由で引く
    /// (同じ画像のデコードは mtime が変わったときだけ)。
    /// manifest に無い・画像が読めない名前は表に載せず warning にする
    /// (寸法無しでも sprite 以外は描けるので、プレビュー全体は止めない)。
    pub def textureSetup(usedTextures: List[String], caches: Caches.Caches, ctx: Ctx): TextureSetup \ IO =
        List.foldLeft((acc, name) -> match List.findLeft(tex -> tex#name == name, ctx#textures) {
            case None      =>
                { warnings = List.append(acc#warnings,
                    "texture '${name}' is not in project.json textures" :: Nil) | acc }
            case Some(tex) => match Caches.imageSize(tex#path, caches) {
                case None             =>
                    { warnings = List.append(acc#warnings,
                        "texture '${name}' could not be read: ${tex#path}" :: Nil) | acc }
                case Some((wid, hei)) =>
                    { infos = Map.insert(name,
                        ({id = GpuHandle.wrapTextureId(0), width = wid, height = hei}: GameEngine.TextureInfo),
                        acc#infos) | acc }
            }
        }, ({infos = Map.empty(), warnings = Nil}: TextureSetup), List.distinct(usedTextures))

    /// ラスタライザに渡す 名前 → 画像パス の表 (manifest 全部)。
    pub def texturePaths(ctx: Ctx): Map[String, String] =
        ctx#textures |> List.map(tex -> (tex#name, tex#path)) |> List.toMap
}
