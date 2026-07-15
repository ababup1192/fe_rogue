// Starfield — どこまでスクロールしても同じ空が再現される無限の星原。
// 状態も画像も持たず、見えている範囲ぶんだけをその場で作る。
// 利用例: addParallaxLayer((ctx, w) -> Starfield.field(ctx#visible, spec)) を遠景・近景の2層で
//   cell / salt / sizes / colors を変えて重ねると奥行きが出る。

mod Starfield {

    /// 星原 1 層ぶんの見た目。
    pub type alias Spec = {
        cell = Float64,                       // セル1辺（px）。大きいほど星がまばら
        salt = Int32,                         // 同じ画面に複数レイヤを重ねるときパターンをずらす種
        z = Int32,
        sizes = (Float64, Float64, Float64),  // 暗い星/中くらい/明るい星の一辺
        colors = (Color, Color, Color)        // 同・色
    }

    /// 見えている範囲を覆うセル格子に星を撒く。星の有無・位置・明るさが全部
    /// セル番号のハッシュ（Hash01）から決まるので、どこへ動いても同じ空が再現される。
    pub def field(visible: Rect2.Rect2, spec: Spec): List[Render.PlacedItem] =
        let cs = spec#cell;
        let c0 = tileIndex(visible#position#x / cs);
        let r0 = tileIndex(visible#position#y / cs);
        let cols = tileIndex(visible#size#x / cs) + 2;
        let rows = tileIndex(visible#size#y / cs) + 2;
        (forM (r <- List.range(0, rows); c <- List.range(0, cols))
            yield starAt(c0 + c, r0 + r, spec))
        |> List.filterMap(s -> s)

    /// セル1個ぶんの星（無いセルもある）。セル内のどこに置くか・明るさもハッシュで決める。
    def starAt(col: Int32, row: Int32, spec: Spec): Option[Render.PlacedItem] =
        let idx = col * 92821 + row * 31 + spec#salt;
        if (Hash01.at(idx, 0) > 0.5) None
        else {
            let px = (Int32.toFloat64(col) + Hash01.at(idx, 1)) * spec#cell;
            let py = (Int32.toFloat64(row) + Hash01.at(idx, 2)) * spec#cell;
            let b = Hash01.at(idx, 3);
            let (dimC, midC, brightC) = spec#colors;
            let (dimS, midS, brightS) = spec#sizes;
            let (color, size) =
                if (b < 0.6) (dimC, dimS)
                else if (b < 0.9) (midC, midS)
                else (brightC, brightS);
            Some({ at = { x = px, y = py },
                   item = Render.box({ x = size, y = size }, color, spec#z) })
        }

    /// world 座標 / セル辺 の商をセル index（床関数）へ。
    def tileIndex(q: Float64): Int32 =
        Float64.floor(q) |> Float64.tryToInt32 |> Option.getWithDefault(0)
}
