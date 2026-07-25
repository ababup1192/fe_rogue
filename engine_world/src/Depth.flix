// Depth — 見下ろし画面で「足元が下にある物ほど手前」を、重なり順（zIndex）の数として決める。
// 人・木・柵・家をひとつの帯（Band）の中に並べると、すれ違うたびに前後が入れ替わる。
// 利用例: 主人公が木の手前に出たり裏に隠れたりする / 柵の向こうに立つ / 落ちている物をまたぐ。
// 注意: 決めるのは数だけで、並べ替えは描画部の仕事（同じ zIndex 同士は渡した順のまま）。
//
// 帯（Band）の考え方: back..front の整数の幅を、world の top..bottom の高さに割り当てる。
// 帯の外（もっと奥の地面、もっと手前の HUD）とは重ならない数の範囲を選ぶこと。
// 帯の幅は「マスの数 + 1」くらいあれば足りる（同じ行に立つ物は同じ数になってよい）。
mod Depth {

    /// 足元の高さ（world の y）を重なり順に写す帯。
    /// back / front = 割り当てる zIndex の範囲（back が奥・front が手前）。
    /// top / bottom = その範囲に対応する world の y（top が奥・bottom が手前）。
    pub type alias Band = { back = Int32, front = Int32, top = Float64, bottom = Float64 }

    /// マス目の盤から帯を作る近道。1 行ぶんに 1 段の zIndex を割り当てる。
    /// back = 帯の一番奥の zIndex、originY = 盤の上端の world y、rows = 行数、tileSize = 1 マスの辺。
    pub def forRows(spec: { back = Int32, originY = Float64, rows = Int32, tileSize = Float64 }): Band =
        { back = spec#back,
          front = spec#back + Int32.max(1, spec#rows),
          top = spec#originY,
          bottom = spec#originY + Int32.toFloat64(Int32.max(1, spec#rows)) * spec#tileSize }

    /// 足元の高さ footY に対する重なり順。帯の外に出た足元は端で止める
    /// （画面外へ歩いても順序が壊れない）。
    pub def zAt(band: Band, footY: Float64): Int32 =
        let span = band#bottom - band#top;
        let t = if (Float64.abs(span) < 0.000001) 0.0
                else clamp01((footY - band#top) / span);
        let steps = Int32.toFloat64(band#front - band#back);
        band#back + (Float64.round(t * steps) |> Float64.tryToInt32 |> Option.getWithDefault(0))

    /// 組み上がった絵の集まりを、足元の高さで決まる層へ持ち上げる。
    /// 部品どうしの相対的な前後（胴 0・頭 1・持ち物 2 のような小さな差）はそのまま保たれるので、
    /// 呼び側は 0 から数えた小さな z で 1 体を組めばよい。
    pub def place(band: Band, footY: Float64, items: List[Render.PlacedItem]): List[Render.PlacedItem] =
        Render.zShiftedAll(zAt(band, footY), items)

    /// place の 1 個版。置き場所の下端（=足元）を自分で渡す。
    pub def placeOne(band: Band, footY: Float64, placed: Render.PlacedItem): Render.PlacedItem =
        { item = Render.zShifted(zAt(band, footY), placed#item) | placed }

    def clamp01(v: Float64): Float64 =
        Float64.max(0.0, Float64.min(1.0, v))
}
