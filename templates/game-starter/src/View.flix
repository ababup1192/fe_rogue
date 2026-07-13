// View — World から「(置き場所, 見せたい物) のリスト」への投影（純粋）。
// ここに状態は無い: プレイヤーの四角は、渡された World の位置から毎フレーム作り直すだけ。
// 背景色は project.json の clearColor が塗るので、ここではプレイヤーだけ描く。

mod View {

    // 描く高さ（z）。数が大きいほど手前。今は1つだけなので値はなんでもよい。
    def zPlayer(): Int32 = 10

    /// プレイヤーの色（明るい青）。
    def playerColor(): Color = { r = 0.388235f32, g = 0.607843f32, b = 1.000000f32 }

    /// World を描画コマンドの列へ写す。atlas は文字を描くとき使うが、今は使わない。
    pub def frame(_atlas: FontAtlas, world: World.World): List[Render.Placed] =
        let s = World.size();
        // Box は左上原点なので、中心座標から半分ずらして左上を出す。
        let topLeft = { x = world#x - s / 2.0, y = world#y - s / 2.0 };
        let square = Render.solidBox({ x = s, y = s }, playerColor(), zPlayer());
        { at = topLeft, item = square } :: Nil
}
