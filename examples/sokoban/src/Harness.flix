// Harness — 画面なしでゲーム全体を動かすために必要なものすべて。
//
// 意図的に短く、その短さこそが要点である: tick は純粋な関数なので、ルールには
// ハーネスが一切要らない。外の世界に触れるのは「絵」だけであり、それが必要とす
// るものはちょうど2つ —— ヘッドレスに焼き込まれたフォントの atlas と、ui.json
// の Spec を読むための Fs ハンドラ。ページはボックスとテキストしか持たないの
// で、`UiRender.renderUiWith` は atlas だけからそれらを描く: Game ハンドラもウ
// ィンドウもいらない。
mod Harness {

    def ttfPath(): String = "assets/Xolonium-Regular.ttf"

    /// ウィンドウなしで焼き込まれたフォント（AWT ヘッドレスの計測値のみ）。
    pub def atlas(): FontAtlas \ IO =
        HeadlessFont.buildUiAtlas(ttfPath(), "assets/joyo.txt")

    /// 両方のページ Spec を1つの UiWorld へ生成する、ランチャーと同じように。
    pub def ui(): Option[UiStore.UiWorld] \ IO =
        run {
            forM (a <- UiSpec.spawnAsset(GameUi.titleUiPath(), UiStore.empty()) |> Result.toOption;
                  b <- UiSpec.spawnAsset(GameUi.clearUiPath(), snd(a)) |> Result.toOption)
            yield snd(b)
        } with Fs.FileRead.runWithIO
}
