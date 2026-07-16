// Caches — プレビュー要求のたびに作り直すと重いものを、リクエストをまたいで覚える台帳。
// エディタは打鍵ごと (300ms debounce) にプレビューを要求するので、フォント atlas
// (TTF 全グリフ走査) とテクスチャ実寸 (画像デコード) の作り直しが応答時間を支配する。
// キーはファイルパスで、値に mtime の印を添える。印が今のファイルと違ったら作り直すので、
// フォントや画像を差し替えれば次の要求から新しい中身が反映される。

mod Caches {
    import java.io.File
    import javax.imageio.ImageIO
    import java.util.concurrent.{ConcurrentHashMap => JMap}

    /// mtime の印付きの値。印が今のファイルと違ったら作り直しの合図。
    pub type alias Stamped[a] = { mtime = Int64, value = a }

    /// キャッシュ一式。Editor.serve が起動時に 1 回だけ作り、リクエスト処理へ引き回す。
    // WhyNot: ConcurrentHashMap を選んだのは同期のためではない — サーバは executor 無し (null) の
    // 1 スレッド直列で、同時アクセスは起きない。リクエストをまたいで生きる可変の入れ物が
    // Flix 側に無い (Ref は region の寿命に縛られる) ので、Java の Map を器として借りている。
    pub type alias Caches = {
        fontAtlases  = JMap[String, Stamped[FontAtlas]],
        textureSizes = JMap[String, Stamped[(Float64, Float64)]]
    }

    /// 空のキャッシュ一式を作る。
    pub def make(): Caches \ IO =
        { fontAtlases = new JMap(), textureSizes = new JMap() }

    /// TTF パスから FontAtlas を引く。台帳に無い・ファイルが更新された、のときだけ焼き直す。
    // WhyNot: キーに fontSize を含めない — 焼き込みサイズは HeadlessFont 側の固定値で、
    // manifest の fontSize は表示時の縮小倍率にしか使われず、atlas の中身を変えないため。
    pub def fontAtlas(ttfPath: String, caches: Caches): FontAtlas \ IO =
        let file = new File(ttfPath);
        let mtime = file.lastModified();
        let cached: Stamped[FontAtlas] = caches#fontAtlases.get(ttfPath);
        if (not Object.isNull(cached) and cached#mtime == mtime)
            cached#value
        else {
            let atlas = HeadlessFont.buildUiAtlas(ttfPath, "");
            discard caches#fontAtlases.put(ttfPath, ({ mtime = mtime, value = atlas }: Stamped[FontAtlas]));
            atlas
        }

    /// 画像パスから実寸 (width, height) を引く。読めなければ None。
    // WhyNot: 読めなかった事実は覚えない — 壊れた画像を直した瞬間、次の要求で反映させたいため。
    pub def imageSize(path: String, caches: Caches): Option[(Float64, Float64)] \ IO =
        let file = new File(path);
        if (file.exists()) {
            let mtime = file.lastModified();
            let cached: Stamped[(Float64, Float64)] = caches#textureSizes.get(path);
            if (not Object.isNull(cached) and cached#mtime == mtime)
                Some(cached#value)
            else
                readImageSize(file) |> Option.map(size -> {
                    discard caches#textureSizes.put(path, ({ mtime = mtime, value = size }: Stamped[(Float64, Float64)]));
                    size
                })
        } else None

    /// 画像ファイルをデコードして実寸を測る。デコードできなければ None。
    def readImageSize(file: File): Option[(Float64, Float64)] \ IO =
        let img = ImageIO.read(file);
        if (Object.isNull(img)) None
        else Some((Int32.toFloat64(img.getWidth()), Int32.toFloat64(img.getHeight())))
}
