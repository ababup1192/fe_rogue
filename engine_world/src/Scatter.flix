// Scatter — どこまでスクロールしても同じ配置が再現される、無限の「物の撒き方」。
// 見えている範囲のセル格子だけをその場で計算し、セルごとに個性の蛇口（決定的乱数）を
// 配って、何をいくつ置くかは呼び側の place に任せる。状態も画像も持たない。
// 利用例: 星空・草むら・遠景の街灯・瓦礫を、World に保存せず描く。
//   Scatter.field(ctx#visible, { cell = 40.0, salt = 11 }, (cell, rand) ->
//       if (rand(0) > 0.5) Nil
//       else { at = ..., item = Render.box(...) } :: Nil)
// 注意: セルの個性は列・行・salt から決まる番号を Hash01 に渡して引く。この番号の作り方と
//   走査範囲（見えている範囲の外側に1セル分の余白）は、星空などの既存の絵をバイト単位で
//   保つために固定しており、変えると過去に焼いた絵がずれる。

mod Scatter {

    /// 見えている範囲 visible を覆うセルを走査し、各セルに place を呼んで結果を全部つなぐ。
    /// place はセル番地と蛇口 rand（rand(k) = このセル固有・チャンネル k の [0,1) 乱数）を
    /// 受け取り、置く物のリスト（置かないなら Nil）を返す。同じセルは常に同じ物を返すので、
    /// どこへ動いても同じ配置が再現される。
    pub def field(visible: Rect2.Rect2, spec: {cell = Float64, salt = Int32},
                  place: ({col = Int32, row = Int32}, Int32 -> Float64) -> List[a]): List[a] =
        let cs = spec#cell;
        let c0 = tileIndex(visible#position#x / cs);
        let r0 = tileIndex(visible#position#y / cs);
        let cols = tileIndex(visible#size#x / cs) + 2;
        let rows = tileIndex(visible#size#y / cs) + 2;
        let cellAt = cell -> {
            let idx = cell#col * 92821 + cell#row * 31 + spec#salt;
            place(cell, k -> Hash01.at(idx, k))
        };
        (forM (r <- List.range(0, rows); c <- List.range(0, cols))
            yield {col = c0 + c, row = r0 + r})
        |> List.flatMap(cellAt)

    /// world 座標 / セル辺 の商をセル index（床関数）へ。
    def tileIndex(q: Float64): Int32 =
        Num.floorInt(q)
}
