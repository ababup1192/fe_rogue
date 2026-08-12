// Harness — 画面なしでゲーム全体を動かすために必要なものすべて。
// tick は純粋な関数なのでルールにはハーネスが要らない。外の世界に触れるのは「絵」だけで、
// それが必要とするのは 2 つ — ヘッドレスに生成したフォントの atlas と、ui.json を読む Fs ハンドラ。
mod Harness {

    def ttfPath(): String = "assets/PixelMplus10-Regular.ttf"

    /// ウィンドウなしで生成されたフォント（AWT ヘッドレスの計測値のみ）。
    /// フォントが持つ全グリフが載る（第 2 引数は旧・常用漢字ファイルの名残で、いまは読まれない）。
    pub def atlas(): FontAtlas \ IO =
        HeadlessFont.buildUiAtlas(ttfPath(), "")

    /// 全ページの Spec を 1 つの UiWorld へ生成する、ランチャーと同じように。
    pub def ui(): UiStore.UiWorld \ IO =
        run { GameUi.loadUi() } with Fs.FileRead.runWithIO
}
