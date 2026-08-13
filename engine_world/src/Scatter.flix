// Scatter — どこまでスクロールしても同じ配置が再現される、無限の「物の撒き方」。
// 見えている範囲のセル格子だけをその場で計算し、セルごとに個性の蛇口（決定的乱数）を
// 配って、何をいくつ置くかは呼び側の place に任せる。状態も画像も持たない。
// 利用例: 星空・草むら・遠景の街灯・瓦礫を、World に保存せず描く。
//   Scatter.field(ctx#visible, { cell = 40.0, salt = 11 }, (cell, rand) ->
//       if (rand(0) > 0.5) Nil
//       else { at = ..., item = RawDraw.box(...) } :: Nil)
// 注意: セルの個性は列・行・salt から決まる番号を Hash01 に渡して引く。この番号の作り方と
//   走査範囲（見えている範囲の外側に1セル分の余白）は、星空などの既存の絵をバイト単位で
//   保つために固定しており、変えると過去に描き出した絵がずれる。

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

    /// 1 本の帯（横一列）にセルを敷く。疑似遠近の絵（奥の帯ほど広い世界が画面に入る）では
    /// 帯ごとに見える幅が違うので、矩形 1 枚を渡す field でなく、帯 1 本ぶんの範囲 span
    /// （world 座標）を渡してその帯だけ敷く。実戦の例は
    /// templates/race-starter/src/ViewScene.flix の outfield。
    ///
    /// - reach: span の外でもこの幅（world px）までは敷く余白。置き物の端が画面へ届く
    ///   ぶんだけ広げ、その外のセルは place を呼ばずに捨てる — 作ってから画面外と分かる
    ///   より、作る前に捨てるほうが速い
    /// - cellsMax: 帯 1 本で歩くセル数の上限。超えるなら間隔を 2 倍・4 倍…と広げる。
    ///   倍々にするのは、間引いた後も残るセルの番号を元のままにするため — 端数で広げると
    ///   番号の意味が変わり、置き物の個性が入れ替わってちらつく
    /// - 乱数の鍵は col + lane * 37 + salt。field の合成（92821 系）と違うのは、帯の絵では
    ///   lane（範囲番号）が主で col の幅が広く、この形なら呼び側が「帯 × 升」の通し番号を
    ///   そのまま鍵として共有できるため。同じセルは常に同じ乱数（決定性）
    pub def strip(span: {lo = Float64, hi = Float64},
                  spec: {cell = Float64, salt = Int32, lane = Int32,
                         reach = Float64, cellsMax = Int32},
                  place: (Int32, Int32 -> Float64) -> List[a]): List[a] =
        if (span#lo > span#hi) Nil
        else {
            // 高い側だけ 1 セル余分に歩くのは field と同じ流儀 — 低い側は床関数が範囲外へ
            // 自然にはみ出すが、高い側は 1 つ足さないと縁のセルが欠ける。
            let mLo = tileIndex((span#lo - spec#reach) / spec#cell);
            let mHi = tileIndex((span#hi + spec#reach) / spec#cell) + 1;
            let width = (span#hi + spec#reach) - (span#lo - spec#reach);
            let step = stepUpTo(width / spec#cell / Int32.toFloat64(spec#cellsMax), 1);
            let jOf = m -> Num.floorInt(Int32.toFloat64(m) / Int32.toFloat64(step));
            List.range(jOf(mLo), jOf(mHi) + 1) |> List.flatMap(j -> {
                let col = j * step;
                place(col, k -> Hash01.at(col + spec#lane * 37 + spec#salt, k))
            })
        }

    /// 歩くセル数が上限に収まるまで間隔を 2 倍ずつ広げる。64 で打ち切るのは、そこまで
    /// 広げても収まらない入力（cellsMax が極端に小さい等）で無限に倍々しないため。
    def stepUpTo(times: Float64, s: Int32): Int32 =
        if (s >= 64 or Int32.toFloat64(s) >= times) s else stepUpTo(times, s * 2)

    /// world 座標 / セル辺 の商をセル index（床関数）へ。
    def tileIndex(q: Float64): Int32 =
        Num.floorInt(q)
}
