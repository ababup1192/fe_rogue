// Harness — 画面なしでゲームの絵を焼くために要るもの。
//
// update は純粋なのでルールにハーネスは要らない。外の世界に触れるのは「絵」だけで、それが
// 必要とするのはヘッドレスに焼き込んだフォントの atlas と、ui.json を読む Fs ハンドラ。

mod Harness {

    def ttfPath(): String = "assets/Xolonium-Regular.ttf"

    /// ウィンドウなしで焼き込んだフォント（AWT ヘッドレスの計測値のみ）。
    pub def atlas(): FontAtlas \ IO =
        HeadlessFont.buildUiAtlas(ttfPath(), "assets/none.txt")

    /// UI ページを 1 つの UiWorld へ生成する、ランチャーと同じように。
    pub def ui(): UiStore.UiWorld \ IO =
        run { GameUi.loadUi() } with Fs.FileRead.runWithIO

    /// カンテラの光の質感を読む、ランチャーと同じように（fail-open は Controls.loadLightDoc に
    /// 一本化 — bake とランチャーが違う既定値にすり替わらないようにするため）。
    pub def lightDoc(): LightDoc.Spec \ IO =
        run { Controls.loadLightDoc() } with Fs.FileRead.runWithIO
}
