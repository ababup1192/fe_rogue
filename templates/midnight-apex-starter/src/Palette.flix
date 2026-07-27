// Palette — Studio のドット絵エディタに「意味色キー → 実色」を教えるための写し。
// ゲームはこの写しを読まない（実色を決める権威は CityscapeView.colorOf と
// SceneryView.patternColor のまま）。
//
// なぜ要るか: Studio が見られるのは *.sprite.json の legend に書いた名前と
// *.theme.json にトップレベルで宣言してある色だけで、コードの中の導出
// （夜景は暗く、回路は道の色から…）は知りようがない。名前が解けないと Studio は
// 並び順から作った仮色で塗るので、編集画面と実機で配色が食い違う。
// だから導出の結果をここへ書き出して読ませる。
//
// 生成物なので手で直さない（`make palette`。`make bake` の前に走る）。
// テーマの色を変えたら作り直す — 忘れても TestPalette が食い違いを見つける。
mod Palette {

    pub def path(): String = "assets/apex.palette.json"

    /// 回路模様のキー。これだけ SceneryView が権威で、残りは夜景（CityscapeView）。
    /// 名前でどちらに聞くかを決める — 同じ名前が両方に出ることはない。
    def patternKeys(): List[String] =
        "circuitTrace" :: "circuitTraceDim" :: "circuitVia" :: "copperPlane" :: Nil

    /// 写しに載せる回路模様の側（道の左肩側）。実機は道の左右で色を振り分けるので、
    /// 静的な写し 1 枚では表せない — Studio には代表としてこちら側の色を見せる。
    /// つまり編集画面の回路模様は「左側の色」で、右側は走らせて確かめる。
    def representativeSide(): Float64 = -1.0

    /// 意味色キー → 実色。実機と同じ関数へ渡すだけ（ここで色を計算し直さない）。
    pub def colorOf(theme: ThemeDoc.Doc, key: String): Color =
        if (List.memberOf(key, patternKeys()))
            SceneryView.patternColor(representativeSide(), key, theme)
        else
            CityscapeView.colorOf(key, theme)

    /// sprite Doc の legend に出てくる意味色キーを、テーマの実色へ解いた表（純粋）。
    /// 名前の重複は 1 つに畳み、並びは名前順（書き出しが毎回同じになる）。
    pub def entriesOf(sprites: PxSpriteDoc.Doc, theme: ThemeDoc.Doc): List[(String, Color)] =
        sprites#legend
            |> Map.valuesOf
            |> List.distinct
            |> List.sort
            |> List.map(key -> (key, colorOf(theme, key)))

    /// 表を JSON のテキストへ。色は {"rgb":[…]} で書く — Studio の色解決が受け付ける形の中で、
    /// #rrggbb のように 256 段へ丸めないので実機の値とそのまま一致する。
    pub def toJson(entries: List[(String, Color)]): String =
        let body = entries
            |> List.map(entry -> {
                let (key, color) = entry;
                "  \"${key}\": { \"rgb\": [${channel(color#r)}, ${channel(color#g)}, ${channel(color#b)}] }"
            })
            |> List.join(",\n");
        "{\n  \"version\": 1,\n"
            + "  \"//\": \"生成物（make palette）。Studio のドット絵エディタに意味色キーの実色を"
            + "教えるための写し。色を変えるのは apex.theme.json 側。回路模様（circuitTrace / "
            + "circuitTraceDim / circuitVia / copperPlane）は実機が道の左右で色を振り分けるので、"
            + "ここに載るのは左側の代表色。\",\n"
            + body + "\n}\n"

    def channel(v: Float32): String =
        Float32.toString(v)

    /// 写しを書き出す。読むのは Studio だけなので、走らせるのは開発の手元だけでよい。
    pub def write(): Unit \ IO =
        let (sprites, theme) = run {
            (PxSpriteDoc.load(SceneryDoc.spritePath()), ThemeDoc.load(ThemeDoc.path()))
        } with Fs.FileRead.runWithIO;
        let text = toJson(entriesOf(sprites, theme));
        run {
            discard Fs.WriteFile.write({ str = text }, path())
        } with Fs.WriteFile.runWithFileWrite with Fs.FileWrite.runWithIO;
        println("wrote ${path()}")
}
