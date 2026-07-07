// Harness — 画面なしでゲームの絵を焼くために要るもの。
//
// update は純粋なのでルールにハーネスは要らない。外の世界に触れるのは「絵」だけで、それが
// 必要とするのはヘッドレスに焼き込んだフォントの atlas ひとつ。ブロック崩しの盤はボックスと
// テキストしか使わないので、SoftRaster はこの atlas だけからすべて描ける。

mod Harness {

    def ttfPath(): String = "assets/Xolonium-Regular.ttf"

    /// ウィンドウなしで焼き込んだフォント（AWT ヘッドレスの計測値のみ）。漢字ファイルは
    /// 渡さない（存在しないパス）ので ASCII＋かなだけが載る —— breakout の文字はすべて ASCII。
    pub def atlas(): FontAtlas \ IO =
        HeadlessFont.ensureHeadless();
        HeadlessFont.buildUiAtlas(ttfPath(), "assets/none.txt")
}
