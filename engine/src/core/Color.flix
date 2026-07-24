// Color — 3 チャンネル sRGB-linear カラー (alpha は別途持つ運用)
//
// Float32 ベース。GL の uniform に直接渡せるレンジ 0.0〜1.0。
// engine（契約層）の共有型なので、フロントのシーングラフとバックエンド（render_gl）が同じ色定義を見る。

pub type alias Color = {r = Float32, g = Float32, b = Float32}

mod Color {

    /// 色を白へamountだけ寄せる。通常は0から1を渡し、範囲外は補正しない。
    /// 既存ゲームと同じ色を保つため、amountをFloat32へ変えてから各チャンネルを補間する。
    pub def lighten(color: Color, amount: Float64): Color =
        let value = Float64.truncateToFloat32(amount);
        { r = color#r + (1.0f32 - color#r) * value,
          g = color#g + (1.0f32 - color#g) * value,
          b = color#b + (1.0f32 - color#b) * value }

    /// 色を黒へamountだけ寄せる。通常は0から1を渡し、範囲外は補正しない。
    /// 丸め順を保つため、Float64で残す割合を求めてからFloat32へ変える。
    pub def darken(color: Color, amount: Float64): Color =
        let remaining = Float64.truncateToFloat32(1.0 - amount);
        { r = color#r * remaining,
          g = color#g * remaining,
          b = color#b * remaining }

    /// HSV から色を作る。h は色相（1 周 = 1.0・0 = 赤・範囲外は折り返し）、s は鮮やかさ、
    /// v は明るさ（どちらも 0〜1）。「値に沿って色相を流す」（虹のグラデーション・
    /// 残量ゲージの緑→赤）が 1 行で導ける。
    /// 同型の Float64 が並ぶので、取り違え防止にレコードで名前渡しする。
    pub def hsv(spec: {h = Float64, s = Float64, v = Float64}): Color =
        let h6 = (spec#h - Float64.floor(spec#h)) * 6.0;
        let f = h6 - Float64.floor(h6);
        let p = spec#v * (1.0 - spec#s);
        let q = spec#v * (1.0 - spec#s * f);
        let u = spec#v * (1.0 - spec#s * (1.0 - f));
        let (r, g, b) =
            if (h6 < 1.0) (spec#v, u, p)
            else if (h6 < 2.0) (q, spec#v, p)
            else if (h6 < 3.0) (p, spec#v, u)
            else if (h6 < 4.0) (p, q, spec#v)
            else if (h6 < 5.0) (u, p, spec#v)
            else (spec#v, p, q);
        { r = clamp01(r), g = clamp01(g), b = clamp01(b) }

    /// GL に渡せる 0〜1 の Float32 へ収める。
    def clamp01(x: Float64): Float32 =
        Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, x)
}
