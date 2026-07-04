// Grid — 正方タイルの「何列目・何行目」と画面上のピクセル位置を相互に変換する。
// マス目とピクセルの行き来を一箇所にまとめるので、盤面の描画や当たり判定のたびに
// 同じ掛け算・割り算を書かずに済む。
// 利用例: マスの中心にキャラを置く / クリックした点がどのマスかを求める / 隣のマスを取る。
// 注意: 知っているのはタイルの大きさだけで、盤が画面のどこにあるかは扱わない（位置合わせは呼び側）。

mod Grid {

    /// `cell` の中心のピクセル位置。原点 (0, 0) がセル (0, 0) の左上であるグリッド上で。
    /// セル (c, r) は x が [c*tileSize, (c+1)*tileSize) に広がるので、中心は半タイル分
    /// ずれる。
    pub def cellCenter(tileSize: Float64, cell: (Int32, Int32)): Vec2.Vec2 =
        let (col, row) = cell;
        { x = (Int32.toFloat64(col) + 0.5) * tileSize,
          y = (Int32.toFloat64(row) + 0.5) * tileSize }

    /// ピクセル位置がどのセルに入るか — 中心に限らずセル内の任意の点について `cellCenter`
    /// の逆。floor を使うので、原点の左や上の点は 0 方向へ丸めず負のセルに入る。
    pub def cellOf(tileSize: Float64, pos: Vec2.Vec2): (Int32, Int32) =
        (floorDiv(pos#x, tileSize), floorDiv(pos#y, tileSize))

    /// `cell` から方向 `d` へ 1 歩進んだセル。
    pub def neighbor(cell: (Int32, Int32), d: Dir4.Dir4): (Int32, Int32) =
        let (col, row) = cell;
        let (dx, dy) = Dir4.delta(d);
        (col + dx, row + dy)

    /// `cell` が `cols` x `rows` のグリッド内にあるか: 列が [0, cols)、行が [0, rows)。
    /// 列も行も持たないグリッドは何も含まない。
    pub def inRect(cell: (Int32, Int32), cols: Int32, rows: Int32): Bool =
        let (col, row) = cell;
        col >= 0 and col < cols and row >= 0 and row < rows

    /// 浮動小数の除算を、含まれる整数セル添字へ切り下げる。
    def floorDiv(value: Float64, tileSize: Float64): Int32 =
        Float64.floor(value / tileSize) |> Float64.tryToInt32 |> Option.getWithDefault(0)
}
