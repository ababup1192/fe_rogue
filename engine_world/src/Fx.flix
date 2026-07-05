// Fx — たくさんの粒を、どこにも保存せず「今の時刻から計算」して並べる薄い仕組み。
// 粒ひとつずつに個性の蛇口（番号から引くばらつき）を配り、形も色も動きもすべて呼び側の
// piece に任せる。spawn も update も free も無く、要らなくなったら呼ぶのをやめるだけ。
// 利用例: 紙吹雪・火花・雨・星屑のような群れを、状態を持たずに描く。
// 注意: 各粒は番号と時刻 t だけから決まる純粋な写像。piece の返り値は多相ゆえ、描画コマンド
//   でも中間データでも好きな型を積める。

mod Fx {

    /// `count` 個の粒を作り、各粒 `i` に個性の蛇口 `rand`（`rand(k)` = 番号 i・チャンネル k の
    /// [0,1) 乱数）と時刻 `t` を渡して `piece` で写す。番号 `i` も併せて渡すので、丸め込みの
    /// 割り当てのような「乱数ではなく順番そのもの」が要る政策にも使える。
    pub def derive(count: Int32, t: Float64, piece: (Int32, Int32 -> Float64, Float64) -> a): List[a] =
        deriveSeeded({seed = 0, count = count}, t, piece)

    /// seed を変えると、同じ番号の粒でも別の個性を引く `derive`。着弾や爆発のような
    /// 「撃つたびに出る」群れが毎回そっくり同じ姿になるのを避けたいとき、発生ごとの
    /// 通し番号を seed に渡す。同じ seed なら同じ絵（巻き戻し・リプレイでも揺れない）。
    /// 注意: `deriveSeeded({seed = 0, ...}, ...)` は `derive` と同じ列。粒数が 8191 個
    /// までなら異なる seed 同士で個性が重ならない。
    pub def deriveSeeded(spec: {seed = Int32, count = Int32}, t: Float64,
                          piece: (Int32, Int32 -> Float64, Float64) -> a): List[a] =
        List.map(i -> piece(i, k -> Hash01.at(spec#seed * 8191 + i, k), t), List.range(0, spec#count))
}
