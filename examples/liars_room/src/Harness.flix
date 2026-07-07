// Harness — 画面なしでゲーム全体を動かすために必要なものすべて。
// tick は純粋な関数なのでルールにはハーネスが要らない。外の世界に触れるのは「絵」だけで、
// それが必要とするのは 2 つ — ヘッドレスに焼いたフォントの atlas と、ui.json を読む Fs ハンドラ。
mod Harness {

    def ttfPath(): String = "assets/PixelMplus10-Regular.ttf"

    /// ウィンドウなしで焼き込まれたフォント（AWT ヘッドレスの計測値のみ）。
    /// 漢字は assets/joyo.txt に列挙したぶんだけ載る（ゲームが使う文言と揃えること）。
    pub def atlas(): FontAtlas \ IO =
        HeadlessFont.ensureHeadless();
        HeadlessFont.buildUiAtlas(ttfPath(), "assets/joyo.txt")

    /// 全ページの Spec を 1 つの UiWorld へ生成する、ランチャーと同じように。
    pub def ui(): UiStore.UiWorld \ IO =
        run { GameUi.loadUi() } with Fs.FileRead.runWithIO
}
